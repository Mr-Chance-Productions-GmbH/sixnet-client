import SwiftUI

// MARK: - Phase

private enum EnrollPhase {
    case discovering    // fetching OIDC config
    case waiting        // browser open, waiting for callback
    case exchanging     // token exchange + /claim
    case success
    case failed(SixnetError)
}

// MARK: - View

struct EnrollView: View {
    @EnvironmentObject var client: DaemonClient
    @Environment(\.dismiss) var dismiss
    let network: Network

    @State private var phase: EnrollPhase = .discovering

    var body: some View {
        VStack(spacing: 20) {
            phaseIcon
            phaseText
            actionButton
        }
        .padding(24)
        .frame(width: 320)
        .task { await runEnrollment() }
    }

    // MARK: Sub-views

    @ViewBuilder
    private var phaseIcon: some View {
        switch phase {
        case .discovering, .waiting, .exchanging:
            ProgressView().controlSize(.large)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var phaseText: some View {
        switch phase {
        case .discovering:
            Text("Connecting to enrollment server…")
                .foregroundStyle(.secondary)
        case .waiting:
            VStack(spacing: 6) {
                Text("Complete sign-in in your browser")
                    .fontWeight(.medium)
                Text("Waiting for authentication…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        case .exchanging:
            Text("Completing enrollment…")
                .foregroundStyle(.secondary)
        case .success:
            Text("Enrolled — ready to connect")
                .fontWeight(.medium)
        case .failed(let error):
            VStack(spacing: 4) {
                Text("Enrollment failed")
                    .fontWeight(.medium)
                Text(error.code)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch phase {
        case .waiting:
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.escape)
        case .failed:
            Button("Close") { dismiss() }
                .keyboardShortcut(.escape)
        default:
            EmptyView()
        }
    }

    // MARK: Enrollment flow

    private func runEnrollment() async {
        guard let issuer = network.config.issuer else { return }
        guard let nodeId = client.nodeId else {
            fail(.daemonUnreachable); return
        }

        // Clear any previous error for this network
        client.setNetworkError(network.id, nil)

        // Step 1 — OIDC discovery
        let endpoints: OIDCEndpoints
        do {
            endpoints = try await fetchOIDCEndpoints(issuer: issuer)
        } catch {
            fail(.oidcDiscoveryFailed); return
        }

        // Step 2 — PKCE + auth URL
        let pkce = generatePKCE()
        let authURL = buildAuthURL(endpoint: endpoints.authorization, pkce: pkce)

        // Step 3 — Open browser, wait for callback
        phase = .waiting
        let callback: (code: String, state: String)
        do {
            callback = try await startCallbackServer(openingURL: authURL)
        } catch is CancellationError {
            return  // user cancelled — no error code
        } catch let e as SixnetError {
            fail(e); return
        } catch {
            fail(.callbackTimeout); return
        }

        guard callback.state == pkce.state else {
            fail(.stateMismatch); return
        }

        // Step 4 — Token exchange + /claim
        phase = .exchanging
        do {
            let idToken = try await exchangeCode(
                tokenEndpoint: endpoints.token,
                code: callback.code,
                verifier: pkce.verifier
            )
            try await postClaim(enrollURL: network.config.enrollURL, idToken: idToken, nodeId: nodeId)
        } catch let e as SixnetError {
            fail(e); return
        } catch {
            fail(.enrollmentRejected(0)); return
        }

        // Step 5 — Join the network
        await client.join(networkId: network.id)

        // Done
        client.setNetworkError(network.id, nil)
        phase = .success
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        dismiss()
    }

    private func fail(_ error: SixnetError) {
        phase = .failed(error)
        client.setNetworkError(network.id, error)
    }
}
