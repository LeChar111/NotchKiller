import Foundation

// NotchKillerFanHelper — lancé en root par le LaunchDaemon io.github.lechar111.notchkiller.fans.
//
// Écrire dans le SMC (mode et consigne des ventilateurs) exige root ; NotchKiller, lui,
// tourne en utilisateur. Cet assistant écoute sur un socket Unix réservé à root et à
// l'utilisateur qui l'a installé (--uid), garde la consigne de chaque ventilateur
// (fans.json, rejouée au démarrage) et l'applique toutes les 2 s : vitesse constante
// ou proportionnelle à une famille de sondes. En mode automatique il ne touche à rien.
// À l'arrêt (SIGTERM, désinstallation) il rend tous les ventilateurs au système.
//
// Compilé avec Sources/Features/Fans/SMC.swift (client SMC et protocole partagés).

setvbuf(stdout, nil, _IOLBF, 0)

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write(Data("\(stamp) \(message)\n".utf8))
}

var allowedUID: uid_t = 0
if let flag = CommandLine.arguments.firstIndex(of: "--uid"), flag + 1 < CommandLine.arguments.count,
   let uid = UInt32(CommandLine.arguments[flag + 1]) {
    allowedUID = uid
}

guard getuid() == 0 else {
    log("doit tourner en root")
    exit(77)
}
guard let smc = SMC() else {
    log("AppleSMC inaccessible")
    exit(71)
}

// MARK: Pilotage

final class Controller {
    let smc: SMC
    let count: Int
    var modes: [FanMode]
    /// Consigne écrite au dernier passage, pour adoucir la descente en mode sonde.
    var lastTarget: [Double?]
    var forced: [Bool]
    let hasTestMode: Bool
    let hasModeKey: Bool
    var groupKeys: [ThermalGroup: [String]] = [:]
    /// Refus déjà journalisé : thermalmonitord peut tenir plusieurs passages.
    var refusalLogged: Set<Int> = []

    init(smc: SMC) {
        self.smc = smc
        count = smc.fanCount
        modes = Array(repeating: .auto, count: count)
        lastTarget = Array(repeating: nil, count: count)
        forced = Array(repeating: false, count: count)
        hasTestMode = smc.info("Ftst") != nil
        hasModeKey = smc.info("F0Md") != nil
        for key in smc.temperatureKeys() {
            groupKeys[ThermalGroup(key: key), default: []].append(key)
        }
        load()
    }

    func load() {
        guard let data = FileManager.default.contents(atPath: FanHelper.statePath),
              let saved = try? JSONDecoder().decode([FanMode].self, from: data) else { return }
        for (index, mode) in saved.enumerated() where index < count { modes[index] = mode }
    }

    func save() {
        try? FileManager.default.createDirectory(atPath: FanHelper.supportDir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(modes) {
            FileManager.default.createFile(atPath: FanHelper.statePath, contents: data,
                                           attributes: [.posixPermissions: 0o644])
        }
    }

    func set(_ mode: FanMode, fan: Int?) {
        let targets = fan.map { [$0] } ?? Array(0..<count)
        for index in targets where index >= 0 && index < count {
            modes[index] = mode
            lastTarget[index] = nil
        }
        save()
    }

    /// Passe le ventilateur en consigne manuelle. Sur Apple Silicon, thermalmonitord
    /// garde la main tant que `Ftst` (mode test) n'est pas levé : l'écriture de `FxMd`
    /// échoue quelques instants. On essaie une seconde au plus, le passage suivant
    /// (2 s plus tard) reprend : le socket ne reste jamais bloqué longtemps.
    private func force(_ index: Int) -> Bool {
        if hasModeKey {
            if (smc.value("F\(index)Md") ?? 0) >= 1 { return true }
            if hasTestMode, (smc.value("Ftst") ?? 0) < 1 { smc.write("Ftst", 1) }
            for _ in 0..<4 {
                if smc.write("F\(index)Md", 1), (smc.value("F\(index)Md") ?? 0) >= 1 {
                    refusalLogged.remove(index)
                    return true
                }
                usleep(250_000)
            }
            if refusalLogged.insert(index).inserted { log("ventilateur \(index) : passage en manuel refusé, nouvel essai à chaque passage") }
            return false
        }
        // Mac Intel anciens : masque de bits « FS! ».
        guard let mask = smc.value("FS! ") else { return false }
        return smc.write("FS! ", Double(UInt16(mask) | UInt16(1 << index)))
    }

    private func release(_ index: Int) {
        if hasModeKey {
            smc.write("F\(index)Md", 0)
        } else if let mask = smc.value("FS! ") {
            smc.write("FS! ", Double(UInt16(mask) & ~UInt16(1 << index)))
        }
        forced[index] = false
        lastTarget[index] = nil
        if hasTestMode, !forced.contains(true), (smc.value("Ftst") ?? 0) >= 1 {
            smc.write("Ftst", 0)
        }
    }

    func releaseAll() {
        for index in 0..<count { release(index) }
    }

    func hottest(_ group: ThermalGroup) -> Double? {
        smc.temperatures(groupKeys[group] ?? []).map(\.celsius).max()
    }

    func tick() {
        for index in 0..<count {
            guard let fan = smc.fan(index) else { continue }
            let desired: Double?
            switch modes[index] {
            case .auto:
                desired = nil
            case .constant(let rpm):
                desired = rpm
            case .sensor(let group, let low, let high):
                if let temperature = hottest(group) {
                    let ratio = high > low ? (temperature - low) / (high - low) : (temperature >= high ? 1 : 0)
                    var rpm = fan.minimum + max(0, min(1, ratio)) * (fan.maximum - fan.minimum)
                    // Montée immédiate, descente par paliers : pas de pompage à chaque pic.
                    if let previous = lastTarget[index], rpm < previous { rpm = max(rpm, previous - 150) }
                    desired = rpm
                } else {
                    desired = nil
                }
            }

            guard let rpm = desired else {
                if forced[index] || (lastTarget[index] != nil) { release(index) }
                continue
            }
            let target = max(fan.minimum, min(fan.maximum, rpm)).rounded()
            if !fan.forced || !forced[index] {
                forced[index] = force(index)
                guard forced[index] else { continue }
            }
            if fan.target.map({ abs($0 - target) >= 1 }) ?? true {
                smc.write("F\(index)Tg", target)
            }
            lastTarget[index] = target
        }
    }
}

let controller = Controller(smc: smc)
log("démarrage — \(controller.count) ventilateur(s), uid autorisé \(allowedUID)")

// MARK: Socket

func respond(_ fd: Int32) {
    defer { close(fd) }

    var credentials = xucred()
    var length = socklen_t(MemoryLayout<xucred>.size)
    guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERCRED, &credentials, &length) == 0,
          credentials.cr_uid == 0 || credentials.cr_uid == allowedUID else { return }

    var timeout = timeval(tv_sec: 2, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while data.count < 65_536 {
        let read = Darwin.read(fd, &buffer, buffer.count)
        guard read > 0 else { break }
        data.append(buffer, count: read)
        if buffer[read - 1] == UInt8(ascii: "\n") { break }
    }

    var response = FanResponse(ok: true, version: FanHelper.version, modes: [], error: nil)
    if let request = try? JSONDecoder().decode(FanRequest.self, from: data) {
        switch request.command {
        case .status:
            break
        case .set:
            if let mode = request.mode { controller.set(mode, fan: request.fan) }
            else { response.ok = false; response.error = "consigne manquante" }
        case .reset:
            controller.set(.auto, fan: nil)
        }
        // Appliquée juste après la réponse : l'app n'attend pas le SMC.
        if request.command != .status { DispatchQueue.main.async { controller.tick() } }
    } else {
        response.ok = false
        response.error = "requête illisible"
    }
    response.modes = controller.modes

    if var encoded = try? JSONEncoder().encode(response) {
        encoded.append(UInt8(ascii: "\n"))
        _ = encoded.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    }
}

unlink(FanHelper.socketPath)
let listener = socket(AF_UNIX, SOCK_STREAM, 0)
guard listener >= 0 else { log("socket impossible"); exit(71) }
var address = sockaddr_un()
address.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutableBytes(of: &address.sun_path) { buffer in
    let path = Array(FanHelper.socketPath.utf8.prefix(buffer.count - 1))
    for (index, byte) in path.enumerated() { buffer[index] = byte }
}
let bound = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard bound == 0, listen(listener, 8) == 0 else { log("écoute impossible sur \(FanHelper.socketPath)"); exit(71) }
// Ouvert en écriture à tous : c'est LOCAL_PEERCRED qui filtre, à chaque connexion.
chmod(FanHelper.socketPath, 0o666)

let acceptSource = DispatchSource.makeReadSource(fileDescriptor: listener, queue: .main)
acceptSource.setEventHandler {
    let client = accept(listener, nil, nil)
    if client >= 0 { respond(client) }
}
acceptSource.resume()

let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now(), repeating: .seconds(2), leeway: .milliseconds(200))
timer.setEventHandler { controller.tick() }
timer.resume()

func shutdown(_ signal: Int32) -> DispatchSourceSignal {
    Darwin.signal(signal, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signal, queue: .main)
    source.setEventHandler {
        controller.releaseAll()
        unlink(FanHelper.socketPath)
        log("arrêt — ventilateurs rendus au système")
        exit(0)
    }
    source.resume()
    return source
}
let signals = [shutdown(SIGTERM), shutdown(SIGINT)]

dispatchMain()
