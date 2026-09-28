import AppKit

/// Sets Live (.als) récemment ouverts, retrouvés par Spotlight — Live garde
/// sa propre liste dans un Preferences.cfg binaire illisible de l'extérieur.
@MainActor
@Observable
final class AbletonRecents {
    static let shared = AbletonRecents()

    struct Project: Identifiable, Equatable {
        var id: String { url.path }
        let url: URL
        let name: String
        let folder: String
        let lastUsed: Date
    }

    private(set) var projects: [Project] = []
    private(set) var isLoading = false

    private init() {}

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task.detached(priority: .utility) {
            let found = Self.search()
            await MainActor.run {
                AbletonRecents.shared.projects = found
                AbletonRecents.shared.isLoading = false
            }
        }
    }

    /// Les sauvegardes automatiques (dossiers « Backup »), les packs et les
    /// modèles polluent la liste : on les écarte.
    nonisolated private static let excluded = ["/Backup/", "/Factory Packs/", "/Packs/", "/Templates/",
                                   "/Library/Application Support/", ".Trash/"]

    nonisolated private static func search() -> [Project] {
        guard let mdfind = Shell.locate("mdfind"),
              let output = Shell.run(mdfind, ["kMDItemFSName == '*.als'"], timeout: 10) else { return [] }
        let paths = output.split(separator: "\n").map(String.init)
            .filter { path in !excluded.contains { path.contains($0) } }
            .prefix(400)
        let projects: [Project] = paths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            var date: Date?
            if let item = MDItemCreate(kCFAllocatorDefault, path as CFString) {
                date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
            }
            if date == nil {
                date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            }
            guard let date else { return nil }
            let parent = url.deletingLastPathComponent().lastPathComponent
            return Project(url: url, name: url.deletingPathExtension().lastPathComponent,
                           folder: parent.replacingOccurrences(of: " Project", with: ""),
                           lastUsed: date)
        }
        return Array(projects.sorted { $0.lastUsed > $1.lastUsed }.prefix(8))
    }
}
