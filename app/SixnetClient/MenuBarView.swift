import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var client: DaemonClient
    @State private var showAddNetwork = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if !client.daemonAlive {
                Text("Daemon not running")
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else if client.networks.isEmpty {
                Text("No networks configured")
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                ForEach(client.networks) { network in
                    NetworkRow(network: network)
                    Divider()
                }
            }

            addNetworkButton

            Divider()

            quitButton
        }
        .frame(width: 300)
        .sheet(isPresented: $showAddNetwork) {
            AddNetworkView().environmentObject(client)
        }
    }

    var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(headerStatusColor)
                .frame(width: 8, height: 8)
            Text("Sixnet")
                .font(.headline)
            Spacer()
            if let nodeId = client.nodeId {
                Text(nodeId)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    var addNetworkButton: some View {
        Button { showAddNetwork = true } label: {
            Label("Add Network", systemImage: "plus.circle")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    var quitButton: some View {
        Button("Quit Sixnet") { NSApplication.shared.terminate(nil) }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }

    var headerStatusColor: Color {
        client.daemonAlive ? .orange : .gray
    }
}

// MARK: - Network Row

struct NetworkRow: View {
    @EnvironmentObject var client: DaemonClient
    let network: Network

    @State private var showEnroll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Name + status dot
            HStack {
                Text(network.config.name)
                    .fontWeight(.medium)
                Spacer()
                statusDot
            }

            // State-specific content
            if let state = network.state {
                if state.isConnected {
                    connectedRow(state: state)
                } else if state.authorized {
                    readyRow
                } else {
                    notAuthorizedRow
                }
            } else if client.daemonAlive {
                notJoinedRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contextMenu {
            Button("Remove Network", role: .destructive) {
                client.removeNetwork(network.id)
            }
        }
        .sheet(isPresented: $showEnroll) {
            EnrollView(network: network).environmentObject(client)
        }
    }

    // MARK: State rows

    func connectedRow(state: NetworkState) -> some View {
        HStack(spacing: 8) {
            Text(state.mode.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            if let ip = state.assignedIP {
                Text(ip)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            actionButton
        }
    }

    var readyRow: some View {
        HStack {
            Text("Ready to connect")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            actionButton
        }
    }

    var notAuthorizedRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let nodeId = client.nodeId {
                Text("Not authorized. Enroll at:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link(network.config.enrollURL,
                     destination: URL(string: network.config.enrollURL) ?? URL(string: "https://")!)
                    .font(.caption)
                    .lineLimit(1)
                Text("Your node ID: \(nodeId)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            if let err = network.lastError {
                Text(err.code)
                    .font(.caption.monospaced())
                    .foregroundStyle(.orange)
            }
        }
    }

    var notJoinedRow: some View {
        HStack {
            Text("Not joined")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if network.config.issuer != nil {
                Button {
                    showEnroll = true
                } label: {
                    busyLabel("Join")
                }
                .buttonStyle(.borderedProminent)
                .disabled(network.isBusy)
            } else {
                joinButton
            }
        }
    }

    // MARK: Buttons

    var actionButton: some View {
        let connected = network.state?.isConnected ?? false
        return Group {
            if connected {
                Button {
                    Task { await client.disconnect(networkId: network.id) }
                } label: {
                    busyLabel("Disconnect")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(network.isBusy)
            } else {
                Button {
                    Task { await client.connect(networkId: network.id) }
                } label: {
                    busyLabel("Connect")
                }
                .buttonStyle(.borderedProminent)
                .disabled(network.isBusy)
            }
        }
    }

    var joinButton: some View {
        Button {
            Task { await client.join(networkId: network.id) }
        } label: {
            busyLabel("Join")
        }
        .buttonStyle(.bordered)
        .disabled(network.isBusy)
    }

    @ViewBuilder
    func busyLabel(_ title: String) -> some View {
        if network.isBusy {
            ProgressView().controlSize(.small)
        } else {
            Text(title)
        }
    }

    // MARK: Status dot

    var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
    }

    var dotColor: Color {
        guard let state = network.state else { return .gray.opacity(0.4) }
        if state.isConnected { return .green }
        if state.authorized { return .orange }
        return .red.opacity(0.7)
    }
}
