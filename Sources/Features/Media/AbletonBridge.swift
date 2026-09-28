import AppKit

/// État du set tel que l'envoie le script d'extension NotchKiller installé dans
/// Live (Tools/ableton/NotchKiller/__init__.py), dix fois par seconde.
struct LiveState: Decodable, Equatable {
    struct Meter: Decodable, Equatable {
        let name: String
        let color: Int
        let l: Double
        let r: Double
        let mute: Bool
    }

    struct Track: Decodable, Equatable {
        let name: String
        let color: Int
        let master: Bool
        let canArm: Bool
        let arm: Bool
        let mute: Bool
        let solo: Bool
        let clip: String?
        let l: Double
        let r: Double
    }

    struct Cue: Decodable, Equatable {
        let name: String
        let time: Double
    }

    struct Scene: Decodable, Equatable {
        let name: String
        let color: Int
        let triggered: Bool
    }

    struct Clip: Decodable, Equatable {
        let name: String
        let color: Int
        /// 0 arrêté, 1 déclenché, 2 en lecture, 3 en enregistrement.
        let state: Int
    }

    struct Column: Decodable, Equatable {
        let name: String
        let color: Int
        let clips: [Clip?]
    }

    let v: Int
    let playing: Bool
    let tempo: Double
    let time: Double
    let length: Double
    let num: Int
    let den: Int
    let record: Bool
    let sessionRecord: Bool
    let overdub: Bool
    let metronome: Bool
    let loop: Bool
    let loopStart: Double
    let loopLength: Double
    let punchIn: Bool
    let punchOut: Bool
    let canUndo: Bool
    let canRedo: Bool
    let master: [Double]
    let groups: [Meter]
    let track: Track
    let cues: [Cue]
    let scenes: [Scene]
    let grid: [Column]
    let offset: [Int]
    let size: [Int]
}

/// Liaison UDP locale avec le script d'extension : l'état arrive sur 9102, les
/// commandes partent vers 9101. Sans paquet depuis 1,5 s, le script est
/// considéré absent et l'encoche retombe sur la synchro MIDI.
@MainActor
@Observable
final class AbletonBridge {
    static let shared = AbletonBridge()

    /// Version attendue du script ; plus ancienne, on propose la mise à jour.
    static let scriptVersion = 1
    private static let listenPort: UInt16 = 9102
    private static let commandPort: UInt16 = 9101

    private(set) var state: LiveState?
    private(set) var isConnected = false

    private var socketFD: Int32 = -1
    private var source: DispatchSourceRead?
    private var lastPacket: TimeInterval = 0
    private var liveness: Timer?

    private init() {
        open()
        if Demo.isActive, let demo = Self.demoState {
            state = demo
            isConnected = true
        }
    }

    var needsUpdate: Bool {
        guard let state else { return false }
        return state.v < Self.scriptVersion
    }

    // MARK: Commandes

    func send(_ command: String, _ extra: [String: Any] = [:]) {
        guard socketFD >= 0 else { return }
        var message = extra
        message["cmd"] = command
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        var address = Self.loopback(port: Self.commandPort)
        _ = data.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(socketFD, bytes.baseAddress, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    // MARK: Réception

    private func open() {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = Self.loopback(port: Self.listenPort)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { close(fd); return }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        socketFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInitiated))
        source.setEventHandler {
            // On vide la file et ne garde que l'état le plus récent.
            var latest: Data?
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while true {
                let count = recv(fd, &buffer, buffer.count, 0)
                guard count > 0 else { break }
                latest = Data(buffer[0..<count])
            }
            guard let latest else { return }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            guard let decoded = try? decoder.decode(LiveState.self, from: latest) else { return }
            Task { @MainActor in AbletonBridge.shared.receive(decoded) }
        }
        source.resume()
        self.source = source

        liveness = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated {
                let bridge = AbletonBridge.shared
                guard bridge.isConnected, bridge.lastPacket > 0,
                      ProcessInfo.processInfo.systemUptime - bridge.lastPacket > 1.5 else { return }
                bridge.isConnected = false
                bridge.state = nil
            }
        }
    }

    private func receive(_ decoded: LiveState) {
        lastPacket = ProcessInfo.processInfo.systemUptime
        if !isConnected { isConnected = true }
        if decoded != state { state = decoded }
    }

    private static func loopback(port: UInt16) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return address
    }

    // MARK: Installation du script

    /// Dossier « Remote Scripts » de la User Library, lu dans Library.cfg de la
    /// version la plus récente de Live ; ~/Music/Ableton par défaut.
    static var remoteScriptsFolder: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var root = home.appending(path: "Music/Ableton")
        if let prefs = latestPreferencesFolder,
           let data = try? Data(contentsOf: prefs.appending(path: "Library.cfg")),
           let text = String(data: data, encoding: .isoLatin1),
           let start = text.range(of: "ProjectPath Value=\"")?.upperBound,
           let end = text[start...].firstIndex(of: "\"") {
            root = URL(fileURLWithPath: String(text[start..<end]))
        }
        return root.appending(path: "User Library/Remote Scripts")
    }

    /// ~/Library/Preferences/Ableton/Live x.y.z le plus récent.
    static var latestPreferencesFolder: URL? {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Preferences/Ableton")
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return folders
            .filter { $0.lastPathComponent.hasPrefix("Live ") }
            .max { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending }
    }

    static var isScriptInstalled: Bool {
        FileManager.default.fileExists(atPath: remoteScriptsFolder.appending(path: "NotchKiller/__init__.py").path)
    }

    /// Copie le script livré dans l'app vers la User Library. Live le lit au
    /// démarrage ou quand on le choisit comme surface de contrôle.
    @discardableResult
    static func installScript() -> Bool {
        guard let bundled = Bundle.main.url(forResource: "NotchKiller", withExtension: nil,
                                            subdirectory: "AbletonRemoteScript") else { return false }
        let target = remoteScriptsFolder.appending(path: "NotchKiller")
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: remoteScriptsFolder, withIntermediateDirectories: true)
            if manager.fileExists(atPath: target.path) { try manager.removeItem(at: target) }
            try manager.copyItem(at: bundled, to: target)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Démo

extension AbletonBridge {
    static var demoState: LiveState? {
        let json = """
        {"v":1,"playing":true,"tempo":124,"time":66.75,"length":256,"num":4,"den":4,
         "record":false,"session_record":false,"overdub":false,"metronome":true,"loop":true,
         "loop_start":64,"loop_length":16,"punch_in":false,"punch_out":false,"can_undo":true,"can_redo":false,
         "master":[0.78,0.74],
         "groups":[{"name":"Drums","color":16149507,"l":0.82,"r":0.8,"mute":false},
                   {"name":"Bass","color":1090798,"l":0.66,"r":0.66,"mute":false},
                   {"name":"Synths","color":10181046,"l":0.58,"r":0.61,"mute":false},
                   {"name":"FX","color":16761095,"l":0.2,"r":0.24,"mute":true}],
         "track":{"name":"Lead Pluck","color":10181046,"master":false,"can_arm":true,"arm":true,
                  "mute":false,"solo":false,"clip":"Pluck hook","l":0.61,"r":0.57},
         "cues":[{"name":"Intro","time":0},{"name":"Build","time":32},{"name":"Drop","time":64},
                 {"name":"Break","time":128},{"name":"Outro","time":224}],
         "scenes":[{"name":"Intro","color":0,"triggered":false},{"name":"Build","color":0,"triggered":false},
                   {"name":"Drop","color":0,"triggered":true},{"name":"Break","color":0,"triggered":false}],
         "grid":[
          {"name":"Kick","color":16149507,"clips":[{"name":"Kick 4x4","color":16149507,"state":0},{"name":"Kick 4x4","color":16149507,"state":0},{"name":"Kick drop","color":16149507,"state":2},null]},
          {"name":"Hats","color":16149507,"clips":[null,{"name":"Hats roll","color":16149507,"state":0},{"name":"Hats open","color":16149507,"state":2},{"name":"Hats soft","color":16149507,"state":0}]},
          {"name":"Bass","color":1090798,"clips":[null,{"name":"Sub rise","color":1090798,"state":0},{"name":"Rolling","color":1090798,"state":2},null]},
          {"name":"Lead Pluck","color":10181046,"clips":[{"name":"Pad intro","color":10181046,"state":0},null,{"name":"Pluck hook","color":10181046,"state":1},{"name":"Pluck soft","color":10181046,"state":0}]},
          {"name":"Vox","color":16761095,"clips":[null,null,{"name":"Vox chop","color":16761095,"state":3},null]}],
         "offset":[0,0],"size":[5,4]}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(LiveState.self, from: Data(json.utf8))
    }
}
