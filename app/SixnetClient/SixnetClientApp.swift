import SwiftUI

@main
struct SixnetClientApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra("Sixnet", systemImage: "network") {
            MenuBarView()
                .environmentObject(delegate.client)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let client = DaemonClient()

    func applicationDidFinishLaunching(_ notification: Notification) {
        client.ensureDaemonRunning()
        client.startPolling()
    }
}
