import SwiftUI

struct MenuBarView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sixnet Client")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            Button("Connect") {
                // TODO
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Button("Disconnect") {
                // TODO
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 220)
    }
}
