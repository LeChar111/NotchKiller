import Foundation

/// Un profil Claude Code, tel qu'on le présente dans le switch de l'historique.
struct ClaudeProfile: Identifiable, Hashable, Sendable {
    let directory: URL

    var id: String { directory.path }
    var isDefault: Bool { directory.standardizedFileURL == ClaudeProfiles.defaultDirectory.standardizedFileURL }

    var name: String {
        if isDefault { return "Perso" }
        let suffix = directory.lastPathComponent.replacingOccurrences(of: ".claude-", with: "")
        return suffix == "work" ? "Pro" : suffix.capitalized
    }

    static var all: [ClaudeProfile] { ClaudeProfiles.directories.map(ClaudeProfile.init) }
}

struct ClaudeHistoryEntry: Identifiable, Hashable, Sendable {
    let id: String
    let profile: ClaudeProfile
    let path: String
    let workingDirectory: String
    let title: String?
    let lastPrompt: String?
    let updatedAt: Date

    var projectName: String { (workingDirectory as NSString).lastPathComponent }
    var displayTitle: String { title ?? lastPrompt ?? "Conversation sans titre" }
    var directoryExists: Bool { FileManager.default.fileExists(atPath: workingDirectory) }
}

/// Sessions terminées proprement (`SessionEnd`). Une conversation récente qui
/// n'y figure pas et ne tourne plus a été interrompue : crash, terminal fermé.
/// La date de départ évite de marquer tout l'historique antérieur.
enum ClaudeEndedSessions {
    private struct Store: Codable {
        var since: Date
        var ended: [String: Date]
    }

    private static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchKiller", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("ended-sessions.json")
    }

    nonisolated(unsafe) private static var cache: Store?

    private static func load() -> Store {
        if let cache { return cache }
        let store = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Store.self, from: $0) }
            ?? Store(since: Date(), ended: [:])
        cache = store
        if !FileManager.default.fileExists(atPath: url.path) { save(store) }
        return store
    }

    private static func save(_ store: Store) {
        cache = store
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static var trackingSince: Date { load().since }

    static func contains(_ id: String) -> Bool { load().ended[id] != nil }

    static func record(_ id: String) {
        var store = load()
        store.ended[id] = Date()
        // Au-delà d'un mois, une session n'est plus proposée comme interrompue.
        let horizon = Date().addingTimeInterval(-30 * 86_400)
        store.ended = store.ended.filter { $0.value > horizon }
        save(store)
    }

    /// Une reprise relance la session : elle n'est plus « terminée ».
    static func forget(_ id: String) {
        var store = load()
        guard store.ended.removeValue(forKey: id) != nil else { return }
        save(store)
    }
}

@MainActor
@Observable
final class ClaudeHistoryModel {
    static let shared = ClaudeHistoryModel()

    enum Status { case live, interrupted, ended }

    private(set) var entries: [ClaudeProfile: [ClaudeHistoryEntry]] = [:]
    private(set) var isLoading = false
    private(set) var lastRefresh: Date?

    /// Clé : chemin du transcript. On ne relit que ce qui a changé.
    private var cache: [String: (modified: Date, entry: ClaudeHistoryEntry?)] = [:]
    private var refreshTask: Task<Void, Never>?

    /// Une session interrompue il y a plus longtemps n'est plus signalée.
    private static let interruptedWindow: TimeInterval = 7 * 86_400

    private init() {}

    func refresh() {
        guard refreshTask == nil else { return }
        isLoading = true
        let profiles = ClaudeProfile.all
        let snapshot = cache
        refreshTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Self.scan(profiles: profiles, cache: snapshot)
            }.value
            guard let self else { return }
            cache = result.cache
            entries = result.entries
            isLoading = false
            lastRefresh = Date()
            refreshTask = nil
        }
    }

    func status(of entry: ClaudeHistoryEntry) -> Status {
        if let session = ClaudeSessionStore.shared.sessions[entry.id], session.isAlive { return .live }
        if ClaudeEndedSessions.contains(entry.id) { return .ended }
        let recent = Date().timeIntervalSince(entry.updatedAt) < Self.interruptedWindow
        // Sans hook actif, une session très récente peut tourner à notre insu.
        let quiet = Date().timeIntervalSince(entry.updatedAt) > 120
        return recent && quiet && entry.updatedAt > ClaudeEndedSessions.trackingSince ? .interrupted : .ended
    }

    // MARK: Lecture des transcripts

    private struct ScanResult: Sendable {
        var entries: [ClaudeProfile: [ClaudeHistoryEntry]]
        var cache: [String: (modified: Date, entry: ClaudeHistoryEntry?)]
    }

    nonisolated private static func scan(
        profiles: [ClaudeProfile],
        cache: [String: (modified: Date, entry: ClaudeHistoryEntry?)]
    ) -> ScanResult {
        let fm = FileManager.default
        var result = ScanResult(entries: [:], cache: [:])

        for profile in profiles {
            let projects = profile.directory.appendingPathComponent("projects")
            let folders = (try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
            var list: [ClaudeHistoryEntry] = []

            for folder in folders {
                // Seuls les transcripts à la racine du projet : les sous-dossiers
                // portent ceux des sous-agents.
                let files = (try? fm.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
                )) ?? []
                for file in files where file.pathExtension == "jsonl" {
                    let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                    guard values?.isRegularFile == true, let modified = values?.contentModificationDate else { continue }

                    let entry: ClaudeHistoryEntry?
                    if let cached = cache[file.path], cached.modified == modified {
                        entry = cached.entry
                    } else {
                        entry = makeEntry(file: file, profile: profile, modified: modified)
                    }
                    result.cache[file.path] = (modified, entry)
                    if let entry { list.append(entry) }
                }
            }
            result.entries[profile] = list.sorted { $0.updatedAt > $1.updatedAt }
        }
        return result
    }

    nonisolated private static func makeEntry(file: URL, profile: ClaudeProfile, modified: Date) -> ClaudeHistoryEntry? {
        let info = TranscriptTitle.info(in: file.path)
        // Sans titre ni message, ce n'est pas une conversation (session vide,
        // lancement avorté) : rien à reprendre.
        guard info.title != nil || info.lastPrompt != nil, let cwd = info.workingDirectory else { return nil }
        return ClaudeHistoryEntry(
            id: file.deletingPathExtension().lastPathComponent,
            profile: profile,
            path: file.path,
            workingDirectory: cwd,
            title: info.title,
            lastPrompt: info.lastPrompt,
            updatedAt: modified
        )
    }
}
