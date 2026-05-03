import SwiftUI
import AppKit

@main
struct XFreeApp: App {
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore: Bool = false
    @AppStorage("appearance") private var appearance: AppearanceMode = .light
    @AppStorage("compactMode") private var compactMode: Bool = false
    @AppStorage("expandedWidth") private var expandedWidth: Double = 1440
    @AppStorage("expandedHeight") private var expandedHeight: Double = 900
    @StateObject private var configStore = AppConfigStore()

    static let compactSize = NSSize(width: 420, height: 760)
    static let compactWidthThreshold: CGFloat = 600
    static let compactMinHeight: CGFloat = 400
    static let expandedMinSize = NSSize(width: 460, height: 600)

    fileprivate static weak var deckWindow: NSWindow?

    var body: some Scene {
        Window("X Free", id: "main") {
            ContentView()
                .environmentObject(configStore)
                .preferredColorScheme(appearance.colorScheme)
                .frame(minWidth: 380, minHeight: 380)
                .background(DeckWindowAccessor())
                .onAppear {
                    DispatchQueue.main.async {
                        applyCompactMode(compactMode)
                        if !hasLaunchedBefore {
                            hasLaunchedBefore = true
                            if !compactMode { Self.deckWindow?.zoom(nil) }
                        }
                    }
                }
                .onChange(of: compactMode) { _, newValue in applyCompactMode(newValue) }
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
                    compactMode.toggle()
                }
                .keyboardShortcut("/", modifiers: .option)
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

private extension XFreeApp {
    func applyCompactMode(_ on: Bool) {
        guard let window = Self.deckWindow else { return }
        relaxConstraints(window)
        if on {
            let frame = window.frame
            if frame.width >= Self.compactWidthThreshold {
                expandedWidth = Double(frame.width)
                expandedHeight = Double(frame.height)
            }
            if frame.size != Self.compactSize {
                resize(window: window, to: Self.compactSize)
            }
            let w = Self.compactSize.width
            window.minSize = NSSize(width: w, height: Self.compactMinHeight)
            window.maxSize = NSSize(width: w, height: CGFloat.greatestFiniteMagnitude)
            disableFullScreenAffordances(window)
        } else {
            let restored = NSSize(width: expandedWidth, height: expandedHeight)
            if window.frame.size != restored {
                resize(window: window, to: restored)
            }
            window.minSize = Self.expandedMinSize
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            enableFullScreenAffordances(window)
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
        var frame = window.frame
        let topLeftY = frame.origin.y + frame.size.height
        frame.size = size
        frame.origin.y = topLeftY - size.height
        window.setFrame(frame, display: true, animate: true)
    }
}

private struct DeckWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            XFreeApp.deckWindow = window
            DeckWindowSupport.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private enum DeckWindowSupport {
    private static var hotkeyInstalled = false
    private static var resizeDelegate: CompactResizeDelegate?

    static func attach(to window: NSWindow) {
        installHotkeyIfNeeded()
        installResizeDelegate(for: window)
    }

    /// SwiftUI's `keyboardShortcut("/")` is character-based, so it dies on non-Latin layouts where
    /// the slash glyph sits on a different physical key. Watch the physical slash key
    /// (kVK_ANSI_Slash = 0x2C) instead and consume the event so the SwiftUI shortcut doesn't
    /// double-fire on Latin layouts.
    private static func installHotkeyIfNeeded() {
        guard !hotkeyInstalled else { return }
        hotkeyInstalled = true
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods == .option, event.keyCode == 0x2C else { return event }
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

    init(window: NSWindow, forward: NSWindowDelegate?) {
        self.window = window
        self.forward = forward
        super.init()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        var size = frameSize
        if let f = forward, f.responds(to: #selector(NSWindowDelegate.windowWillResize(_:to:))) {
            size = f.windowWillResize?(sender, to: size) ?? size
        }
        guard UserDefaults.standard.bool(forKey: "compactMode") else { return size }
        return NSSize(
            width: XFreeApp.compactSize.width,
            height: max(XFreeApp.compactMinHeight, size.height)
        )
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        if UserDefaults.standard.bool(forKey: "compactMode") { return false }
        if let f = forward, f.responds(to: #selector(NSWindowDelegate.windowShouldZoom(_:toFrame:))) {
            return f.windowShouldZoom?(window, toFrame: newFrame) ?? true
        }
        return true
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return forward?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        return forward
    }
}
