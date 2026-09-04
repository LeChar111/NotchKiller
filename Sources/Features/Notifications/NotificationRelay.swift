import AppKit

struct RelayedNotification: Identifiable, Equatable {
    let id: Int
    let bundleID: String
    let appName: String
    let title: String
    let body: String
    let date: Date
}

/// Relaie les notifications système dans l'encoche.
///
/// macOS n'expose aucune API publique pour lire les notifications d'autres
/// applications. La seule voie qui ne passe pas par de l'« accessibilité »
/// détournée est la base de `usernoted`, que le système écrit lui-même — en
/// lecture seule, et à condition que l'app ait l'Accès complet au disque.
@MainActor
@Observable
final class NotificationRelay {
    static let shared = NotificationRelay()

    private(set) var latest: RelayedNotification?
    private(set) var recent: [RelayedNotification] = []
    private(set) var hasAccess = false
    private(set) var checked = false

    private var timer: Timer?
    private var lastSeenID = 0
    private static let maxKept = 12

    private nonisolated static var databasePath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")
            .path
    }

    private init() {}

    func start() {
        guard timer == nil, AppSettings.shared.relaySystemNotifications else { return }
        prime()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
        timer?.tolerance = 0.5
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func clearLatest() { latest = nil }

    /// Premier passage : on note l'identifiant courant sans rien annoncer,
    /// sinon le lancement de l'app déverserait tout l'historique.
    private func prime() {
        let rows = Self.query(after: 0, limit: 1)
        checked = true
        hasAccess = Self.canRead()
        lastSeenID = rows.first?.id ?? Self.maxRecordID()
    }

    private func poll() {
        let rows = Self.query(after: lastSeenID, limit: 5)
        guard let newest = rows.first else { return }
        lastSeenID = newest.id
        latest = newest
        recent.insert(contentsOf: rows, at: 0)
        while recent.count > Self.maxKept { recent.removeLast() }
    }

    // MARK: Lecture de la base

    private nonisolated static func canRead() -> Bool {
        FileManager.default.isReadableFile(atPath: databasePath)
            && !query(after: 0, limit: 1).isEmpty
    }

    private nonisolated static func maxRecordID() -> Int {
        guard let sqlite = Shell.locate("sqlite3"),
              let out = Shell.run(sqlite, ["-readonly", databasePath, "select max(rec_id) from record;"], timeout: 4)
        else { return 0 }
        return Int(out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// `data` est un plist binaire ; plutôt que de l'analyser en SQL, on
    /// extrait les chaînes lisibles côté Swift.
    private nonisolated static func query(after id: Int, limit: Int) -> [RelayedNotification] {
        guard let sqlite = Shell.locate("sqlite3") else { return [] }
        let sql = """
        select r.rec_id, a.identifier, r.delivered_date, quote(r.data)
        from record r join app a on a.app_id = r.app_id
        where r.rec_id > \(id) order by r.rec_id desc limit \(limit);
        """
        guard let output = Shell.run(sqlite, ["-readonly", "-separator", "\u{1F}", databasePath, sql], timeout: 5)
        else { return [] }

        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 4, let recordID = Int(parts[0]) else { return nil }

            let bundleID = parts[1]
            let seconds = Double(parts[2]) ?? 0
            let date = Date(timeIntervalSinceReferenceDate: seconds)
            let (title, body) = decode(hexBlob: parts[3])
            guard !title.isEmpty || !body.isEmpty else { return nil }

            return RelayedNotification(
                id: recordID,
                bundleID: bundleID,
                appName: appName(for: bundleID),
                title: title.isEmpty ? appName(for: bundleID) : title,
                body: body,
                date: date
            )
        }
    }

    /// `quote()` renvoie X'..hex..' ; on décode puis on lit le plist.
    private nonisolated static func decode(hexBlob: String) -> (String, String) {
        let hex = hexBlob.trimmingCharacters(in: CharacterSet(charactersIn: "X'"))
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex, let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) {
            guard let byte = UInt8(hex[index..<next], radix: 16) else { break }
            bytes.append(byte)
            index = next
        }

        guard let plist = try? PropertyListSerialization.propertyList(
            from: Data(bytes), options: [], format: nil
        ) as? [String: Any] else { return ("", "") }

        let request = plist["req"] as? [String: Any] ?? plist
        let title = request["titl"] as? String ?? ""
        let subtitle = request["subt"] as? String ?? ""
        let body = request["body"] as? String ?? ""
        let detail = [subtitle, body].filter { !$0.isEmpty }.joined(separator: " · ")
        return (title, detail)
    }

    private nonisolated static func appName(for bundleID: String) -> String {
        let clean = bundleID.replacingOccurrences(of: "_system_center_:", with: "")
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: clean) {
            return FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
        }
        return clean.split(separator: ".").last.map(String.init)?.capitalized ?? clean
    }
}
