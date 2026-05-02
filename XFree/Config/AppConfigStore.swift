import SwiftUI
import Combine

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

final class AppConfigStore: ObservableObject {
    static let minColumnWidth: CGFloat = 280

    @Published var widthMode: WidthMode { didSet { scheduleSave() } }
    @Published var columnWidth: Int { didSet { scheduleSave() } }
    @Published var columns: [Column] { didSet { scheduleSave() } }

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
    }

    private var saveTask: DispatchWorkItem?

    init() {
        let stored = Self.load()
        self.widthMode = stored?.widthMode ?? .manual
        self.columnWidth = stored?.columnWidth ?? 450
        self.columns = stored?.columns ?? [Column(type: .custom, url: "https://x.com/home")]
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

    private func scheduleSave() {
        saveTask?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func saveNow() {
        let payload = Stored(widthMode: widthMode, columnWidth: columnWidth, columns: columns)
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
    }

    func moveColumn(from source: IndexSet, to destination: Int) {
        columns.move(fromOffsets: source, toOffset: destination)
    }
}
