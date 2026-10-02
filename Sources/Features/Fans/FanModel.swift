import AppKit

/// Résumé d'une famille de sondes : la moyenne dit l'état d'ensemble, le maximum
/// dit ce qui chauffe.
struct ThermalSummary: Identifiable, Equatable {
    let group: ThermalGroup
    let sensors: [ThermalSensor]

    var id: ThermalGroup { group }
    var average: Double { sensors.isEmpty ? 0 : sensors.reduce(0) { $0 + $1.celsius } / Double(sensors.count) }
    var hottest: Double { sensors.map(\.celsius).max() ?? 0 }
}

enum FanPreset: String, CaseIterable, Identifiable {
    case automatic, full, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatique"
        case .full:      "Plein régime"
        case .custom:    "Personnalisé"
        }
    }
}

/// Lecture des ventilateurs et des sondes (SMC, sans privilège) et pilotage par
/// l'assistant root NotchKillerFanHelper, joint sur son socket Unix.
@MainActor
@Observable
final class FanModel {
    static let shared = FanModel()

    enum HelperState: Equatable {
        /// Pas de LaunchDaemon : lecture seule.
        case missing
        /// Installé mais muet (démarrage, plantage) : launchd le relance.
        case unreachable
        /// L'assistant installé est plus ancien que celui embarqué.
        case outdated
        case ready
    }

    private(set) var fans: [FanReading] = []
    private(set) var sensors: [ThermalSensor] = []
    private(set) var modes: [FanMode] = []
    private(set) var helper: HelperState = .missing
    private(set) var isWorking = false
    private(set) var lastAction: String?
    /// Température la plus haute du CPU sur les derniers relevés (2 s chacun).
    private(set) var cpuHistory: [Double] = []
    /// Macs Fan Control ouvert : deux pilotes qui écrivent la même consigne se la disputent.
    private(set) var competitor: NSRunningApplication?

    private var timer: Timer?
    private var subscribers = 0
    private var isRefreshing = false

    private static let competitorID = "com.crystalidea.macsfancontrol"

    private init() {}

    // MARK: Abonnement

    func subscribe() {
        subscribers += 1
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        timer?.tolerance = 0.3
    }

    func unsubscribe() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    // MARK: Relevé

    var summaries: [ThermalSummary] {
        let grouped = Dictionary(grouping: sensors, by: \.group)
        return ThermalGroup.allCases.compactMap { group in
            guard let members = grouped[group], !members.isEmpty else { return nil }
            return ThermalSummary(group: group, sensors: members.sorted { $0.key < $1.key })
        }
    }

    var preset: FanPreset {
        guard !modes.isEmpty else { return .automatic }
        if modes.allSatisfy({ $0 == .auto }) { return .automatic }
        let full = zip(modes, fans).allSatisfy { mode, fan in
            if case .constant(let rpm) = mode { return rpm >= fan.maximum - 1 }
            return false
        }
        return full && modes.count == fans.count ? .full : .custom
    }

    func mode(of fan: FanReading) -> FanMode {
        fan.index < modes.count ? modes[fan.index] : .auto
    }

    func refresh() {
        if Demo.isActive { loadDemo(); return }
        competitor = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == Self.competitorID }
        guard !isRefreshing else { return }
        isRefreshing = true

        Task.detached(priority: .utility) {
            let reading = SensorReader.shared.read()
            let status = FanHelperClient.send(FanRequest(command: .status))
            let installed = FileManager.default.fileExists(atPath: FanHelper.plistPath)
            await MainActor.run {
                self.isRefreshing = false
                self.fans = reading.fans
                self.sensors = reading.sensors
                if let hottest = self.sensors.filter({ $0.group == .cpuPerformance || $0.group == .cpuEfficiency }).map(\.celsius).max() {
                    self.cpuHistory = Array((self.cpuHistory + [hottest]).suffix(30))
                }
                self.apply(status, installed: installed)
            }
        }
    }

    private func apply(_ response: FanResponse?, installed: Bool) {
        guard let response else {
            helper = installed ? .unreachable : .missing
            modes = []
            return
        }
        helper = response.version < FanHelper.version ? .outdated : .ready
        modes = response.modes
    }

    // MARK: Pilotage

    func setMode(_ mode: FanMode, for fan: FanReading) {
        guard helper == .ready else { return }
        if fan.index < modes.count { modes[fan.index] = mode }
        send(FanRequest(command: .set, fan: fan.index, mode: mode))
    }

    func apply(_ preset: FanPreset) {
        guard helper == .ready else { return }
        switch preset {
        case .automatic:
            modes = modes.map { _ in .auto }
            send(FanRequest(command: .reset))
        case .full:
            for fan in fans { setMode(.constant(rpm: fan.maximum), for: fan) }
        case .custom:
            break
        }
    }

    private func send(_ request: FanRequest) {
        if Demo.isActive { return }
        Task.detached(priority: .userInitiated) {
            let response = FanHelperClient.send(request)
            await MainActor.run {
                if let response {
                    self.apply(response, installed: true)
                    if let error = response.error { self.lastAction = "Assistant : \(error)" }
                } else {
                    self.lastAction = "L'assistant ne répond pas"
                }
            }
        }
    }

    func quitCompetitor() {
        competitor?.terminate()
        lastAction = "Macs Fan Control fermé"
        Task {
            try? await Task.sleep(for: .seconds(1))
            refresh()
        }
    }

    // MARK: Installation de l'assistant

    /// Une seule fenêtre de mot de passe : copie de l'assistant dans /Library, puis
    /// LaunchDaemon chargé par launchd. Réinstaller remplace l'ancien.
    func installHelper() {
        if Demo.isActive { lastAction = "Mode démo — aucune action réelle"; return }
        guard !isWorking else { return }
        guard let source = Bundle.main.url(forResource: "NotchKillerFanHelper", withExtension: nil)?.path else {
            lastAction = "Assistant absent du paquet — relancez build.sh"
            return
        }
        let plist = Self.daemonPlist(uid: getuid())
        let label = FanHelper.label
        let script = """
        set -e
        mkdir -p \(Self.quote(FanHelper.supportDir)) /Library/Logs/NotchKiller
        /bin/launchctl bootout system/\(label) 2>/dev/null || true
        i=0; while /bin/launchctl print system/\(label) >/dev/null 2>&1 && [ $i -lt 20 ]; do sleep 0.25; i=$((i+1)); done
        /usr/bin/install -o root -g wheel -m 755 \(Self.quote(source)) \(Self.quote(FanHelper.installedPath))
        /usr/bin/install -o root -g wheel -m 644 "$1" \(Self.quote(FanHelper.plistPath))
        /bin/launchctl bootstrap system \(Self.quote(FanHelper.plistPath))
        """
        runPrivileged(script, attachment: plist, working: "Installation de l'assistant…",
                      done: "Assistant installé — pilotage actif", failed: "Installation impossible")
    }

    /// Arrêter le service rend les ventilateurs au système (l'assistant s'en charge
    /// en recevant SIGTERM), puis on efface ses fichiers.
    func uninstallHelper() {
        if Demo.isActive { lastAction = "Mode démo — aucune action réelle"; return }
        guard !isWorking else { return }
        let script = """
        /bin/launchctl bootout system/\(FanHelper.label) 2>/dev/null || true
        rm -f \(Self.quote(FanHelper.plistPath)) \(Self.quote(FanHelper.installedPath)) \(Self.quote(FanHelper.statePath))
        """
        runPrivileged(script, attachment: nil, working: "Désinstallation…",
                      done: "Assistant retiré — ventilateurs rendus au système", failed: "Désinstallation impossible")
    }

    private func runPrivileged(_ body: String, attachment: String?, working: String, done: String, failed: String) {
        isWorking = true
        lastAction = working
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("notchkiller-fans-\(UUID().uuidString)")

        Task.detached(priority: .userInitiated) {
            var error: NSDictionary?
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let scriptURL = directory.appendingPathComponent("run.sh")
                try body.write(to: scriptURL, atomically: true, encoding: .utf8)
                var command = "/bin/sh \(Self.quote(scriptURL.path))"
                if let attachment {
                    let attachmentURL = directory.appendingPathComponent("daemon.plist")
                    try attachment.write(to: attachmentURL, atomically: true, encoding: .utf8)
                    command += " \(Self.quote(attachmentURL.path))"
                }
                let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(&error)
            } catch let failure {
                error = [NSAppleScript.errorMessage: failure.localizedDescription]
            }
            try? FileManager.default.removeItem(at: directory)
            let cancelled = (error?[NSAppleScript.errorNumber] as? Int) == -128
            let message = error == nil ? done : (cancelled ? "Annulé" : failed)

            // Le service met un instant à ouvrir son socket.
            for _ in 0..<10 where error == nil && attachment != nil {
                if FanHelperClient.send(FanRequest(command: .status)) != nil { break }
                try? await Task.sleep(for: .milliseconds(300))
            }
            await MainActor.run {
                self.isWorking = false
                self.lastAction = message
                self.refresh()
            }
        }
    }

    nonisolated private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated private static func daemonPlist(uid: uid_t) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(FanHelper.label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(FanHelper.installedPath)</string>
                <string>--uid</string>
                <string>\(uid)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardErrorPath</key>
            <string>\(FanHelper.logPath)</string>
        </dict>
        </plist>
        """
    }
}

// MARK: - Lecture SMC

/// Une seule connexion SMC, réservée au relevé en arrière-plan. Les clés de
/// température sont repérées au premier passage (parcours des ~3 300 clés), puis
/// seules celles-ci sont relues.
final class SensorReader: @unchecked Sendable {
    static let shared = SensorReader()

    private let lock = NSLock()
    private let smc = SMC()
    private var temperatureKeys: [String]?

    func read() -> (fans: [FanReading], sensors: [ThermalSensor]) {
        lock.lock()
        defer { lock.unlock() }
        guard let smc else { return ([], []) }
        if temperatureKeys == nil { temperatureKeys = smc.temperatureKeys() }
        return (smc.fans(), smc.temperatures(temperatureKeys ?? []))
    }
}

// MARK: - Client du socket

enum FanHelperClient {
    /// Une requête, une réponse, une connexion. `nil` : assistant absent ou muet.
    nonisolated static func send(_ request: FanRequest) -> FanResponse? {
        guard var payload = try? JSONEncoder().encode(request) else { return nil }
        payload.append(UInt8(ascii: "\n"))

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (index, byte) in FanHelper.socketPath.utf8.prefix(buffer.count - 1).enumerated() { buffer[index] = byte }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }

        let written = payload.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard written == payload.count else { return nil }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return try? JSONDecoder().decode(FanResponse.self, from: data)
    }
}

// MARK: - Démo

extension FanModel {
    func loadDemo() {
        fans = [
            FanReading(index: 0, actual: 2_140, minimum: 1_350, maximum: 5_777, target: 2_140, forced: false),
            FanReading(index: 1, actual: 2_210, minimum: 1_350, maximum: 5_777, target: 2_210, forced: false),
        ]
        modes = [.auto, .sensor(group: .cpuPerformance, low: 55, high: 90)]
        helper = .ready
        let values: [(String, Double)] = [
            ("Tp01", 58.2), ("Tp05", 61.4), ("Tp09", 57.9), ("Tp0D", 63.0), ("Te05", 48.6), ("Te0S", 47.9),
            ("Tg0G", 44.1), ("Tg0H", 45.3), ("TH0x", 36.8), ("TB0T", 31.2), ("TB1T", 30.8),
            ("TW0P", 41.5), ("TaLP", 33.0), ("TaRF", 34.2), ("Ts0P", 29.4),
        ]
        sensors = values.map { ThermalSensor(key: $0.0, celsius: $0.1) }
        cpuHistory = [55, 56, 58, 61, 60, 59, 62, 64, 63, 61, 60, 63]
    }
}
