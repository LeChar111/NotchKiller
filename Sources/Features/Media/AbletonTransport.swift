import AppKit
import CoreMIDI

/// Ableton Live dans l'encoche. Deux sources, la plus riche l'emporte :
/// - le script d'extension NotchKiller (voir AbletonBridge) : tout le set,
///   en lecture comme en commande ;
/// - à défaut, la synchro MIDI : NotchKiller publie une destination virtuelle
///   « NotchKiller » que l'on coche en « Sync » dans Préférences → Link,
///   Tempo & MIDI. Live y envoie Start / Continue / Stop, la position
///   (Song Position Pointer) et l'horloge (24 tops par noire). Les commandes
///   passent alors par des raccourcis clavier envoyés au processus de Live.
/// S'y ajoutent ce que macOS dit de Live : titre de fenêtre (nom du set),
/// CPU et mémoire, et le drapeau de plantage que Live laisse derrière lui.
@MainActor
@Observable
final class AbletonTransport {
    static let shared = AbletonTransport()
    nonisolated static let bundleID = "com.ableton.live"

    struct Position: Equatable {
        let bar: Int
        let beat: Int
        let sixteenth: Int
        var label: String { "\(bar).\(beat).\(sixteenth)" }
    }

    struct Alert: Equatable {
        enum Kind { case crash, clipping }
        let kind: Kind
        let at: Date
    }

    struct DayStats: Codable, Equatable {
        var open: TimeInterval = 0
        var playing: TimeInterval = 0
        var recording: TimeInterval = 0
    }

    private(set) var isRunning = false
    /// Vrai dès qu'un message MIDI de transport ou d'horloge est arrivé.
    private(set) var isSynced = false
    private(set) var setName: String?
    private(set) var isSetModified = false
    private(set) var cpu: Double?
    private(set) var memory: Double?
    private(set) var alert: Alert?
    private(set) var today = DayStats()

    private var midiPlaying = false
    private var midiTempo: Double?
    private var midiSixteenths: Int?

    var bridge: AbletonBridge = .shared

    private var client = MIDIClientRef()
    private var destination = MIDIEndpointRef()
    private let clock = ClockMeter()
    private var watchdog: Timer?
    private var monitor: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastCPUTime: (wall: TimeInterval, cpu: UInt64)?
    private var lastClipAlert: TimeInterval = 0
    private var ticksSinceSave = 0

    private init() {
        guard !Demo.isActive else {
            isRunning = true
            setName = "Midnight Circuit"
            isSetModified = true
            cpu = 38
            memory = 2_300_000_000
            today = DayStats(open: 7_400, playing: 2_640, recording: 540)
            return
        }
        today = Self.loadStats()[Self.dayKey()] ?? DayStats()
        observeLaunches()
        setUpMIDI()
        setRunning(!NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty)
    }

    // MARK: État unifié

    var live: LiveState? { bridge.state }
    var hasScript: Bool { bridge.isConnected && bridge.state != nil }

    var isPlaying: Bool { live?.playing ?? midiPlaying }
    var tempo: Double? { live?.tempo ?? midiTempo }
    var isRecording: Bool { (live?.record ?? false) || (live?.sessionRecord ?? false) }
    /// Signal d'état connu : script ou synchro MIDI.
    var isTracking: Bool { hasScript || isSynced }

    /// Durée d'une mesure en noires (le temps de Live se compte en noires).
    private var barLength: Double {
        guard let live, live.den > 0 else { return 4 }
        return Double(live.num) * 4 / Double(live.den)
    }

    var position: Position? {
        if let live {
            let unit = 4 / Double(max(1, live.den))
            let inBar = live.time.truncatingRemainder(dividingBy: barLength)
            return Position(bar: Int(live.time / barLength) + 1,
                            beat: Int(inBar / unit) + 1,
                            sixteenth: Int(live.time.truncatingRemainder(dividingBy: 1) * 4) + 1)
        }
        guard let sixteenths = midiSixteenths else { return nil }
        return Position(bar: sixteenths / 16 + 1, beat: sixteenths % 16 / 4 + 1, sixteenth: sixteenths % 4 + 1)
    }

    /// Numéro du temps courant depuis le début du morceau : la pulsation de
    /// l'encoche s'anime à chaque changement.
    var beatIndex: Int? {
        if let live { return Int(live.time / (4 / Double(max(1, live.den)))) }
        return midiSixteenths.map { $0 / 4 }
    }

    var isDownbeat: Bool { position?.beat == 1 }

    /// Temps restant avant le dernier événement de l'arrangement.
    var remaining: TimeInterval? {
        guard let live, live.length > live.time, live.tempo > 0 else { return nil }
        return (live.length - live.time) * 60 / live.tempo
    }

    // MARK: Commandes

    func toggle() {
        if hasScript { bridge.send("toggle"); return }
        guard key(49) else { return }
        // Sans synchro, aucun retour de Live : on suppose que la touche a porté.
        if !isSynced { midiPlaying.toggle() }
    }

    func continuePlaying() {
        if hasScript { bridge.send("continue") } else { key(49, flags: .maskShift) }
    }

    func record() {
        if hasScript { bridge.send("record") } else { key(101) }  // F9
    }

    func switchView() { key(48) }                            // Tab
    func save() { key(1, flags: .maskCommand) }              // ⌘S
    func undo() {
        if hasScript { bridge.send("undo") } else { key(6, flags: .maskCommand) }
    }

    func redo() {
        if hasScript { bridge.send("redo") } else { key(6, flags: [.maskCommand, .maskShift]) }
    }

    func send(_ command: String, _ extra: [String: Any] = [:]) { bridge.send(command, extra) }

    func setTempo(_ value: Double) { bridge.send("tempo", ["value": value]) }

    func nudgeTempo(_ delta: Double) {
        guard let tempo = live?.tempo else { return }
        setTempo((tempo + delta).rounded(toPlaces: 2))
    }

    func open(_ url: URL) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    func dismissAlert() { alert = nil }

    /// Raccourci clavier envoyé au processus de Live, même en arrière-plan.
    /// Demande l'accès Accessibilité s'il manque.
    @discardableResult
    private func key(_ code: CGKeyCode, flags: CGEventFlags = []) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first else { return false }
        guard AXIsProcessTrusted() else {
            let option = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([option: true] as CFDictionary)
            return false
        }
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.postToPid(app.processIdentifier)
        }
        return true
    }

    // MARK: Lancement / arrêt de Live

    private func observeLaunches() {
        let center = NSWorkspace.shared.notificationCenter
        for (name, running) in [(NSWorkspace.didLaunchApplicationNotification, true),
                                (NSWorkspace.didTerminateApplicationNotification, false)] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == Self.bundleID else { return }
                MainActor.assumeIsolated { AbletonTransport.shared.setRunning(running) }
            })
        }
    }

    private func setRunning(_ running: Bool) {
        isRunning = running
        monitor?.invalidate()
        monitor = nil
        guard running else {
            midiPlaying = false
            midiTempo = nil
            midiSixteenths = nil
            isSynced = false
            setName = nil
            isSetModified = false
            cpu = nil
            memory = nil
            lastCPUTime = nil
            saveStats()
            checkForCrash()
            return
        }
        alert = nil
        monitor = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { AbletonTransport.shared.sample() }
        }
        sample()
    }

    /// Chaque seconde tant que Live tourne : temps de travail, titre, CPU,
    /// mémoire et saturation du master.
    private func sample() {
        rollDayIfNeeded()
        today.open += 1
        if isPlaying { today.playing += 1 }
        if isRecording && isPlaying { today.recording += 1 }
        ticksSinceSave += 1
        if ticksSinceSave >= 15 { saveStats() }

        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first else { return }
        let pid = app.processIdentifier
        if ticksSinceSave % 2 == 0 { readTitle(pid) }
        memory = ProcessControl.footprint(pid)
        cpu = cpuUsage(pid)
        watchClipping()
    }

    private func readTitle(_ pid: pid_t) {
        guard AXIsProcessTrusted() else { return }
        let element = AXUIElementCreateApplication(pid)
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windows) == .success,
              let list = windows as? [AXUIElement] else { return }
        for window in list {
            var title: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
            guard let text = title as? String, let parsed = Self.parseTitle(text) else { continue }
            if setName != parsed.name { setName = parsed.name }
            if isSetModified != parsed.modified { isSetModified = parsed.modified }
            return
        }
    }

    /// « Mon morceau* [Mon morceau Project] - Ableton Live 12 Suite » →
    /// (« Mon morceau », modifié). L'astérisque signale un set non enregistré.
    nonisolated static func parseTitle(_ title: String) -> (name: String, modified: Bool)? {
        guard let range = title.range(of: " - Ableton Live") else { return nil }
        var name = String(title[..<range.lowerBound])
        if let bracket = name.range(of: " [") { name = String(name[..<bracket.lowerBound]) }
        let modified = name.contains("*")
        name = name.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : (name, modified)
    }

    private func cpuUsage(_ pid: pid_t) -> Double? {
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard status == 0 else { return nil }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let total = (info.ri_user_time + info.ri_system_time) * UInt64(timebase.numer) / UInt64(timebase.denom)
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastCPUTime = (now, total) }
        guard let last = lastCPUTime, now > last.wall, total >= last.cpu else { return nil }
        return Double(total - last.cpu) / 1e9 / (now - last.wall) * 100
    }

    private func watchClipping() {
        guard let peak = live?.master.max(), peak >= 0.999, isPlaying else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastClipAlert > 10 else { return }
        lastClipAlert = now
        alert = Alert(kind: .clipping, at: Date())
    }

    /// Live écrit « Running » dans CrashDetection.cfg à l'ouverture et le
    /// remplace en quittant proprement : resté tel quel, c'est un plantage.
    private func checkForCrash() {
        Task {
            try? await Task.sleep(for: .seconds(2))
            guard !isRunning,
                  let folder = Self.latestPreferencesFolder,
                  let data = try? Data(contentsOf: folder.appending(path: "CrashDetection.cfg")),
                  String(decoding: data, as: UTF8.self).contains("\"Running\"") else { return }
            alert = Alert(kind: .crash, at: Date())
        }
    }

    private static var latestPreferencesFolder: URL? { AbletonBridge.latestPreferencesFolder }

    // MARK: Temps de travail

    private static let statsKey = "ableton.stats"
    private var currentDay = AbletonTransport.dayKey()

    private static func dayKey(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func loadStats() -> [String: DayStats] {
        guard let data = UserDefaults.standard.data(forKey: statsKey),
              let stats = try? JSONDecoder().decode([String: DayStats].self, from: data) else { return [:] }
        return stats
    }

    private func rollDayIfNeeded() {
        let key = Self.dayKey()
        guard key != currentDay else { return }
        saveStats()
        currentDay = key
        today = DayStats()
    }

    private func saveStats() {
        ticksSinceSave = 0
        var stats = Self.loadStats()
        stats[currentDay] = today
        // Deux semaines d'historique suffisent.
        let kept = stats.keys.sorted().suffix(14)
        stats = stats.filter { kept.contains($0.key) }
        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: Self.statsKey)
        }
    }

    // MARK: MIDI

    private func setUpMIDI() {
        guard MIDIClientCreateWithBlock("NotchKiller" as CFString, &client, nil) == noErr else { return }
        let meter = clock
        MIDIDestinationCreateWithProtocol(client, "NotchKiller" as CFString, ._1_0, &destination) { list, _ in
            for message in Self.systemMessages(in: list) {
                let update = meter.handle(message)
                guard update.status != nil || update.tempo != nil || update.sixteenths != nil else { continue }
                Task { @MainActor in AbletonTransport.shared.receive(update) }
            }
        }
    }

    private func receive(_ update: ClockMeter.Update) {
        isSynced = true
        if let bpm = update.tempo { midiTempo = (bpm * 10).rounded() / 10 }
        if let sixteenths = update.sixteenths { midiSixteenths = sixteenths }
        switch update.status {
        case 0xFA, 0xFB:
            midiPlaying = true
            startWatchdog()
        case 0xFC:
            midiPlaying = false
        default:
            break
        }
    }

    /// Live cesse d'envoyer l'horloge à l'arrêt, et ne dit rien s'il plante :
    /// une horloge muette depuis une seconde vaut un arrêt.
    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            MainActor.assumeIsolated {
                let transport = AbletonTransport.shared
                guard transport.midiPlaying else { timer.invalidate(); return }
                if let last = transport.clock.lastTick, ProcessInfo.processInfo.systemUptime - last > 1 {
                    transport.midiPlaying = false
                    timer.invalidate()
                }
            }
        }
    }

    /// Messages système (type UMP 0x1) d'une liste MIDI 1.0 : statut et deux octets.
    nonisolated private static func systemMessages(in list: UnsafePointer<MIDIEventList>) -> [(UInt8, UInt8, UInt8)] {
        var messages: [(UInt8, UInt8, UInt8)] = []
        let offset = MemoryLayout<MIDIEventPacket>.offset(of: \.words) ?? 0
        for packet in list.unsafeSequence() {
            let count = Int(packet.pointee.wordCount)
            let words = UnsafeRawPointer(packet).advanced(by: offset).assumingMemoryBound(to: UInt32.self)
            var i = 0
            while i < count {
                let word = words[i]
                let type = word >> 28
                if type == 0x1 {
                    messages.append((UInt8((word >> 16) & 0xFF), UInt8((word >> 8) & 0x7F), UInt8(word & 0x7F)))
                }
                switch type {
                case 0x0, 0x1, 0x2, 0x6, 0x7: i += 1
                case 0x3, 0x4, 0x8, 0x9, 0xA: i += 2
                case 0xB, 0xC:                i += 3
                default:                      i += 4
                }
            }
        }
        return messages
    }
}

/// Suit l'horloge MIDI sur le fil CoreMIDI : tempo mesuré à chaque noire,
/// position en doubles croches (6 tops chacune).
private final class ClockMeter: @unchecked Sendable {
    struct Update: Sendable {
        var status: UInt8?
        var tempo: Double?
        var sixteenths: Int?
    }

    private let lock = NSLock()
    private var ticks = 0
    private var beatStart: TimeInterval?
    private var last: TimeInterval?
    private var sixteenths = 0
    private var clocksInSixteenth = 0

    var lastTick: TimeInterval? { lock.withLock { last } }

    func handle(_ message: (UInt8, UInt8, UInt8)) -> Update {
        let (status, lsb, msb) = message
        return lock.withLock {
            var update = Update()
            switch status {
            case 0xF8:
                let now = ProcessInfo.processInfo.systemUptime
                // Un trou d'une seconde (arrêt, changement de port) relance la mesure.
                if let last, now - last > 1 { ticks = 0; beatStart = nil }
                last = now
                clocksInSixteenth += 1
                if clocksInSixteenth == 6 {
                    clocksInSixteenth = 0
                    sixteenths += 1
                    update.sixteenths = sixteenths
                }
                if let start = beatStart {
                    ticks += 1
                    if ticks == 24 {
                        ticks = 0
                        beatStart = now
                        let elapsed = now - start
                        if elapsed > 0 { update.tempo = 60 / elapsed }
                    }
                } else {
                    beatStart = now
                }
            case 0xF2:
                sixteenths = Int(lsb) | Int(msb) << 7
                clocksInSixteenth = 0
                update.sixteenths = sixteenths
            case 0xFA:
                sixteenths = 0
                clocksInSixteenth = 0
                ticks = 0
                beatStart = nil
                update.status = status
                update.sixteenths = 0
            case 0xFB, 0xFC:
                ticks = 0
                beatStart = nil
                update.status = status
            default:
                break
            }
            return update
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
