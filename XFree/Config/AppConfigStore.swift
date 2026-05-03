import SwiftUI
import Combine
import WebKit

/// Every UserDefaults key we own, in one place. `@AppStorage` declarations across the app
/// reference these via `.rawValue`, and `resetAll()` wipes them in one call so the reset path
/// doesn't keep a parallel list in sync.
enum AppPreference: String, CaseIterable {
    case appearance
    case compactMode
    case hideAds
    case pageZoom

    static func resetAll() {
        let defaults = UserDefaults.standard
        for pref in allCases { defaults.removeObject(forKey: pref.rawValue) }
    }
}

enum WidthMode: String, Codable, CaseIterable, Identifiable {
    case auto
    case manual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .manual: return "Manual"
        }
    }
}

/// Layout-independent keyboard shortcut binding.
///
/// `keyCode` is the physical kVK_* code — same key on every keyboard layout. `modifierFlagsRaw`
/// is the masked NSEvent.ModifierFlags. `displayCharacter` is a snapshot of the glyph that was
/// printed on the user's current layout when they recorded the binding; it's used for UI only,
/// matching against incoming events uses keyCode + modifiers.
struct ShortcutBinding: Codable, Hashable {
    let keyCode: UInt16
    let modifierFlagsRaw: UInt
    let displayCharacter: String

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRaw)
    }

    func matches(event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.keyCode == keyCode && mods.rawValue == modifierFlagsRaw
    }

    /// `⌥/`, `⇧⌃⌘F12`, etc. Matches Apple's compact shortcut formatting.
    var displayString: String {
        var parts: [String] = []
        if modifierFlags.contains(.control) { parts.append("⌃") }
        if modifierFlags.contains(.option) { parts.append("⌥") }
        if modifierFlags.contains(.shift) { parts.append("⇧") }
        if modifierFlags.contains(.command) { parts.append("⌘") }
        parts.append(Self.specialKeyDisplay[keyCode] ?? displayCharacter.uppercased())
        return parts.joined()
    }

    /// kVK_ANSI_Slash + .option — what `⌥/` resolves to on a US keyboard.
    static let defaultCompact = ShortcutBinding(
        keyCode: 0x2C,
        modifierFlagsRaw: NSEvent.ModifierFlags.option.rawValue,
        displayCharacter: "/"
    )

    /// SwiftUI-flavored equivalents for the menu-item shortcut hint. Special keys map onto the
    /// `KeyEquivalent` constants; everything else falls back to the snapshotted character.
    var keyEquivalent: KeyEquivalent {
        switch keyCode {
        case 0x24, 0x4C: return .return
        case 0x30: return .tab
        case 0x31: return .space
        case 0x33: return .delete
        case 0x35: return .escape
        case 0x75: return .deleteForward
        case 0x7B: return .leftArrow
        case 0x7C: return .rightArrow
        case 0x7D: return .downArrow
        case 0x7E: return .upArrow
        default: return KeyEquivalent(displayCharacter.first ?? "/")
        }
    }

    var eventModifiers: EventModifiers {
        var m: EventModifiers = []
        if modifierFlags.contains(.command) { m.insert(.command) }
        if modifierFlags.contains(.option) { m.insert(.option) }
        if modifierFlags.contains(.control) { m.insert(.control) }
        if modifierFlags.contains(.shift) { m.insert(.shift) }
        return m
    }

    /// `event.charactersIgnoringModifiers` returns garbage for arrows/function/whitespace; map
    /// the kVK_* codes we care about to readable glyphs. Anything not in the map falls back to
    /// the snapshotted `displayCharacter`.
    private static let specialKeyDisplay: [UInt16: String] = [
        0x24: "↩", 0x4C: "↩",                        // return, numpad enter
        0x30: "⇥",                                    // tab
        0x31: "Space",                                // space
        0x33: "⌫", 0x75: "⌦",                        // delete, forward delete
        0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟",  // home, end, page up, page down
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",  // arrows
        0x7A: "F1",  0x78: "F2",  0x63: "F3",  0x76: "F4",
        0x60: "F5",  0x61: "F6",  0x62: "F7",  0x64: "F8",
        0x65: "F9",  0x6D: "F10", 0x67: "F11", 0x6F: "F12"
    ]
}

final class AppConfigStore: ObservableObject {
    static let minColumnWidth: CGFloat = 400

    @Published var widthMode: WidthMode { didSet { scheduleSave() } }
    @Published var columnWidth: Int { didSet { scheduleSave() } }
    @Published var columns: [Column] { didSet { scheduleSave() } }
    @Published var compactShortcut: ShortcutBinding { didSet { scheduleSave() } }

    /// Source of truth: re-detected on every launch by the `findUserName` script that runs in the
    /// LoginView WebView. Not persisted — cookies in WKWebsiteDataStore are persistent enough,
    /// and persisting a separate copy would just risk diverging from the real cookie state.
    @Published var loggedInUsername: String? = nil

    struct Column: Identifiable, Codable, Hashable {
        var id: UUID = UUID()
        var type: ColumnType
        var url: String?

        enum ColumnType: String, Codable, CaseIterable, Identifiable {
            case forYou
            case following
            case notifications
            case profile
            case custom

            var id: String { rawValue }

            var label: String {
                switch self {
                case .forYou: return "For you"
                case .following: return "Following"
                case .notifications: return "Notifications"
                case .profile: return "Profile"
                case .custom: return "Custom URL"
                }
            }
        }

        private enum CodingKeys: String, CodingKey { case type, url }

        init(type: ColumnType, url: String? = nil) {
            self.type = type
            self.url = url
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.type = try c.decode(ColumnType.self, forKey: .type)
            self.url = try c.decodeIfPresent(String.self, forKey: .url)
            self.id = UUID()
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(type, forKey: .type)
            try c.encodeIfPresent(url, forKey: .url)
        }

        var isXColumn: Bool {
            switch type {
            case .following, .forYou, .notifications, .profile: return true
            case .custom:
                if let u = url.flatMap({ URL(string: $0) }), ["x.com", "twitter.com"].contains(u.host()) {
                    return true
                }
                return false
            }
        }
    }

    static let configDirectoryUrl = FileManager.default.homeDirectoryForCurrentUser.appending(components: ".config", "XFree")
    private static let configFileUrl = configDirectoryUrl.appending(path: "settings.json")
    private static let configSchemaFileUrl = configDirectoryUrl.appending(path: "schema.json")

    private struct Stored: Codable {
        var widthMode: WidthMode?
        var columnWidth: Int?
        var columns: [Column]
        var compactShortcut: ShortcutBinding?
    }

    private var saveTask: DispatchWorkItem?

    init() {
        let stored = Self.load()
        self.widthMode = stored?.widthMode ?? .manual
        self.columnWidth = stored?.columnWidth ?? 450
        self.columns = stored?.columns ?? [Column(type: .custom, url: "https://x.com/home")]
        self.compactShortcut = stored?.compactShortcut ?? .defaultCompact
    }

    private static func ensureFiles() {
        try? FileManager.default.createDirectory(at: configDirectoryUrl, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: configFileUrl.path()),
           let path = Bundle.main.path(forResource: "settings", ofType: "json"),
           let data = try? Data(contentsOf: URL(filePath: path)) {
            FileManager.default.createFile(atPath: configFileUrl.path(), contents: data)
        }
        if let path = Bundle.main.path(forResource: "schema", ofType: "json"),
           let data = try? Data(contentsOf: URL(filePath: path)) {
            FileManager.default.createFile(atPath: configSchemaFileUrl.path(), contents: data)
        }
    }

    private static func load() -> Stored? {
        ensureFiles()
        guard let data = FileManager.default.contents(atPath: configFileUrl.path()),
              let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else { return nil }
        return stored
    }

    /// Load shipped defaults straight from the app bundle. Used by `resetToDefaults` so users
    /// get the same column set new installs get, not whatever fallback `init` carries.
    private static func loadBundledDefaults() -> Stored? {
        guard let path = Bundle.main.path(forResource: "settings", ofType: "json"),
              let data = try? Data(contentsOf: URL(filePath: path)),
              let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else { return nil }
        return stored
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func saveNow() {
        let payload = Stored(
            widthMode: widthMode,
            columnWidth: columnWidth,
            columns: columns,
            compactShortcut: compactShortcut
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        try? FileManager.default.createDirectory(at: Self.configDirectoryUrl, withIntermediateDirectories: true)
        try? data.write(to: Self.configFileUrl, options: .atomic)
    }

    func addColumn() {
        columns.append(Column(type: .custom, url: ""))
    }

    func removeColumn(_ id: UUID) {
        columns.removeAll { $0.id == id }
        WebViewCache.shared.evict(id.uuidString)
    }

    /// Reset everything we own to its default value. Pulls the column set from the bundled
    /// settings.json so the result matches what a fresh install would get. Doesn't touch
    /// session state (`loggedInUsername`, x.com cookies) — that's not a setting.
    @MainActor
    func resetToDefaults() {
        WebViewCache.shared.evictAll()
        let bundled = Self.loadBundledDefaults()
        widthMode = bundled?.widthMode ?? .manual
        columnWidth = bundled?.columnWidth ?? 450
        columns = bundled?.columns ?? [Column(type: .custom, url: "https://x.com/home")]
        compactShortcut = bundled?.compactShortcut ?? .defaultCompact
        // Skip the 0.3s debounce — reset is one-shot, we want it on disk before the user can
        // possibly quit the app. Cancel the pending scheduled save so we don't write twice.
        saveTask?.cancel()
        saveNow()
    }

    /// Drop x.com cookies, localStorage, IndexedDB, caches; evict cached x.com WebViews; clear
    /// the username flag so ContentView swaps back to LoginView.
    ///
    /// Order matters: tear down WK data BEFORE flipping the state flag, so the LoginView WebView
    /// SwiftUI creates next reads from an already-clean datastore (otherwise it'd happily read
    /// the still-live cookies and auto-relog the user).
    @MainActor
    func signOut() async {
        let dataStore = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types)
        let xRecords = records.filter { ["x.com", "twitter.com"].contains($0.displayName) }
        await dataStore.removeData(ofTypes: types, for: xRecords)
        WebViewCache.shared.evictXcom()
        loggedInUsername = nil
    }

    func moveColumn(from source: IndexSet, to destination: Int) {
        columns.move(fromOffsets: source, toOffset: destination)
    }
}
