import SwiftUI

@main
struct ReciteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar only — no windows
        Settings {
            EmptyView()
        }
    }
}
