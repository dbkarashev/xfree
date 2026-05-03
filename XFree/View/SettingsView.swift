import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            ColumnsSettingsView()
                .tabItem { Label("Columns", systemImage: "rectangle.split.3x1") }
        }
        .frame(width: 540, height: 420)
        .background(PanelWindowAccessor(staticTitle: "Settings", centerOnOpen: true))
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var store: AppConfigStore
    @AppStorage(AppPreference.appearance.rawValue) private var appearance: AppearanceMode = .light
    @AppStorage(AppPreference.hideAds.rawValue) private var hideAds: Bool = true

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Hide ads on x.com", isOn: $hideAds)

            LabeledContent("Account") {
                HStack(spacing: 8) {
                    if let user = store.loggedInUsername {
                        Text("@\(user)").foregroundStyle(.secondary)
                    } else {
                        Text("Not signed in").foregroundStyle(.secondary)
                    }
                    Button("Log Out") { confirmLogOut(store: store) }
                        .disabled(store.loggedInUsername == nil)
                }
            }

            LabeledContent("Reset") {
                Button("Restore Defaults") { confirmRestoreDefaults(store: store) }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
    }
}

/// Returns nil if the candidate is acceptable, or a short message explaining why it isn't.
/// Rules: at least one modifier; not a system-reserved combo; not one of our hardcoded ones.
func validateCompactShortcut(_ candidate: ShortcutBinding) -> String? {
    let mods = candidate.modifierFlags
    if mods.isEmpty {
        return "Use at least one modifier key"
    }

    let cmdOnly = mods == .command
    let lower = candidate.displayCharacter.lowercased()

    if cmdOnly, ["q", "w", ","].contains(lower) {
        return "Reserved by macOS"
    }
    if cmdOnly {
        if lower == "r" { return "Already used for Refresh" }
        if ["+", "-", "="].contains(candidate.displayCharacter) { return "Already used for Zoom" }
        if let n = Int(candidate.displayCharacter), (1...9).contains(n) {
            return "Already used to jump to column \(n)"
        }
    }
    return nil
}

/// Apple-style inline shortcut recorder: a bordered button that becomes "live" on click,
/// captures the next valid keypress, validates it, and commits on success. Esc cancels;
/// clicking the button while recording toggles back out.
///
/// Sets `DeckWindowSupport.isRecordingShortcut` so the live compact-mode hotkey monitor
/// pauses while a new chord is being captured — otherwise binding the current shortcut to a
/// new value would also toggle the deck on the way past.
struct ShortcutRecorderField: View {
    @Binding var binding: ShortcutBinding
    /// Returns nil on success, an error message to display otherwise.
    let onValidate: (ShortcutBinding) -> String?

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording ? "Press shortcut…" : binding.displayString)
                    .frame(minWidth: 110)
                    .monospaced()
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        errorMessage = nil
        DeckWindowSupport.isRecordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        DeckWindowSupport.isRecordingShortcut = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 0x35 {  // Esc
            stopRecording()
            return
        }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let candidate = ShortcutBinding(
            keyCode: event.keyCode,
            modifierFlagsRaw: mods.rawValue,
            displayCharacter: event.charactersIgnoringModifiers ?? ""
        )
        if let error = onValidate(candidate) {
            errorMessage = error
            return
        }
        binding = candidate
        errorMessage = nil
        stopRecording()
    }
}

/// SwiftUI's macOS Settings scene auto-overrides the window title with the active TabView
/// label, and both Settings and About panels remember their last-closed origin between runs
/// (we want them centered every time). Pin title and recenter via NSWindow access.
///
/// The view is mounted lazily and reused across closes (SwiftUI hides the window rather than
/// destroying the view), so initial-open work runs in `makeNSView` while subsequent recenters
/// hang off a `\.isVisible` KVO observer.
struct PanelWindowAccessor: NSViewRepresentable {
    let staticTitle: String?
    let centerOnOpen: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            if let title = staticTitle {
                window.title = title
                context.coordinator.observeTitle(window: window, expected: title)
            }
            if centerOnOpen {
                // Disable autosave once, here. The visibility observer just recenters; we don't
                // need to keep stomping on the autosave name on every show.
                window.setFrameAutosaveName("")
                window.center()
                context.coordinator.observeVisibility(window: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var titleObserver: NSKeyValueObservation?
        private var visibilityObserver: NSKeyValueObservation?

        /// Synchronous re-set so AppKit doesn't get to redraw the titlebar with the SwiftUI
        /// auto-title before we override — that's what was producing the flicker on tab switch.
        func observeTitle(window: NSWindow, expected: String) {
            titleObserver = window.observe(\.title, options: [.new]) { w, _ in
                if w.title != expected { w.title = expected }
            }
        }

        /// Settings/About windows are hidden, not destroyed, on close. Re-center every time the
        /// window flips back to visible so reopens always land in the middle.
        func observeVisibility(window: NSWindow) {
            visibilityObserver = window.observe(\.isVisible, options: [.new]) { w, change in
                guard change.newValue == true else { return }
                w.center()
            }
        }

        deinit {
            titleObserver?.invalidate()
            visibilityObserver?.invalidate()
        }
    }
}

/// Wipe app preferences — appearance, hide-ads, compact mode, page zoom, columns and column
/// shortcut. Doesn't touch session state (x.com cookies / login).
@MainActor
func confirmRestoreDefaults(store: AppConfigStore) {
    let alert = NSAlert()
    alert.messageText = "Restore default settings?"
    alert.informativeText = "Appearance, columns, compact shortcut and other preferences will be reset. Your x.com login and custom columns' web data are unaffected."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Restore")
    alert.addButton(withTitle: "Cancel")
    alert.buttons.first?.hasDestructiveAction = true
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    AppPreference.resetAll()
    store.resetToDefaults()
}

/// Modal NSAlert so the same confirm flow works from both Settings and the app menu —
/// SwiftUI `.alert()` is awkward to drive from a `CommandGroup` button action.
@MainActor
func confirmLogOut(store: AppConfigStore) {
    let alert = NSAlert()
    alert.messageText = "Log out of X Free?"
    alert.informativeText = "You'll need to log in again to use the deck. Custom non-x.com columns are unaffected."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Log Out")
    alert.addButton(withTitle: "Cancel")
    alert.buttons.first?.hasDestructiveAction = true
    if alert.runModal() == .alertFirstButtonReturn {
        Task { await store.signOut() }
    }
}

private struct ColumnsSettingsView: View {
    @EnvironmentObject private var store: AppConfigStore
    @AppStorage(AppPreference.compactMode.rawValue) private var compactMode: Bool = false

    var body: some View {
        let isLoggedIn = store.loggedInUsername != nil
        VStack(spacing: 0) {
            Form {
                Toggle("Compact mode", isOn: $compactMode)
                    .disabled(!isLoggedIn)
                    .help(isLoggedIn ? "" : "Sign in to use compact mode.")

                LabeledContent("Shortcut") {
                    HStack(spacing: 6) {
                        ShortcutRecorderField(
                            binding: $store.compactShortcut,
                            onValidate: validateCompactShortcut
                        )
                        if store.compactShortcut != .defaultCompact {
                            Button {
                                store.compactShortcut = .defaultCompact
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Restore default")
                        }
                    }
                }

                Picker("Layout", selection: $store.widthMode) {
                    ForEach(WidthMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(compactMode)

                if store.widthMode == .manual {
                    LabeledContent("Width") {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(store.columnWidth) },
                                    set: { store.columnWidth = Int($0) }
                                ),
                                in: 400...700,
                                step: 25
                            )
                            Text("\(store.columnWidth) px")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .trailing)
                        }
                    }
                    .disabled(compactMode)
                } else {
                    Text("Columns split the window equally. Below \(Int(AppConfigStore.minColumnWidth)) px per column the deck scrolls horizontally.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            List {
                ForEach($store.columns) { $column in
                    ColumnRow(column: $column)
                }
                .onMove { from, to in store.moveColumn(from: from, to: to) }
                .onDelete { indices in
                    indices.forEach { store.removeColumn(store.columns[$0].id) }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            Divider()

            HStack {
                Button {
                    store.addColumn()
                } label: {
                    Label("Add column", systemImage: "plus")
                }
                .buttonStyle(.borderless)

                Spacer()

                Text("Drag to reorder · swipe to delete")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

private struct ColumnRow: View {
    @Binding var column: AppConfigStore.Column

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)

            Picker("", selection: $column.type) {
                ForEach(AppConfigStore.Column.ColumnType.allCases) { t in
                    Text(t.label).tag(t)
                }
            }
            .labelsHidden()
            .frame(width: 140)

            if column.type == .custom {
                TextField(
                    "https://x.com/i/bookmarks",
                    text: Binding(
                        get: { column.url ?? "" },
                        set: { column.url = $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)
            } else {
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }
}
