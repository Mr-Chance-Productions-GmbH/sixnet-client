import Foundation
import AppKit

// MARK: - Models

struct SavedNetwork: Codable {
    let configURL: String   // base URL the user entered
    let networkId: String
    let name: String
    let enrollURL: String
}

struct NetworkState {
    let authorized: Bool
    let mode: String        // "vpn" | "lan" | "exit" | "" (empty = disconnected)
    let assignedIP: String?

    var isConnected: Bool { mode == "vpn" || mode == "lan" || mode == "exit" }
}

struct Network: Identifiable {
    var id: String { config.networkId }
    var config: SavedNetwork
    var state: NetworkState?
    var isBusy: Bool = false
}

// MARK: - Socket I/O (free functions, not actor-isolated)

private let daemonSocketPath = "/var/run/sixnetd.sock"

private func socketSend(_ request: [String: Any]) -> [String: Any]? {
    guard let data = try? JSONSerialization.data(withJSONObject: request),
          let json = String(data: data, encoding: .utf8) else { return nil }

    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { Darwin.close(fd) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    daemonSocketPath.withCString { src in
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            let len = min(Int(strlen(src)) + 1, dest.count)
            dest.copyBytes(from: UnsafeRawBufferPointer(start: UnsafeRawPointer(src), count: len))
        }
    }

    let connected = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
        }
    }
    guard connected else { return nil }

    let payload = json + "\n"
    payload.withCString { ptr in _ = Darwin.send(fd, ptr, Int(strlen(ptr)), 0) }

    var response = Data()
    var buf = [UInt8](repeating: 0, count: 4096)
    while true {
        let n = Darwin.recv(fd, &buf, buf.count, 0)
        if n <= 0 { break }
        response.append(contentsOf: buf[..<n])
        if buf[..<n].contains(0x0A) { break }
    }

    return (try? JSONSerialization.jsonObject(with: response)) as? [String: Any]
}

private func socketAlive() -> Bool {
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { Darwin.close(fd) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    daemonSocketPath.withCString { src in
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            let len = min(Int(strlen(src)) + 1, dest.count)
            dest.copyBytes(from: UnsafeRawBufferPointer(start: UnsafeRawPointer(src), count: len))
        }
    }
    return withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
        }
    }
}

// MARK: - DaemonClient

@MainActor
class DaemonClient: ObservableObject {
    @Published var networks: [Network] = []
    @Published var nodeId: String?
    @Published var daemonAlive = false

    private var pollTimer: Timer?
    private var pollingStarted = false
    private let storageKey = "savedNetworks"

    init() {
        loadNetworks()
    }

    // MARK: Lifecycle

    func ensureDaemonRunning() {
        guard !socketAlive() else { return }
        startDaemonViaAppleScript()
    }

    func startPolling() {
        guard !pollingStarted else { return }
        pollingStarted = true
        Task { await poll() }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.poll() }
        }
    }

    // MARK: Network List Management

    func addNetwork(_ saved: SavedNetwork) {
        guard !networks.contains(where: { $0.id == saved.networkId }) else { return }
        networks.append(Network(config: saved))
        persist()
        Task { await poll() }
    }

    func removeNetwork(_ networkId: String) {
        networks.removeAll { $0.id == networkId }
        persist()
    }

    // MARK: Commands

    func poll() async {
        // Get node status (no networkId needed for daemon/node info)
        if let resp = await sendRequest(["cmd": "status"]),
           resp["daemon"] as? String == "running" {
            daemonAlive = true
            nodeId = resp["nodeId"] as? String
        } else {
            daemonAlive = false
            nodeId = nil
        }

        // Poll each configured network
        for i in networks.indices {
            let nwid = networks[i].config.networkId
            if let resp = await sendRequest(["cmd": "status", "networkId": nwid]),
               let net = resp["network"] as? [String: Any] {
                networks[i].state = NetworkState(
                    authorized: net["authorized"] as? Bool ?? false,
                    mode: net["mode"] as? String ?? "",
                    assignedIP: net["assignedIP"] as? String
                )
            } else {
                // Daemon alive but no network state: not joined
                networks[i].state = nil
            }
        }
    }

    func join(networkId: String) async {
        setBusy(networkId, true)
        _ = await sendRequest(["cmd": "join", "networkId": networkId])
        setBusy(networkId, false)
        await poll()
    }

    func connect(networkId: String, mode: String = "vpn") async {
        // Exit mode conflict: disconnect any other network currently in exit mode
        if mode == "exit" {
            for net in networks where net.state?.mode == "exit" && net.id != networkId {
                _ = await sendRequest(["cmd": "disconnect", "networkId": net.id])
            }
        }
        setBusy(networkId, true)
        _ = await sendRequest(["cmd": "connect", "networkId": networkId, "mode": mode])
        setBusy(networkId, false)
        await poll()
    }

    func disconnect(networkId: String) async {
        setBusy(networkId, true)
        _ = await sendRequest(["cmd": "disconnect", "networkId": networkId])
        setBusy(networkId, false)
        await poll()
    }

    // MARK: Private

    private func setBusy(_ networkId: String, _ busy: Bool) {
        if let i = networks.firstIndex(where: { $0.id == networkId }) {
            networks[i].isBusy = busy
        }
    }

    private func loadNetworks() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([SavedNetwork].self, from: data) else { return }
        networks = saved.map { Network(config: $0) }
    }

    private func persist() {
        let saved = networks.map { $0.config }
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func startDaemonViaAppleScript() {
        let candidates = ["/opt/homebrew/bin/sixnetd", "/usr/local/bin/sixnetd"]
        let path = candidates.first { FileManager.default.fileExists(atPath: $0) } ?? candidates[0]
        let src = "do shell script \"\(path) > /dev/null 2>&1 &\" with administrator privileges"
        DispatchQueue.global().async {
            let script = NSAppleScript(source: src)
            var err: NSDictionary?
            script?.executeAndReturnError(&err)
        }
    }

    private func sendRequest(_ req: [String: Any]) async -> [String: Any]? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: socketSend(req))
            }
        }
    }
}
