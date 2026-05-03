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
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var store: AppConfigStore
    @AppStorage("appearance") private var appearance: AppearanceMode = .light
    @AppStorage("hideAds") private var hideAds: Bool = true

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
                HStack {
                    if let user = store.loggedInUsername {
                        Text("@\(user)").foregroundStyle(.secondary)
                    } else {
                        Text("Not signed in").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Log Out") { confirmLogOut(store: store) }
                        .disabled(store.loggedInUsername == nil)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
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
    @AppStorage("compactMode") private var compactMode: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Toggle("Compact mode", isOn: $compactMode)

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
            .frame(height: store.widthMode == .manual ? 170 : 150)

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
