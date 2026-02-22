import SwiftUI

@main
struct SixnetClientApp: App {
    var body: some Scene {
        MenuBarExtra("Sixnet Client", systemImage: "network") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}
