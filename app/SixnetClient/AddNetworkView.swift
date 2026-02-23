import SwiftUI

// Expected response from GET {url}/client.json:
// {
//   "networkId": "31655f6ec3a15f6d",
//   "name": "Q1 Office VPN",
//   "enrollUrl": "https://enroll.example.com"
// }

struct AddNetworkView: View {
    @EnvironmentObject var client: DaemonClient
    @Environment(\.dismiss) var dismiss

    @State private var urlInput = ""
    @State private var isFetching = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Network")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Enrollment URL")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("https://enroll.example.com", text: $urlInput)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await add() } }
                Text("Provided by your network administrator.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Spacer()
                if isFetching {
                    ProgressView().controlSize(.small)
                }
                Button("Add") { Task { await add() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                    .disabled(urlInput.trimmingCharacters(in: .whitespaces).isEmpty || isFetching)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func add() async {
        let raw = urlInput.trimmingCharacters(in: .whitespaces)
        let baseString = raw.hasSuffix("/") ? String(raw.dropLast()) : raw

        guard let base = URL(string: baseString) else {
            errorMessage = "Invalid URL"
            return
        }

        if client.networks.contains(where: { $0.config.configURL == base.absoluteString }) {
            errorMessage = "This network is already in your list"
            return
        }

        isFetching = true
        errorMessage = nil

        let configURL = base.appendingPathComponent("client.json")
        do {
            let (data, response) = try await URLSession.shared.data(from: configURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw AddNetworkError.badResponse
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let networkId = json["networkId"] as? String, !networkId.isEmpty,
                  let name = json["name"] as? String, !name.isEmpty,
                  let enrollURL = json["enrollUrl"] as? String, !enrollURL.isEmpty else {
                throw AddNetworkError.invalidConfig
            }

            let saved = SavedNetwork(
                configURL: base.absoluteString,
                networkId: networkId,
                name: name,
                enrollURL: enrollURL
            )
            client.addNetwork(saved)
            dismiss()
        } catch let e as AddNetworkError {
            errorMessage = e.description
        } catch {
            errorMessage = error.localizedDescription
        }

        isFetching = false
    }
}

private enum AddNetworkError: Error {
    case badResponse
    case invalidConfig

    var description: String {
        switch self {
        case .badResponse: return "Server returned an error. Check the URL."
        case .invalidConfig: return "Response is missing required fields (networkId, name, enrollUrl)."
        }
    }
}
