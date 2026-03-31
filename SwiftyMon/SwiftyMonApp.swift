import SwiftUI

@main
struct SwiftyMonApp: App {
    @StateObject private var monitor = ProcessMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 960, height: 680)
        .commands {
            CommandGroup(after: .appInfo) {
                Divider()
                Button("Refresh Now") { monitor.refreshNow() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
