import AppKit

/// Un groupe = une application et tout ce que macOS lui impute : ses auxiliaires,
/// mais aussi ce qu'on a lancé depuis elle (un `node` dans le terminal de Cursor,
/// une session `claude` dans Ghostty). C'est le découpage de « Forcer à quitter ».
struct ProcessGroup: Identifiable, Equatable {
    let id: String
    let name: String
    /// Le processus responsable : l'app elle-même quand il y en a une.
    let ownerPID: Int32
    let pids: [Int32]
    let cpu: Double
    let memoryBytes: Double
    let bundlePath: String?
    /// Suspendus par le noyau faute d'espace de pagination.
    var pausedPIDs: [Int32] = []
    /// Renseigné pour une app du Dock : de quoi la rouvrir après l'avoir quittée.
    var relaunchURL: URL?

    var isPaused: Bool { !pausedPIDs.isEmpty }

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
        if Demo.isActive { loadDemo(); return }
        guard !isRefreshing else { return }
        isRefreshing = true

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let uid = getuid()

        Task.detached(priority: .utility) {
            let parsed = Self.snapshot(uid: uid, ownPID: ownPID)
            await MainActor.run {
                let located = parsed.map { group in
                    var group = group
                    if let app = NSRunningApplication(processIdentifier: group.ownerPID), app.activationPolicy == .regular {
                        group.relaunchURL = app.bundleURL
                    }
                    return group
                }
                self.groups = Self.sorted(located, byCPU: self.sortByCPU)
                self.totalUserMemory = parsed.reduce(0) { $0 + $1.memoryBytes }
                self.updateReclaimCandidates()
                self.isRefreshing = false
            }
        }
    }

    private static func sorted(_ items: [ProcessGroup], byCPU: Bool) -> [ProcessGroup] {
        items.sorted { byCPU ? $0.cpu > $1.cpu : $0.memoryBytes > $1.memoryBytes }
    }

    /// `ps` pour la liste et la moyenne CPU glissante (celle d'Activity Monitor),
    /// libproc pour l'empreinte : le RSS de `ps` ignore le swap et la compression,
    /// si bien qu'une app de 16 Go dont l'essentiel est swappé y pèse 1 Go.
    private nonisolated static func snapshot(uid: uid_t, ownPID: Int32) -> [ProcessGroup] {
        guard let output = run("/bin/ps", ["-axo", "pid=,uid=,pcpu="]) else { return [] }

        struct Tally { var pids: [Int32] = []; var cpu = 0.0; var memory = 0.0; var paused: [Int32] = [] }
        var byOwner: [Int32: Tally] = [:]

        for line in output.split(separator: "\n") {
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count == 3, let pid = Int32(columns[0]), let owner = UInt32(columns[1]),
                  let cpu = Double(columns[2]) else { continue }
            guard owner == uid, pid != ownPID else { continue }
            let responsible = ProcessControl.responsiblePID(pid)
            guard responsible != ownPID else { continue }

            var tally = byOwner[responsible] ?? Tally()
            tally.pids.append(pid)
            tally.cpu += cpu
            tally.memory += ProcessControl.footprint(pid) ?? 0
            if ProcessControl.isStarvationPaused(pid) { tally.paused.append(pid) }
            byOwner[responsible] = tally
        }

        // Deux instances d'un même exécutable (des `node` sans app) forment une ligne.
        var groups: [String: ProcessGroup] = [:]
        for (owner, tally) in byOwner {
            guard let path = ProcessControl.executablePath(owner), !isSystemPath(path) else { continue }
            let (key, display, bundle) = identify(path: path)
            guard !protectedNames.contains(display) else { continue }

            let previous = groups[key]
            let isLarger = tally.memory > (previous?.memoryBytes ?? 0)
            groups[key] = ProcessGroup(
                id: key, name: display,
                ownerPID: previous.map { isLarger ? owner : $0.ownerPID } ?? owner,
                pids: (previous?.pids ?? []) + tally.pids,
                cpu: (previous?.cpu ?? 0) + tally.cpu,
                memoryBytes: (previous?.memoryBytes ?? 0) + tally.memory,
                bundlePath: bundle,
                pausedPIDs: (previous?.pausedPIDs ?? []) + tally.paused
            )
        }
        return Array(groups.values)
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
    /// Seule l'app est sollicitée ; ses auxiliaires et ses terminaux suivent.
    @discardableResult
    func terminate(_ group: ProcessGroup) -> Bool {
        var closed = false
        if let app = NSRunningApplication(processIdentifier: group.ownerPID), app.activationPolicy == .regular {
            closed = app.terminate()
        } else {
            for pid in group.pids { closed = kill(pid, SIGTERM) == 0 || closed }
        }
        lastAction = group.isPaused
            ? "\(group.name) est en pause : reprendre ou forcer"
            : closed ? "\(group.name) — fermeture demandée" : "\(group.name) — refus"
        refreshSoon()
        return closed
    }

    /// SIGKILL sur tout le groupe, comme « Forcer à quitter » : fonctionne aussi
    /// sur une app en pause, qui ne traite plus aucun événement.
    func forceQuit(_ group: ProcessGroup) {
        for pid in group.pids { kill(pid, SIGKILL) }
        lastAction = "\(group.name) — arrêt forcé · \(Self.formatBytes(group.memoryBytes))"
        refreshSoon()
    }

    /// Quitte puis rouvre l'app : elle restaure ses fenêtres avec une mémoire neuve.
    /// Si elle ne s'est pas fermée au bout de 8 s (dialogue, pause), on force.
    func relaunch(_ group: ProcessGroup) {
        guard let url = group.relaunchURL else { return }
        let owner = group.ownerPID, pids = group.pids, name = group.name
        lastAction = "\(name) — redémarrage…"
        if !group.isPaused { NSRunningApplication(processIdentifier: owner)?.terminate() }

        Task {
            if !group.isPaused { await Self.waitForExit(owner, seconds: 8) }
            if kill(owner, 0) == 0 {
                for pid in pids { kill(pid, SIGKILL) }
                await Self.waitForExit(owner, seconds: 3)
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                lastAction = "\(name) relancée"
            } catch {
                lastAction = "\(name) — réouverture impossible"
            }
            refreshSoon()
        }
    }

    private static func waitForExit(_ pid: Int32, seconds: Double) async {
        let deadline = Date().addingTimeInterval(seconds)
        while kill(pid, 0) == 0, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    /// Lève la pause imposée par le noyau, sur l'app et chacun de ses auxiliaires.
    func resume(_ group: ProcessGroup) {
        let pids = group.pausedPIDs, name = group.name
        guard !pids.isEmpty else { return }
        lastAction = "\(name) — reprise…"
        Task {
            let resumed = await ProcessControl.resumeWithAdministratorPrompt(pids)
            lastAction = resumed ? "\(name) reprise" : "\(name) — reprise annulée"
            refreshSoon()
        }
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

// MARK: - Démo

extension ProcessMonitor {
    func loadDemo() {
        let gb = 1_073_741_824.0
        let list = [
            ProcessGroup(id: "safari", name: "Safari", ownerPID: 611, pids: [611, 1204, 1377], cpu: 6.2, memoryBytes: 2.4 * gb, bundlePath: "/Applications/Safari.app"),
            ProcessGroup(id: "xcode", name: "Xcode", ownerPID: 902, pids: [902], cpu: 12.8, memoryBytes: 1.9 * gb, bundlePath: "/Applications/Xcode.app", pausedPIDs: [902]),
            ProcessGroup(id: "node", name: "node", ownerPID: 48211, pids: [48211, 48302], cpu: 9.4, memoryBytes: 0.8 * gb, bundlePath: nil),
            ProcessGroup(id: "music", name: "Musique", ownerPID: 733, pids: [733], cpu: 1.1, memoryBytes: 0.35 * gb, bundlePath: "/System/Applications/Music.app"),
            ProcessGroup(id: "mail", name: "Mail", ownerPID: 640, pids: [640], cpu: 0.4, memoryBytes: 0.3 * gb, bundlePath: "/System/Applications/Mail.app"),
            ProcessGroup(id: "postgres", name: "postgres", ownerPID: 812, pids: [812], cpu: 0.9, memoryBytes: 0.21 * gb, bundlePath: nil),
        ].map { group in
            var group = group
            group.relaunchURL = group.bundlePath.map { URL(fileURLWithPath: $0) }
            return group
        }
        groups = Self.sorted(list, byCPU: sortByCPU)
        totalUserMemory = list.reduce(0) { $0 + $1.memoryBytes }
        reclaimCandidates = Array(list.suffix(2))
        reclaimableBytes = reclaimCandidates.reduce(0) { $0 + $1.memoryBytes }
    }
}
