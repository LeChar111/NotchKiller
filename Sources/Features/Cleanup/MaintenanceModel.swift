import AppKit

/// Cache d'application qu'on peut supprimer directement : il se reconstruit au
/// prochain lancement de l'app. Jamais celui d'une app ouverte.
struct AppCacheItem: Identifiable, Equatable {
    var id: String { path }
    let path: String
    let name: String
    let bytes: Double
}

/// État publié par `audio-plugins-offload.sh` (root) dans
/// `/Library/Application Support/NotchKiller/audio-offload-status.json`.
struct AudioOffloadStatus: Decodable, Equatable {
    var state = "idle"
    var message = ""
    var done = 0
    var total = 0
    var current = ""
    var dest = ""
    var watching = false
    var destMounted = false
    var onMac = 0
    var onDest = 0
    var onMacKB = 0
    var intruders = 0
    var updatedAt: Double = 0
}

/// État publié par `nk-maintenance.sh` après chaque passage hebdomadaire.
struct MaintenanceRunStatus: Decodable, Equatable {
    var lastRun: Double = 0
    var freeGB = 0
    var freedMB = 0
    var offloadMounted = true
}

@MainActor
@Observable
final class MaintenanceModel {
    static let shared = MaintenanceModel()

    static let agentLabel = "io.github.lechar111.notchkiller.maintenance"
    static let daemonLabel = "io.github.lechar111.notchkiller.audio-offload"
    nonisolated static let audioStatusPath = "/Library/Application Support/NotchKiller/audio-offload-status.json"
    nonisolated static let audioLogPath = "/Library/Logs/NotchKiller/audio-offload.log"
    private static let destKey = "nk.maintenance.audioDest"

    // Disques
    private(set) var internalFree: Double = 0
    private(set) var internalTotal: Double = 0
    private(set) var externalName: String?
    private(set) var externalFree: Double?

    // Caches d'apps
    private(set) var caches: [AppCacheItem] = []
    private(set) var isScanningCaches = false
    private(set) var cachesScanned = false
    var cachesTotal: Double { caches.reduce(0) { $0 + $1.bytes } }

    // Plug-ins audio
    private(set) var audio = AudioOffloadStatus()
    private(set) var audioRunning = false
    var audioDest: String {
        didSet { UserDefaults.standard.set(audioDest, forKey: Self.destKey) }
    }

    // Entretien hebdomadaire
    private(set) var agentInstalled = false
    private(set) var lastRun: MaintenanceRunStatus?

    private(set) var lastAction: String?
    private var pollTask: Task<Void, Never>?

    private init() {
        audioDest = UserDefaults.standard.string(forKey: Self.destKey) ?? ""
        if Demo.isActive { loadDemo() } else { refresh() }
    }

    /// Volume qui porte la destination (« /Volumes/X »), s'il y en a une.
    var externalRoot: String? {
        let parts = audioDest.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == "Volumes" else { return nil }
        return "/Volumes/\(parts[1])"
    }

    // MARK: Rafraîchissement

    func refresh() {
        guard !Demo.isActive else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            internalFree = Double(values.volumeAvailableCapacityForImportantUsage ?? 0)
            internalTotal = Double(values.volumeTotalCapacity ?? 0)
        }
        if let root = externalRoot, FileManager.default.fileExists(atPath: root),
           let values = try? URL(fileURLWithPath: root).resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeNameKey]) {
            externalName = values.volumeName ?? (root as NSString).lastPathComponent
            externalFree = Double(values.volumeAvailableCapacity ?? 0)
        } else {
            externalName = externalRoot.map { ($0 as NSString).lastPathComponent }
            externalFree = nil
        }
        if let data = FileManager.default.contents(atPath: Self.audioStatusPath),
           let status = try? JSONDecoder().decode(AudioOffloadStatus.self, from: data) {
            audio = status
        }
        agentInstalled = FileManager.default.fileExists(
            atPath: home.appendingPathComponent("Library/LaunchAgents/\(Self.agentLabel).plist").path)
        let statusURL = home.appendingPathComponent("Library/Application Support/NotchKiller/maintenance-status.json")
        if let data = try? Data(contentsOf: statusURL) {
            lastRun = try? JSONDecoder().decode(MaintenanceRunStatus.self, from: data)
        }
    }

    // MARK: Caches d'apps

    func scanCaches() {
        if Demo.isActive { return }
        guard !isScanningCaches else { return }
        isScanningCaches = true
        let running = Self.runningAppKeys()
        Task.detached(priority: .utility) {
            let found = Self.collectCaches(running: running)
            await MainActor.run {
                self.caches = found
                self.isScanningCaches = false
                self.cachesScanned = true
            }
        }
    }

    /// Suppression directe, pas la corbeille : un cache mis à la corbeille occupe
    /// toujours le disque, et il se reconstruit de toute façon.
    func purgeCaches() {
        guard !isScanningCaches else { return }
        // Une app a pu s'ouvrir depuis l'analyse : on refiltre au dernier moment.
        let running = Self.runningAppKeys()
        let batch = caches.filter { !Self.belongsToRunningApp($0.path, running: running) }
        isScanningCaches = true
        Task.detached(priority: .utility) {
            var freed = 0.0, count = 0
            for item in batch where (try? FileManager.default.removeItem(atPath: item.path)) != nil {
                freed += item.bytes; count += 1
            }
            let summary = "\(count) cache\(count > 1 ? "s" : "") supprimé\(count > 1 ? "s" : "") · \(Shell.formatBytes(freed))"
            await MainActor.run {
                self.caches.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
                self.isScanningCaches = false
                self.lastAction = summary
                self.refresh()
            }
        }
    }

    /// Noms (minuscules) des apps ouvertes : bundle id, nom affiché, premier mot du
    /// nom (« brave » couvre « BraveSoftware »), nom du binaire.
    private static func runningAppKeys() -> Set<String> {
        var keys = Set<String>()
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier?.lowercased() { keys.insert(id) }
            if let name = app.localizedName?.lowercased() {
                keys.insert(name)
                if let first = name.split(separator: " ").first, first.count >= 4 { keys.insert(String(first)) }
            }
            if let exe = app.executableURL?.lastPathComponent.lowercased() { keys.insert(exe) }
        }
        return keys
    }

    nonisolated private static func belongsToRunningApp(_ path: String, running: Set<String>) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let relative = path.replacingOccurrences(of: home + "/Library/", with: "")
        guard let owner = relative.split(separator: "/").dropFirst().first?.lowercased() else { return false }
        let compact = owner.replacingOccurrences(of: " ", with: "")
        return running.contains { key in
            let k = key.replacingOccurrences(of: " ", with: "")
            return k == compact || k.hasPrefix(compact) || (compact.hasPrefix(k) && k.count >= 4)
        }
    }

    nonisolated private static func collectCaches(running: Set<String>) -> [AppCacheItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var candidates: [(String, String)] = []

        // ~/Library/Caches : tout sauf le système et les liens (déjà sur un autre disque).
        let systemPrefixes = ["com.apple.", "CloudKit", "GeoServices", "FamilyCircle", "Metadata"]
        let cachesDir = "\(home)/Library/Caches"
        for entry in (try? fm.contentsOfDirectory(atPath: cachesDir)) ?? [] where !entry.hasPrefix(".") {
            guard !systemPrefixes.contains(where: { entry.hasPrefix($0) }) else { continue }
            let path = "\(cachesDir)/\(entry)"
            guard (try? fm.destinationOfSymbolicLink(atPath: path)) == nil else { continue }
            candidates.append((path, entry))
        }

        // Caches Chromium/Electron rangés dans Application Support.
        let electron = ["Cache", "Code Cache", "GPUCache", "CachedData", "Crashpad", "DawnCache",
                        "DawnGraphiteCache", "DawnWebGPUCache", "Service Worker/CacheStorage", "logs"]
        let support = "\(home)/Library/Application Support"
        for app in (try? fm.contentsOfDirectory(atPath: support)) ?? [] where !app.hasPrefix(".") && !app.hasPrefix("com.apple.") {
            for folder in electron {
                let path = "\(support)/\(app)/\(folder)"
                if fm.fileExists(atPath: path) { candidates.append((path, "\(app) · \(folder)")) }
            }
        }

        // Temporaires de plus de 3 jours.
        let tmp = NSTemporaryDirectory()
        let limit = Date().addingTimeInterval(-3 * 86_400)
        for entry in (try? fm.contentsOfDirectory(atPath: tmp)) ?? [] {
            let path = (tmp as NSString).appendingPathComponent(entry)
            if let date = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date, date < limit {
                candidates.append((path, "Temporaire · \(entry)"))
            }
        }

        candidates.removeAll { belongsToRunningApp($0.0, running: running) }
        let sizes = Shell.diskUsage(of: candidates.map(\.0))
        return candidates.compactMap { path, name in
            guard let bytes = sizes[path], bytes > 1_048_576 else { return nil }
            return AppCacheItem(path: path, name: name, bytes: bytes)
        }
        .sorted { $0.bytes > $1.bytes }
    }

    // MARK: Plug-ins audio

    enum AudioAction {
        case move, watch, unwatch, quarantine, restore
        var flag: String {
            switch self {
            case .move: ""
            case .watch: "--watch"
            case .unwatch: "--unwatch"
            case .quarantine: "--quarantine"
            case .restore: "--restore"
            }
        }
        var label: String {
            switch self {
            case .move: "Déplacement"
            case .watch: "Surveillance"
            case .unwatch: "Arrêt de la surveillance"
            case .quarantine: "Quarantaine"
            case .restore: "Rapatriement"
            }
        }
    }

    func chooseAudioDest() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choisir"
        panel.message = "Dossier du disque externe qui recevra les plug-ins audio"
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            audioDest = url.path
            refresh()
        }
    }

    /// Lance le moteur en root (fenêtre de mot de passe macOS) et suit sa progression.
    func runAudio(_ action: AudioAction) {
        guard !audioRunning, !audioDest.isEmpty || action == .unwatch else { return }
        audioRunning = true
        lastAction = "\(action.label) des plug-ins…"
        let script = MaintenanceScripts.install().appendingPathComponent(MaintenanceScripts.audioOffloadName).path
        var args = ["/bin/zsh", "-f", script, "--quiet"]
        if !audioDest.isEmpty { args += ["--dest", audioDest] }
        if !action.flag.isEmpty { args.append(action.flag) }
        let command = args.map(Self.shellQuote).joined(separator: " ")
        startPolling()

        Task.detached(priority: .userInitiated) {
            let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            var error: NSDictionary?
            NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(&error)
            let cancelled = (error?[NSAppleScript.errorNumber] as? Int) == -128
            let failed = error != nil
            await MainActor.run {
                self.audioRunning = false
                self.pollTask?.cancel()
                self.refresh()
                if cancelled {
                    self.lastAction = "\(action.label) annulé"
                } else if failed, self.audio.message.isEmpty {
                    self.lastAction = "\(action.label) : échec — voir le journal"
                } else {
                    self.lastAction = self.audio.message.isEmpty ? "\(action.label) terminé" : self.audio.message
                }
            }
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                self?.refresh()
            }
        }
    }

    func openAudioLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: Self.audioLogPath))
    }

    nonisolated private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: Entretien hebdomadaire (LaunchAgent)

    private var agentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Self.agentLabel).plist")
    }

    func installAgent() {
        let script = MaintenanceScripts.install().appendingPathComponent(MaintenanceScripts.maintenanceName).path
        var arguments = ["/bin/zsh", "-f", script]
        if let root = externalRoot { arguments += ["--offload-root", root] }
        let plist: [String: Any] = [
            "Label": Self.agentLabel,
            "ProgramArguments": arguments,
            // Lundi, 10 h : un passage par semaine suffit, et l'agent rattrape au réveil.
            "StartCalendarInterval": ["Weekday": 1, "Hour": 10, "Minute": 0],
            "LowPriorityIO": true,
            "Nice": 10,
        ]
        do {
            try FileManager.default.createDirectory(at: agentPlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: agentPlistURL, options: .atomic)
            launchctl(["bootout", "gui/\(getuid())/\(Self.agentLabel)"])
            launchctl(["bootstrap", "gui/\(getuid())", agentPlistURL.path])
            lastAction = "Entretien hebdomadaire activé · lundi 10 h"
        } catch {
            lastAction = "Entretien : échec — \(error.localizedDescription)"
        }
        refresh()
    }

    func removeAgent() {
        launchctl(["bootout", "gui/\(getuid())/\(Self.agentLabel)"])
        try? FileManager.default.removeItem(at: agentPlistURL)
        lastAction = "Entretien hebdomadaire désactivé"
        refresh()
    }

    func runAgentNow() {
        if !agentInstalled { installAgent() }
        launchctl(["kickstart", "gui/\(getuid())/\(Self.agentLabel)"])
        lastAction = "Entretien lancé"
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            self?.refresh()
        }
    }

    func openAgentLog() {
        let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/NotchKiller/maintenance.log")
        NSWorkspace.shared.open(log)
    }

    private func launchctl(_ arguments: [String]) {
        Shell.run("/bin/launchctl", arguments)
    }
}

// MARK: - Démo

extension MaintenanceModel {
    func loadDemo() {
        let gb = 1_073_741_824.0
        internalFree = 113 * gb
        internalTotal = 460 * gb
        externalName = "Studio SSD"
        externalFree = 517 * gb
        audioDest = "/Volumes/Studio SSD/Audio/Plug-Ins"
        audio = AudioOffloadStatus(state: "idle", message: "12 déplacé(s)", dest: audioDest, watching: true,
                                   destMounted: true, onMac: 3, onDest: 196, onMacKB: 84_000)
        caches = [
            AppCacheItem(path: "\(Demo.home)/Library/Application Support/Slack/Service Worker/CacheStorage", name: "Slack · Service Worker/CacheStorage", bytes: 0.48 * gb),
            AppCacheItem(path: "\(Demo.home)/Library/Caches/com.spotify.client", name: "com.spotify.client", bytes: 0.2 * gb),
        ]
        cachesScanned = true
        agentInstalled = true
        lastRun = MaintenanceRunStatus(lastRun: Date().addingTimeInterval(-2 * 86_400).timeIntervalSince1970,
                                       freeGB: 113, freedMB: 640, offloadMounted: true)
    }
}
