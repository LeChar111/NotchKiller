import AppKit

/// Un processus vu par son empreinte mémoire réelle (colonne MEM de `top`), swap et
/// compression compris. Le RSS de `ps` ne compte que la RAM : un processus dont 40 Go
/// sont partis en swap y apparaît à 200 Mo, alors que c'est lui qui remplit le disque.
struct MemoryHog: Identifiable, Equatable {
    var id: Int32 { pid }
    let pid: Int32
    let name: String
    let command: String
    let footprint: Double
    let resident: Double
    let elapsed: String
    let ageSeconds: Double
    /// App au premier plan du Dock, ou processus auxiliaire logé dans un `.app`.
    let isApp: Bool

    /// Ce qui n'est pas en RAM : compressé ou swappé.
    var outOfRAM: Double { max(0, footprint - resident) }
    var isStale: Bool { ageSeconds >= 86_400 }
}

enum MemoryPressure: Int {
    case normal = 1, warning = 2, critical = 4

    var label: String {
        switch self {
        case .normal:   "normale"
        case .warning:  "tendue"
        case .critical: "critique"
        }
    }
}

@MainActor
@Observable
final class MemoryModel {
    static let shared = MemoryModel()

    private(set) var swapUsed: Double = 0
    private(set) var swapTotal: Double = 0
    private(set) var pressure: MemoryPressure = .normal
    private(set) var hogs: [MemoryHog] = []
    private(set) var isRefreshing = false
    private(set) var isPurging = false
    private(set) var lastAction: String?

    /// « Tout libérer » ne vise que ce qui tient le swap hors de toute app (et de ses
    /// auxiliaires) : tests oubliés, serveurs de dev, scripts. Une app se ferme ligne par ligne.
    var swapHolders: [MemoryHog] { hogs.filter { !$0.isApp && $0.outOfRAM >= 512 * 1_048_576 } }
    var swapHoldersBytes: Double { swapHolders.reduce(0) { $0 + $1.outOfRAM } }

    private var timer: Timer?
    private var subscribers = 0

    private init() {}

    func subscribe() {
        subscribers += 1
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
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
        let uid = getuid(), own = ProcessInfo.processInfo.processIdentifier

        Task.detached(priority: .utility) {
            let swap = Self.swapUsage()
            let level = Self.pressureLevel()
            let found = Self.snapshot(uid: uid, ownPID: own)
            await MainActor.run {
                self.swapUsed = swap.used
                self.swapTotal = swap.total
                self.pressure = level
                self.hogs = found.map { hog in
                    let app = hog.inBundle || NSRunningApplication(processIdentifier: hog.pid)?.activationPolicy == .regular
                    return MemoryHog(pid: hog.pid, name: hog.name, command: hog.command, footprint: hog.footprint,
                                     resident: hog.resident, elapsed: hog.elapsed, ageSeconds: hog.ageSeconds, isApp: app)
                }
                self.isRefreshing = false
            }
        }
    }

    private nonisolated static func swapUsage() -> (used: Double, total: Double) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (Double(usage.xsu_used), Double(usage.xsu_total))
    }

    private nonisolated static func pressureLevel() -> MemoryPressure {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        return MemoryPressure(rawValue: Int(level)) ?? .normal
    }

    /// `top` pour l'empreinte (swap compris), puis `ps` pour le propriétaire, le RSS,
    /// l'ancienneté et la ligne de commande complète des plus gros.
    private nonisolated static func snapshot(uid: uid_t, ownPID: Int32) -> [(pid: Int32, name: String, command: String, footprint: Double, resident: Double, elapsed: String, ageSeconds: Double, inBundle: Bool)] {
        guard let top = Shell.run("/usr/bin/top", ["-l", "1", "-o", "mem", "-n", "40", "-stats", "pid,mem"], timeout: 10) else { return [] }

        var footprints: [Int32: Double] = [:]
        var inTable = false
        for line in top.split(separator: "\n") {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            if cols.first == "PID" { inTable = true; continue }
            guard inTable, cols.count >= 2, let pid = Int32(cols[0]), let bytes = parseTopSize(String(cols[1])) else { continue }
            footprints[pid] = bytes
        }
        guard !footprints.isEmpty else { return [] }

        let pids = footprints.keys.map(String.init).joined(separator: ",")
        guard let ps = Shell.run("/bin/ps", ["-o", "pid=,uid=,rss=,etime=,args=", "-p", pids]) else { return [] }

        var result: [(pid: Int32, name: String, command: String, footprint: Double, resident: Double, elapsed: String, ageSeconds: Double, inBundle: Bool)] = []
        for line in ps.split(separator: "\n") {
            let cols = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard cols.count == 5, let pid = Int32(cols[0]), let owner = UInt32(cols[1]), let rss = Double(cols[2]) else { continue }
            guard owner == uid, pid != ownPID, let footprint = footprints[pid], footprint >= 128 * 1_048_576 else { continue }
            let args = String(cols[4])
            // Chemin réel : un auxiliaire réécrit son titre (args et comm), pas son exécutable.
            let path = executablePath(pid) ?? (args.split(separator: " ").first.map(String.init) ?? args)
            let name = displayName(executable: path)
            guard !protectedNames.contains(name) else { continue }
            result.append((pid, name, args, footprint, rss * 1024, String(cols[3]), seconds(etime: String(cols[3])), path.contains(".app/")))
        }
        return result.sorted { $0.footprint > $1.footprint }.prefix(12).map { $0 }
    }

    private nonisolated static func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// `top` écrit 40G, 6654M, 512K, 830B — parfois suivi de + ou -.
    private nonisolated static func parseTopSize(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
        guard let unit = text.last, let value = Double(text.dropLast()) else { return Double(text) }
        switch unit {
        case "G": return value * 1_073_741_824
        case "M": return value * 1_048_576
        case "K": return value * 1024
        case "B": return value
        default:  return Double(text)
        }
    }

    /// `ps` : [[jj-]hh:]mm:ss
    private nonisolated static func seconds(etime: String) -> Double {
        let dayParts = etime.split(separator: "-")
        let days = dayParts.count == 2 ? Double(dayParts[0]) ?? 0 : 0
        let clock = (dayParts.last ?? "").split(separator: ":").compactMap { Double($0) }
        let hms = clock.reversed().enumerated().reduce(0.0) { $0 + $1.element * pow(60, Double($1.offset)) }
        return days * 86_400 + hms
    }

    /// `…/Cursor Helper (Renderer).app/…/Cursor Helper (Renderer)` → `Cursor Helper (Renderer)` ; `/opt/…/node` → `node`.
    private nonisolated static func displayName(executable: String) -> String {
        (executable as NSString).lastPathComponent
    }

    private nonisolated static let protectedNames: Set<String> = [
        "Finder", "Dock", "SystemUIServer", "ControlCenter", "NotificationCenter",
        "loginwindow", "WindowServer", "NotchKiller",
    ]

    // MARK: Actions

    /// SIGTERM, puis SIGKILL après 5 s si le processus s'accroche : un test bloqué
    /// qui a rempli le swap n'a souvent plus la main pour s'arrêter proprement.
    func terminate(_ hog: MemoryHog) {
        terminate([hog])
    }

    func freeSwap() {
        terminate(swapHolders)
    }

    private func terminate(_ targets: [MemoryHog]) {
        guard !targets.isEmpty else { return }
        let freed = targets.reduce(0) { $0 + $1.footprint }
        for hog in targets {
            if let app = NSRunningApplication(processIdentifier: hog.pid), app.activationPolicy == .regular {
                app.terminate()
            } else {
                kill(hog.pid, SIGTERM)
            }
        }
        lastAction = targets.count == 1
            ? "\(targets[0].name) (\(targets[0].pid)) — arrêt demandé · \(Shell.formatBytes(freed))"
            : "\(targets.count) processus arrêtés · \(Shell.formatBytes(freed))"

        let pids = targets.filter { !$0.isApp }.map(\.pid)
        Task {
            try? await Task.sleep(for: .seconds(5))
            for pid in pids where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
            try? await Task.sleep(for: .seconds(1))
            refresh()
        }
    }

    /// `purge` vide les caches disque inactifs : la RAM rendue permet au système de
    /// rapatrier des pages et de réduire ensuite les fichiers de swap. Demande le mot de passe.
    func purge() {
        guard !isPurging else { return }
        isPurging = true
        lastAction = "Purge en cours…"
        Task.detached(priority: .userInitiated) {
            let script = "do shell script \"/usr/sbin/purge\" with administrator privileges"
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            let message = error == nil ? "Caches mémoire purgés" : "Purge annulée"
            await MainActor.run {
                self.isPurging = false
                self.lastAction = message
                self.refresh()
            }
        }
    }
}

// MARK: - Démo

extension MemoryModel {
    func loadDemo() {
        let gb = 1_073_741_824.0
        swapUsed = 1.2 * gb
        swapTotal = 2 * gb
        pressure = .warning
        hogs = [
            MemoryHog(pid: 611, name: "Safari", command: "/Applications/Safari.app", footprint: 2.4 * gb,
                      resident: 1.8 * gb, elapsed: "03:12:40", ageSeconds: 11_560, isApp: true),
            MemoryHog(pid: 902, name: "Xcode", command: "/Applications/Xcode.app", footprint: 1.9 * gb,
                      resident: 1.5 * gb, elapsed: "01:48:05", ageSeconds: 6_485, isApp: true),
            MemoryHog(pid: 48211, name: "node", command: "node server.js", footprint: 0.8 * gb,
                      resident: 0.6 * gb, elapsed: "02-04:10:00", ageSeconds: 187_800, isApp: false),
            MemoryHog(pid: 812, name: "postgres", command: "postgres -D /usr/local/var/postgres",
                      footprint: 0.21 * gb, resident: 0.18 * gb, elapsed: "05:00:12", ageSeconds: 18_012, isApp: false),
        ]
    }
}
