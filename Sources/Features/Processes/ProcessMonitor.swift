import AppKit

/// Un groupe = une application et tous ses processus auxiliaires.
/// Un navigateur ou un éditeur Electron en lance une dizaine ; les lister
/// séparément ne dit rien à personne.
struct ProcessGroup: Identifiable, Equatable {
    let id: String
    let name: String
    let pids: [Int32]
    let cpu: Double
    let memoryBytes: Double
    let bundlePath: String?

    var memoryLabel: String {
        ProcessMonitor.formatBytes(memoryBytes)
    }

    var cpuLabel: String {
        String(format: "%.0f %%", cpu)
    }
}

@MainActor
@Observable
final class ProcessMonitor {
    static let shared = ProcessMonitor()

    private(set) var groups: [ProcessGroup] = []
    private(set) var totalUserMemory: Double = 0
    /// Recalculé au relevé, pas à chaque rendu : interroger NSWorkspace et la
    /// liste des fenêtres à chaque passe de layout coûte cher pour rien.
    private(set) var reclaimCandidates: [ProcessGroup] = []
    private(set) var reclaimableBytes: Double = 0
    private(set) var isRefreshing = false
    private(set) var lastAction: String?

    /// Tri : mémoire par défaut, c'est la ressource qu'on vient récupérer.
    var sortByCPU = false {
        didSet { groups = Self.sorted(groups, byCPU: sortByCPU) }
    }

    private var timer: Timer?
    private var subscribers = 0

    private init() {}

    // MARK: Cycle de vie — on ne sonde que quand la page est affichée

    func subscribe() {
        subscribers += 1
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        timer?.tolerance = 0.5
    }

    func unsubscribe() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    // MARK: Relevé

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let uid = getuid()

        Task.detached(priority: .utility) {
            let parsed = Self.snapshot(uid: uid, ownPID: ownPID)
            await MainActor.run {
                self.groups = Self.sorted(parsed, byCPU: self.sortByCPU)
                self.totalUserMemory = parsed.reduce(0) { $0 + $1.memoryBytes }
                self.updateReclaimCandidates()
                self.isRefreshing = false
            }
        }
    }

    private static func sorted(_ items: [ProcessGroup], byCPU: Bool) -> [ProcessGroup] {
        items.sorted { byCPU ? $0.cpu > $1.cpu : $0.memoryBytes > $1.memoryBytes }
    }

    /// `ps` plutôt que libproc : pas d'entitlement, pas de sondage privilégié,
    /// et la moyenne CPU glissante de `ps` est celle d'Activity Monitor.
    private nonisolated static func snapshot(uid: uid_t, ownPID: Int32) -> [ProcessGroup] {
        guard let output = run("/bin/ps", ["-axo", "pid=,uid=,pcpu=,rss=,comm="]) else { return [] }

        var accumulator: [String: (name: String, pids: [Int32], cpu: Double, memory: Double, bundle: String?)] = [:]

        for line in output.split(separator: "\n") {
            guard let entry = parse(line: String(line)) else { continue }
            guard entry.uid == uid, entry.pid != ownPID else { continue }
            guard !isSystemPath(entry.path) else { continue }

            let (key, display, bundle) = identify(path: entry.path)
            guard !protectedNames.contains(display) else { continue }

            var current = accumulator[key] ?? (display, [], 0, 0, bundle)
            current.pids.append(entry.pid)
            current.cpu += entry.cpu
            current.memory += entry.rssKB * 1024
            accumulator[key] = current
        }

        return accumulator.map { key, value in
            ProcessGroup(id: key, name: value.name, pids: value.pids,
                         cpu: value.cpu, memoryBytes: value.memory, bundlePath: value.bundle)
        }
    }

    private nonisolated static func parse(line: String) -> (pid: Int32, uid: uid_t, cpu: Double, rssKB: Double, path: String)? {
        var scanner = line.drop { $0 == " " }
        func token() -> String? {
            guard let end = scanner.firstIndex(of: " ") else { return nil }
            let value = String(scanner[scanner.startIndex..<end])
            scanner = scanner[end...].drop { $0 == " " }
            return value.isEmpty ? nil : value
        }
        guard let pid = token().flatMap(Int32.init),
              let uid = token().flatMap(UInt32.init),
              let cpu = token().flatMap(Double.init),
              let rss = token().flatMap(Double.init) else { return nil }
        let path = String(scanner)
        guard !path.isEmpty else { return nil }
        return (pid, uid_t(uid), cpu, rss, path)
    }

    /// Tout ce qui appartient au système reste hors de la liste : on ne propose
    /// pas de fermer ce qui fait tourner la machine.
    private nonisolated static func isSystemPath(_ path: String) -> Bool {
        let systemPrefixes = ["/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/",
                              "/Library/PrivilegedHelperTools/", "/private/var/"]
        return systemPrefixes.contains { path.hasPrefix($0) }
    }

    private nonisolated static let protectedNames: Set<String> = [
        "Finder", "Dock", "SystemUIServer", "ControlCenter", "NotificationCenter",
        "Spotlight", "loginwindow", "WindowServer", "NotchKiller", "Raycast",
    ]

    /// Remonte au premier `.app` du chemin : `Cursor.app/…/Cursor Helper` → `Cursor`.
    private nonisolated static func identify(path: String) -> (key: String, name: String, bundle: String?) {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        if let index = parts.firstIndex(where: { $0.hasSuffix(".app") }) {
            let name = String(parts[index].dropLast(4))
            let bundle = parts[...index].joined(separator: "/")
            return (bundle, name, bundle)
        }
        let name = String(parts.last ?? "")
        return (path, name, nil)
    }

    private nonisolated static func run(_ launchPath: String, _ arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    // MARK: Fermeture

    /// Fermeture douce : l'app reprend la main et peut proposer d'enregistrer.
    @discardableResult
    func terminate(_ group: ProcessGroup) -> Bool {
        var closed = false
        for pid in group.pids {
            if let app = NSRunningApplication(processIdentifier: pid) {
                closed = app.terminate() || closed
            } else {
                closed = kill(pid, SIGTERM) == 0 || closed
            }
        }
        lastAction = closed ? "\(group.name) — fermeture demandée" : "\(group.name) — refus"
        refreshSoon()
        return closed
    }

    // MARK: Libération de mémoire

    /// Candidats : applications ouvertes, ni au premier plan ni à l'écran.
    /// C'est la définition la plus défendable de « pas nécessaire maintenant ».
    private func updateReclaimCandidates() {
        let onScreen = Self.pidsWithVisibleWindows()
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier

        reclaimCandidates = groups.filter { group in
            guard group.bundlePath != nil else { return false }
            guard let app = group.pids.compactMap({ NSRunningApplication(processIdentifier: $0) })
                .first(where: { $0.activationPolicy == .regular }) else { return false }
            guard app.processIdentifier != frontmost else { return false }
            return app.isHidden || !group.pids.contains(where: { onScreen.contains($0) })
        }
        reclaimableBytes = reclaimCandidates.reduce(0) { $0 + $1.memoryBytes }
    }

    func reclaim(_ candidates: [ProcessGroup]) {
        let freed = candidates.reduce(0) { $0 + $1.memoryBytes }
        for group in candidates { terminate(group) }
        lastAction = "\(candidates.count) app\(candidates.count > 1 ? "s" : "") fermée\(candidates.count > 1 ? "s" : "") · \(Self.formatBytes(freed))"
    }

    /// Les PID qui possèdent au moins une fenêtre à l'écran. La liste des
    /// fenêtres sans leur titre ne demande aucune autorisation.
    private nonisolated static func pidsWithVisibleWindows() -> Set<Int32> {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        return Set(windows.compactMap { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else { return nil }
            return pid
        })
    }

    private func refreshSoon() {
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            refresh()
        }
    }

    nonisolated static func formatBytes(_ value: Double) -> String {
        if value >= 1_073_741_824 { return String(format: "%.1f Go", value / 1_073_741_824) }
        return String(format: "%.0f Mo", value / 1_048_576)
    }
}
