import SwiftUI
import AppKit

@main
struct XFreeApp: App {
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore: Bool = false
    @AppStorage("appearance") private var appearance: AppearanceMode = .system
    @AppStorage("expandedWidth") private var expandedWidth: Double = 1440
    @AppStorage("expandedHeight") private var expandedHeight: Double = 900
    @StateObject private var configStore = AppConfigStore()

    private static let compactSize = NSSize(width: 420, height: 760)
    private static let compactWidthThreshold: CGFloat = 600

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(configStore)
                .preferredColorScheme(appearance.colorScheme)
                .frame(minWidth: 390, minHeight: 600)
                .onAppear {
                    guard !hasLaunchedBefore else { return }
                    hasLaunchedBefore = true
                    DispatchQueue.main.async {
                        NSApplication.shared.windows.first?.zoom(nil)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1440, height: 900)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutMenuButton()
            }
            CommandGroup(after: .windowSize) {
                Button("Toggle Compact Mode") {
                    toggleCompactMode()
                }
                .keyboardShortcut("\\", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(configStore)
                .preferredColorScheme(appearance.colorScheme)
        }

        Window("About X Free", id: "about") {
            AboutView()
                .preferredColorScheme(appearance.colorScheme)
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

private extension XFreeApp {
    func toggleCompactMode() {
        guard let window = mainContentWindow() else { return }
        let frame = window.frame
        let isCompact = frame.width < Self.compactWidthThreshold
        if isCompact {
            let restored = NSSize(width: expandedWidth, height: expandedHeight)
            resize(window: window, to: restored)
        } else {
            expandedWidth = Double(frame.width)
            expandedHeight = Double(frame.height)
            resize(window: window, to: Self.compactSize)
        }
    }

    func resize(window: NSWindow, to size: NSSize) {
        var frame = window.frame
        let topLeftY = frame.origin.y + frame.size.height
        frame.size = size
        frame.origin.y = topLeftY - size.height
        window.setFrame(frame, display: true, animate: true)
    }

    /// Pick the primary deck window — skip About/Settings panels.
    func mainContentWindow() -> NSWindow? {
        if let key = NSApp.keyWindow, isDeckWindow(key) { return key }
        if let main = NSApp.mainWindow, isDeckWindow(main) { return main }
        return NSApp.windows.first(where: isDeckWindow)
    }

    func isDeckWindow(_ window: NSWindow) -> Bool {
        // Settings/About are panel-style or have explicit titles; the deck window has no titlebar.
        guard window.contentView != nil, window.isVisible else { return false }
        if window.identifier?.rawValue == "about" { return false }
        return window.styleMask.contains(.fullSizeContentView) || window.styleMask.contains(.resizable)
    }
}
