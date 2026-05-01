import SwiftUI
import AppKit

@main
struct XFreeApp: App {
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore: Bool = false

    var body: some Scene {
        WindowGroup {
            Group {
                if let config = AppConfig.loadConfig() {
                    ContentView(appConfig: config)
                } else {
                    VStack(alignment: .center) {
                        Text("Error: Failed to load config file")
                    }
                }
            }
            .onAppear {
                guard !hasLaunchedBefore else { return }
                hasLaunchedBefore = true
                DispatchQueue.main.async {
                    NSApplication.shared.windows.first?.zoom(nil)
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutMenuButton()
            }
        }

        Window("About X Free", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commandsRemoved()
    }
}

private struct AboutMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About X Free") {
            openWindow(id: "about")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
