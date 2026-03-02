import Foundation
import CryptoKit
import AppKit

// MARK: - PKCE

struct PKCESession {
    let verifier: String
    let challenge: String
    let state: String
}

func generatePKCE() -> PKCESession {
    // 72 random bytes → 96 base64url chars (RFC 7636 §4.1)
    var bytes = Data(count: 72)
    _ = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 72, $0.baseAddress!) }
    let verifier = bytes.base64URLEncoded

    let challengeData = Data(SHA256.hash(data: Data(verifier.utf8)))
    let challenge = challengeData.base64URLEncoded

    var stateBytes = Data(count: 16)
    _ = stateBytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
    let state = stateBytes.map { String(format: "%02x", $0) }.joined()

    return PKCESession(verifier: verifier, challenge: challenge, state: state)
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - OIDC Discovery

struct OIDCEndpoints {
    let authorization: URL
    let token: URL
}

func fetchOIDCEndpoints(issuer: String) async throws -> OIDCEndpoints {
    let base = issuer.hasSuffix("/") ? String(issuer.dropLast()) : issuer
    guard let url = URL(string: base + "/.well-known/openid-configuration") else {
        throw SixnetError.oidcDiscoveryFailed
    }
    let (data, response) = try await URLSession.shared.data(from: url)
    guard (response as? HTTPURLResponse)?.statusCode == 200,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let authStr = json["authorization_endpoint"] as? String,
          let tokenStr = json["token_endpoint"] as? String,
          let authURL = URL(string: authStr),
          let tokenURL = URL(string: tokenStr) else {
        throw SixnetError.oidcDiscoveryFailed
    }
    return OIDCEndpoints(authorization: authURL, token: tokenURL)
}

// MARK: - Auth URL

// Protocol contracts — do not make configurable
let enrollClientID    = "sixnet-device-enroll"
let enrollRedirectURI = "http://localhost:12345/callback"

func buildAuthURL(endpoint: URL, pkce: PKCESession) -> URL {
    var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
    components.queryItems = [
        URLQueryItem(name: "client_id",              value: enrollClientID),
        URLQueryItem(name: "redirect_uri",           value: enrollRedirectURI),
        URLQueryItem(name: "response_type",          value: "code"),
        URLQueryItem(name: "scope",                  value: "openid email profile"),
        URLQueryItem(name: "code_challenge",         value: pkce.challenge),
        URLQueryItem(name: "code_challenge_method",  value: "S256"),
        URLQueryItem(name: "state",                  value: pkce.state),
    ]
    return components.url!
}

// MARK: - Callback Server

// Reference type so withTaskCancellationHandler can close the fd.
final class CallbackServerHandle: @unchecked Sendable {
    var fd: Int32 = -1
    func close() {
        if fd >= 0 { Darwin.close(fd); fd = -1 }
    }
}

/// Starts a TCP listener on :12345, opens the browser, waits for the OAuth callback.
/// Task cancellation closes the socket cleanly (no error code set on cancel).
func startCallbackServer(openingURL: URL) async throws -> (code: String, state: String) {
    let handle = CallbackServerHandle()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
                guard fd >= 0 else {
                    cont.resume(throwing: SixnetError.callbackTimeout)
                    return
                }
                handle.fd = fd

                var reuseAddr: Int32 = 1
                setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = UInt16(12345).bigEndian
                addr.sin_addr.s_addr = INADDR_ANY

                let bindOK = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                    }
                }
                guard bindOK else {
                    Darwin.close(fd); handle.fd = -1
                    cont.resume(throwing: SixnetError.callbackTimeout)
                    return
                }

                Darwin.listen(fd, 1)

                // 120-second accept timeout
                var tv = timeval(tv_sec: 120, tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                // Open browser now that the socket is listening
                DispatchQueue.main.async { NSWorkspace.shared.open(openingURL) }

                let clientFD = Darwin.accept(fd, nil, nil)
                Darwin.close(fd); handle.fd = -1

                guard clientFD >= 0 else {
                    // EBADF = closed by cancellation handler → not an error
                    cont.resume(throwing: errno == EBADF ? CancellationError() : SixnetError.callbackTimeout)
                    return
                }
                defer { Darwin.close(clientFD) }

                // Read the HTTP request
                var buf = [UInt8](repeating: 0, count: 4096)
                let n = Darwin.recv(clientFD, &buf, buf.count, 0)

                // Respond immediately so the browser shows a done page
                let html = "<html><body><h2>Authentication complete. You may close this tab.</h2></body></html>"
                let httpResp = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n\(html)"
                _ = httpResp.withCString { Darwin.send(clientFD, $0, Int(strlen($0)), 0) }

                guard n > 0 else {
                    cont.resume(throwing: SixnetError.callbackTimeout)
                    return
                }

                // Parse the request line: "GET /callback?code=…&state=… HTTP/1.1"
                let request = String(bytes: buf[..<n], encoding: .utf8) ?? ""
                let firstLine = request.components(separatedBy: "\r\n").first ?? ""
                let parts = firstLine.components(separatedBy: " ")
                guard parts.count >= 2,
                      let components = URLComponents(string: "http://localhost" + parts[1]),
                      let items = components.queryItems else {
                    cont.resume(throwing: SixnetError.callbackTimeout)
                    return
                }

                let code  = items.first(where: { $0.name == "code"  })?.value ?? ""
                let state = items.first(where: { $0.name == "state" })?.value ?? ""

                guard !code.isEmpty else {
                    cont.resume(throwing: SixnetError.callbackTimeout)
                    return
                }

                cont.resume(returning: (code: code, state: state))
            }
        }
    } onCancel: {
        handle.close()
    }
}

// MARK: - Token Exchange

func exchangeCode(tokenEndpoint: URL, code: String, verifier: String) async throws -> String {
    var req = URLRequest(url: tokenEndpoint)
    req.httpMethod = "POST"
    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    req.httpBody = [
        "grant_type=authorization_code",
        "code=\(code)",
        "redirect_uri=\(enrollRedirectURI)",
        "client_id=\(enrollClientID)",
        "code_verifier=\(verifier)",
    ].joined(separator: "&").data(using: .utf8)

    let (data, response) = try await URLSession.shared.data(for: req)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw SixnetError.tokenExchangeFailed
    }
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let idToken = json["id_token"] as? String, !idToken.isEmpty else {
        throw SixnetError.missingIdToken
    }
    return idToken
}

// MARK: - Claim

func postClaim(enrollURL: String, idToken: String, nodeId: String) async throws {
    let base = enrollURL.hasSuffix("/") ? String(enrollURL.dropLast()) : enrollURL
    guard let url = URL(string: base + "/claim") else {
        throw SixnetError.enrollmentRejected(0)
    }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try? JSONSerialization.data(withJSONObject: ["nodeId": nodeId])

    let (_, response) = try await URLSession.shared.data(for: req)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    switch status {
    case 200: return
    case 404: throw SixnetError.enrollmentNotAvailable
    default:  throw SixnetError.enrollmentRejected(status)
    }
}
