import AppKit

struct MediaSource: Identifiable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let url: URL
}

struct MediaPlaylist: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    /// Renseigné pour les playlists épinglées : on les ouvre par leur lien.
    let link: String?
    /// Pochette récupérée depuis la page du lien.
    var artworkURL: String? = nil
    /// Renommée à la main : la récupération automatique n'y touche plus.
    var isCustomName = false
}

@MainActor
@Observable
final class MediaLibrary {
    static let shared = MediaLibrary()

    private(set) var sources: [MediaSource] = []
    private(set) var playlists: [MediaPlaylist] = []
    private(set) var pinned: [MediaPlaylist] = []
    private(set) var isLoading = false
    private(set) var note: String?

    private static let known: [(String, String)] = [
        ("com.apple.Music", "Musique"),
        ("com.spotify.client", "Spotify"),
        ("com.apple.podcasts", "Podcasts"),
        ("com.apple.TV", "Apple TV"),
    ]

    private static let pinnedKey = "media.pinned"

    private init() { loadPinned() }

    var defaultSource: MediaSource? {
        let stored = AppSettings.shared.defaultMediaBundleID
        return sources.first { $0.bundleID == stored } ?? sources.first
    }

    var isAppleMusic: Bool { defaultSource?.bundleID == "com.apple.Music" }

    func refresh() {
        sources = Self.known.compactMap { bundleID, name in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
            return MediaSource(bundleID: bundleID, name: name, url: url)
        }
        loadPinned()
        guard isAppleMusic else { playlists = []; return }
        loadMusicPlaylists()
    }

    func setDefault(_ source: MediaSource) {
        AppSettings.shared.defaultMediaBundleID = source.bundleID
        note = "\(source.name) — source par défaut"
        refresh()
    }

    func launchDefault() {
        guard let source = defaultSource else { return }
        NSWorkspace.shared.openApplication(at: source.url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Apple Music

    /// `user playlists` n'est lisible que si Musique tourne — on ne la lance pas
    /// dans le dos de l'utilisateur juste pour dresser une liste.
    var isMusicRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.Music" }
    }

    private func loadMusicPlaylists() {
        guard isMusicRunning else { playlists = []; return }
        guard !isLoading else { return }
        isLoading = true

        Task {
            let script = """
            if application "Music" is running then
              tell application "Music"
                set out to ""
                repeat with p in user playlists
                  try
                    set out to out & (name of p) & tab & (count of tracks of p) & linefeed
                  end try
                end repeat
                return out
              end tell
            else
              return ""
            end if
            """
            let raw = (try? await AppleScriptHelper.execute(script))?.stringValue ?? ""
            playlists = Self.parsePlaylists(raw)
            isLoading = false
        }
    }

    private nonisolated static func parsePlaylists(_ raw: String) -> [MediaPlaylist] {
        raw.split(separator: "\n").prefix(24).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard let name = parts.first.map(String.init), !name.isEmpty else { return nil }
            let count = parts.count > 1 ? String(parts[1]) : "—"
            return MediaPlaylist(id: "music:\(name)", name: name,
                                 subtitle: "\(count) titre\(count == "1" ? "" : "s")", link: nil)
        }
    }

    func play(_ playlist: MediaPlaylist) {
        if let link = playlist.link, let url = URL(string: link) {
            NSWorkspace.shared.open(url)
            note = "\(playlist.name) — ouvert"
            return
        }
        let escaped = playlist.name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        Task {
            try? await AppleScriptHelper.executeVoid(
                "tell application \"Music\" to play playlist \"\(escaped)\""
            )
            note = "\(playlist.name) — lecture"
        }
    }

    // MARK: Playlists épinglées (Spotify et autres services sans dictionnaire)

    func addPinnedFromPasteboard() {
        let board = NSPasteboard.general
        let candidate = board.string(forType: .URL)
            ?? board.string(forType: .string)
            ?? ""
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: trimmed), let scheme = url.scheme,
              scheme == "https" || scheme == "spotify" || scheme == "music" else {
            note = "Aucun lien de playlist dans le presse-papiers"
            return
        }

        addPinned(link: trimmed, name: board.string(forType: .init("public.url-name")))
    }

    func addPinned(link: String, name: String?) {
        guard !pinned.contains(where: { $0.link == link }) else {
            note = "Déjà épinglée"
            return
        }
        let title = name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? Self.derivedName(from: link)
        let playlist = MediaPlaylist(id: "pin:\(link)", name: title,
                                     subtitle: Self.serviceName(from: link), link: link)
        pinned.append(playlist)
        savePinned()
        note = "\(title) — épinglée"
        fetchMetadata(for: playlist)
    }

    func removePinned(_ playlist: MediaPlaylist) {
        pinned.removeAll { $0.id == playlist.id }
        savePinned()
    }

    func rename(_ playlist: MediaPlaylist, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = pinned.firstIndex(where: { $0.id == playlist.id }) else { return }
        let current = pinned[index]
        pinned[index] = MediaPlaylist(id: current.id, name: trimmed, subtitle: current.subtitle, link: current.link,
                                      artworkURL: current.artworkURL, isCustomName: true)
        savePinned()
    }

    /// Nom et pochette depuis la page du lien. `force` écrase aussi un nom
    /// choisi à la main — c'est le bouton « Récupérer ».
    func fetchMetadata(for playlist: MediaPlaylist, force: Bool = false) {
        guard let link = playlist.link else { return }
        fetchedLinks.insert(link)
        Task {
            let result = await PlaylistMetadata.fetch(link)
            guard let index = pinned.firstIndex(where: { $0.id == playlist.id }) else { return }
            let current = pinned[index]
            let keepName = current.isCustomName && !force
            let name = keepName ? current.name : (result.title ?? current.name)
            pinned[index] = MediaPlaylist(id: current.id, name: name, subtitle: current.subtitle, link: current.link,
                                          artworkURL: result.imageURL ?? current.artworkURL,
                                          isCustomName: keepName)
            savePinned()
            if force {
                note = result.title == nil ? "Nom introuvable pour ce lien" : "\(name) — mis à jour"
            }
        }
    }

    /// Liens déjà interrogés pendant cette exécution : on ne réinterroge pas en boucle.
    private var fetchedLinks: Set<String> = []

    /// Sans appel d'API on n'a pas le vrai titre : on tire le meilleur du lien.
    private nonisolated static func derivedName(from link: String) -> String {
        guard let url = URL(string: link) else { return "Playlist" }
        let parts = url.pathComponents.filter { $0 != "/" }
        if let slug = parts.first(where: { $0.contains("-") }) {
            return slug.replacingOccurrences(of: "-", with: " ").capitalized
        }
        if let last = parts.last, last.count > 8 {
            return "Playlist \(last.prefix(6))…"
        }
        return "Playlist"
    }

    private nonisolated static func serviceName(from link: String) -> String {
        if link.contains("spotify") { return "Spotify" }
        if link.contains("music.apple") { return "Apple Music" }
        if link.contains("deezer") { return "Deezer" }
        if link.contains("youtube") { return "YouTube" }
        return "Lien"
    }

    private func loadPinned() {
        guard let raw = UserDefaults.standard.array(forKey: Self.pinnedKey) as? [[String: String]] else { return }
        pinned = raw.compactMap { entry in
            guard let link = entry["link"], let name = entry["name"] else { return nil }
            return MediaPlaylist(id: "pin:\(link)", name: name,
                                 subtitle: entry["service"] ?? Self.serviceName(from: link), link: link,
                                 artworkURL: entry["artwork"], isCustomName: entry["custom"] == "1")
        }
        // Épinglées avant la récupération automatique : on complète une fois.
        for playlist in pinned where playlist.artworkURL == nil && !fetchedLinks.contains(playlist.link ?? "") {
            fetchMetadata(for: playlist)
        }
    }

    private func savePinned() {
        let raw = pinned.compactMap { playlist -> [String: String]? in
            guard let link = playlist.link else { return nil }
            var entry = ["link": link, "name": playlist.name, "service": playlist.subtitle,
                         "custom": playlist.isCustomName ? "1" : "0"]
            if let artwork = playlist.artworkURL { entry["artwork"] = artwork }
            return entry
        }
        UserDefaults.standard.set(raw, forKey: Self.pinnedKey)
    }
}
