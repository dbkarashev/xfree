import SwiftUI
import AppKit

@main
struct XFreeApp: App {
    @AppStorage(AppPreference.appearance.rawValue) private var appearance: AppearanceMode = .light
    @AppStorage(AppPreference.compactMode.rawValue) private var compactMode: Bool = false
    @StateObject private var configStore = AppConfigStore()

    static let compactSize = NSSize(width: 420, height: 760)
    static let compactMinHeight: CGFloat = 400
    static let expandedMinSize = NSSize(width: 460, height: 600)

    fileprivate static weak var deckWindow: NSWindow?

    var body: some Scene {
        Window("X Free", id: "main") {
            ContentView()
                .environmentObject(configStore)
                .preferredColorScheme(appearance.colorScheme)
                .frame(minWidth: 380, minHeight: 380)
                .background(DeckWindowAccessor(configStore: configStore))
                .onAppear {
                    DispatchQueue.main.async {
                        applyEffectiveCompactMode()
                    }
                }
                .onChange(of: compactMode) { _, _ in applyEffectiveCompactMode() }
                .onChange(of: configStore.loggedInUsername) { _, _ in applyEffectiveCompactMode() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1440, height: 900)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutMenuButton()
            }
            CommandGroup(before: .appTermination) {
                LogOutMenuButton(store: configStore)
                Divider()
            }
            CommandGroup(after: .windowSize) {
                ToggleCompactCommand(store: configStore)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(configStore)
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

private struct LogOutMenuButton: View {
    @ObservedObject var store: AppConfigStore

    var body: some View {
        Button("Log Out") { confirmLogOut(store: store) }
            .disabled(store.loggedInUsername == nil)
    }
}

private struct ToggleCompactCommand: View {
    @ObservedObject var store: AppConfigStore
    @AppStorage(AppPreference.compactMode.rawValue) private var compactMode: Bool = false

    var body: some View {
        Button("Toggle Compact Mode") { compactMode.toggle() }
            .keyboardShortcut(
                store.compactShortcut.keyEquivalent,
                modifiers: store.compactShortcut.eventModifiers
            )
    }
}

private extension XFreeApp {
    /// Compact is gated on login: x.com's login page renders poorly at 420 px wide, so we
    /// always show LoginView in expanded layout even if the user's stored preference is on.
    /// Stored compactMode is preserved either way; effective mode follows login state.
    func applyEffectiveCompactMode() {
        let effective = compactMode && configStore.loggedInUsername != nil
        applyCompactMode(effective)
    }

    func applyCompactMode(_ on: Bool) {
        guard let window = Self.deckWindow else { return }
        relaxConstraints(window)
        if on {
            if window.frame.size != Self.compactSize {
                resize(window: window, to: Self.compactSize)
            }
            let w = Self.compactSize.width
            window.minSize = NSSize(width: w, height: Self.compactMinHeight)
            window.maxSize = NSSize(width: w, height: CGFloat.greatestFiniteMagnitude)
            disableFullScreenAffordances(window)
        } else {
            window.minSize = Self.expandedMinSize
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            enableFullScreenAffordances(window)
            if !window.isZoomed {
                DeckWindowSupport.inProgrammaticResize = true
                window.zoom(nil)
                DeckWindowSupport.inProgrammaticResize = false
            }
        }
    }

    func relaxConstraints(_ window: NSWindow) {
        window.minSize = NSSize(width: 200, height: 200)
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }

    func disableFullScreenAffordances(_ window: NSWindow) {
        var behavior = window.collectionBehavior
        behavior.remove([.fullScreenPrimary, .fullScreenAuxiliary])
        behavior.insert(.fullScreenNone)
        window.collectionBehavior = behavior
        window.standardWindowButton(.zoomButton)?.isEnabled = false
    }

    func enableFullScreenAffordances(_ window: NSWindow) {
        var behavior = window.collectionBehavior
        behavior.remove(.fullScreenNone)
        behavior.insert(.fullScreenPrimary)
        window.collectionBehavior = behavior
        window.standardWindowButton(.zoomButton)?.isEnabled = true
    }

    func resize(window: NSWindow, to size: NSSize) {
        DeckWindowSupport.inProgrammaticResize = true
        defer { DeckWindowSupport.inProgrammaticResize = false }
        var frame = window.frame
        let topLeftY = frame.origin.y + frame.size.height
        frame.size = size
        frame.origin.y = topLeftY - size.height
        window.setFrame(frame, display: true, animate: true)
    }
}

private struct DeckWindowAccessor: NSViewRepresentable {
    let configStore: AppConfigStore

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let store = configStore
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            XFreeApp.deckWindow = window
            DeckWindowSupport.attach(to: window, configStore: store)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

enum DeckWindowSupport {
    fileprivate static var inProgrammaticResize = false
    fileprivate static var mouseIsDown = false

    /// Set by `ShortcutRecorderField` while it's listening for a new chord. The compact-mode
    /// hotkey monitor checks this so recording the current shortcut doesn't toggle the deck as
    /// a side effect.
    static var isRecordingShortcut = false

    private static var hotkeyInstalled = false
    private static var mouseTrackerInstalled = false
    private static var resizeDelegate: CompactResizeDelegate?

    static func attach(to window: NSWindow, configStore: AppConfigStore) {
        installHotkeyIfNeeded(configStore: configStore)
        installMouseTrackerIfNeeded()
        installResizeDelegate(for: window)
    }

    /// We snap origin back on system-initiated moves (Sequoia desktop tile), but only when the
    /// user isn't actively dragging. Track mouse button state app-wide to tell those apart.
    private static func installMouseTrackerIfNeeded() {
        guard !mouseTrackerInstalled else { return }
        mouseTrackerInstalled = true
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { event in
            mouseIsDown = (event.type == .leftMouseDown)
            return event
        }
    }

    /// SwiftUI's `keyboardShortcut` is character-based, so non-Latin layouts miss non-letter
    /// keys (the user's `⌥/` would land on a different physical key). Watch physical key codes
    /// instead and consume the event so any matching SwiftUI shortcut doesn't double-fire.
    /// Binding is read live from the store so the in-Settings recorder rebinds the hotkey
    /// without restarting the app.
    private static func installHotkeyIfNeeded(configStore: AppConfigStore) {
        guard !hotkeyInstalled else { return }
        hotkeyInstalled = true
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak configStore] event in
            guard let configStore else { return event }
            guard !DeckWindowSupport.isRecordingShortcut else { return event }
            guard configStore.compactShortcut.matches(event: event) else { return event }
            let key = "compactMode"
            UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
            return nil
        }
    }

    /// `minSize`/`maxSize` are honored by manual edge drags but bypassed by Sequoia desktop
    /// tiling and Window-menu commands (Zoom / Fill / Move & Resize). The reliable hook is
    /// `windowWillResize(_:to:)` — called before any resize path applies, so we can clamp without
    /// flicker. SwiftUI sets its own delegate on this window for close/restore plumbing, so we
    /// install a transparent proxy that forwards every other selector to the original.
    private static func installResizeDelegate(for window: NSWindow) {
        if resizeDelegate?.window === window { return }
        let proxy = CompactResizeDelegate(window: window, forward: window.delegate)
        window.delegate = proxy
        resizeDelegate = proxy
    }
}

private final class CompactResizeDelegate: NSObject, NSWindowDelegate {
    weak var window: NSWindow?
    private weak var forward: NSWindowDelegate?
    private var lastUserOrigin: NSPoint

    init(window: NSWindow, forward: NSWindowDelegate?) {
        self.window = window
        self.forward = forward
        self.lastUserOrigin = window.frame.origin
        super.init()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        var size = frameSize
        if let f = forward, f.responds(to: #selector(NSWindowDelegate.windowWillResize(_:to:))) {
            size = f.windowWillResize?(sender, to: size) ?? size
        }
        if DeckWindowSupport.inProgrammaticResize { return size }
        guard UserDefaults.standard.bool(forKey: "compactMode") else { return size }
        let height: CGFloat = sender.inLiveResize
            ? max(XFreeApp.compactMinHeight, size.height)
            : sender.frame.height
        return NSSize(width: XFreeApp.compactSize.width, height: height)
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        if UserDefaults.standard.bool(forKey: "compactMode") { return false }
        if let f = forward, f.responds(to: #selector(NSWindowDelegate.windowShouldZoom(_:toFrame:))) {
            return f.windowShouldZoom?(window, toFrame: newFrame) ?? true
        }
        return true
    }

    /// AppKit has no `windowWillMove(_:to:)`, so we can't preempt the OS desktop-tile origin
    /// change. Instead detect after the fact: if the move happened while the mouse is up (i.e.
    /// not a user drag), it's the OS — snap back to the last user-authorized origin.
    func windowDidMove(_ notification: Notification) {
        if let f = forward, f.responds(to: #selector(NSWindowDelegate.windowDidMove(_:))) {
            f.windowDidMove?(notification)
        }
        guard let window = notification.object as? NSWindow else { return }
        if DeckWindowSupport.inProgrammaticResize {
            lastUserOrigin = window.frame.origin
            return
        }
        if DeckWindowSupport.mouseIsDown {
            lastUserOrigin = window.frame.origin
            return
        }
        guard UserDefaults.standard.bool(forKey: "compactMode") else {
            lastUserOrigin = window.frame.origin
            return
        }
        guard window.frame.origin != lastUserOrigin else { return }
        DeckWindowSupport.inProgrammaticResize = true
        window.setFrameOrigin(lastUserOrigin)
        DeckWindowSupport.inProgrammaticResize = false
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return forward?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        return forward
    }
}
