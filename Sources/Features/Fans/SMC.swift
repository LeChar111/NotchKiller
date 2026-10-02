import Foundation
import IOKit

// Partagé entre l'app (lecture des sondes et des ventilateurs, sans privilège) et
// NotchKillerFanHelper (Tools/fan-helper), l'assistant root qui seul peut écrire
// dans le SMC. Ce fichier ne dépend donc que de Foundation et d'IOKit.

// MARK: - Client SMC

/// Accès au System Management Controller par `AppleSMC`. La lecture est ouverte à
/// tous ; l'écriture (mode et consigne des ventilateurs) exige root.
final class SMC {
    /// Structure d'échange du pilote (`SMCKeyData_t`, 80 octets). `padding` aligne
    /// `result` sur l'offset 40 du C : Swift range le champ suivant `keyInfo` à la
    /// fin de sa taille (37) et non de son pas (40).
    private struct Param {
        struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0; var release: UInt16 = 0 }
        struct PLimit { var version: UInt16 = 0, length: UInt16 = 0; var cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
        struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0; var attributes: UInt8 = 0 }

        var key: UInt32 = 0
        var version = Version()
        var pLimit = PLimit()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0, status: UInt8 = 0, data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
            = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
               0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private enum Selector: UInt8 {
        case read = 5, write = 6, keyAtIndex = 8, keyInfo = 9
    }

    struct KeyInfo {
        let size: Int
        let type: String
    }

    private var connection: io_connect_t = 0
    private var infoCache: [UInt32: KeyInfo] = [:]

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    deinit {
        IOServiceClose(connection)
    }

    static func code(_ key: String) -> UInt32 {
        key.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    static func name(_ code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(code >> UInt32($0) & 0xff) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func call(_ input: inout Param) -> Param? {
        var output = Param()
        var size = MemoryLayout<Param>.stride
        let status = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<Param>.stride, &output, &size)
        guard status == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    func info(_ key: String) -> KeyInfo? {
        let code = Self.code(key)
        if let cached = infoCache[code] { return cached }
        var input = Param()
        input.key = code
        input.data8 = Selector.keyInfo.rawValue
        guard let output = call(&input) else { return nil }
        let info = KeyInfo(size: Int(output.keyInfo.dataSize), type: Self.name(output.keyInfo.dataType))
        infoCache[code] = info
        return info
    }

    func bytes(_ key: String) -> (KeyInfo, [UInt8])? {
        guard let info = info(key), info.size > 0, info.size <= 32 else { return nil }
        var input = Param()
        input.key = Self.code(key)
        input.keyInfo.dataSize = UInt32(info.size)
        input.data8 = Selector.read.rawValue
        guard let output = call(&input) else { return nil }
        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(info.size)) }
        return (info, bytes)
    }

    /// Valeur numérique d'une clé, quel que soit son codage (`flt ` sur Apple
    /// Silicon, `fpe2`/`sp78` sur les Mac Intel, entiers non signés).
    func value(_ key: String) -> Double? {
        guard let (info, bytes) = bytes(key) else { return nil }
        return Self.decode(info.type, bytes)
    }

    static func decode(_ type: String, _ b: [UInt8]) -> Double? {
        switch type {
        case "flt ":
            guard b.count == 4 else { return nil }
            let value = Double(Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24))
            return value.isFinite ? value : nil
        case "fpe2":
            guard b.count == 2 else { return nil }
            return Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4
        case "sp78":
            guard b.count == 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256
        case "ui8 ":
            return b.first.map(Double.init)
        case "ui16":
            guard b.count == 2 else { return nil }
            return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        case "ui32":
            guard b.count == 4 else { return nil }
            return Double(b.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        default:
            return nil
        }
    }

    /// Écrit une valeur dans le codage de la clé. Réservé à root.
    @discardableResult
    func write(_ key: String, _ value: Double) -> Bool {
        guard let info = info(key) else { return false }
        let encoded: [UInt8]
        switch info.type {
        case "flt ":
            let bits = Float(value).bitPattern
            encoded = [UInt8(bits & 0xff), UInt8(bits >> 8 & 0xff), UInt8(bits >> 16 & 0xff), UInt8(bits >> 24)]
        case "fpe2":
            let raw = UInt16(max(0, min(16_383, value * 4)))
            encoded = [UInt8(raw >> 8), UInt8(raw & 0xff)]
        case "ui8 ":
            encoded = [UInt8(max(0, min(255, value)))]
        case "ui16":
            let raw = UInt16(max(0, min(65_535, value)))
            encoded = [UInt8(raw >> 8), UInt8(raw & 0xff)]
        default:
            return false
        }
        guard encoded.count == info.size else { return false }

        var input = Param()
        input.key = Self.code(key)
        input.keyInfo.dataSize = UInt32(info.size)
        input.data8 = Selector.write.rawValue
        withUnsafeMutableBytes(of: &input.bytes) { buffer in
            for (index, byte) in encoded.enumerated() { buffer[index] = byte }
        }
        return call(&input) != nil
    }

    /// Toutes les clés du contrôleur (#KEY en donne le nombre).
    func allKeys() -> [String] {
        guard let count = value("#KEY"), count > 0 else { return [] }
        var keys: [String] = []
        keys.reserveCapacity(Int(count))
        for index in 0..<UInt32(count) {
            var input = Param()
            input.data8 = Selector.keyAtIndex.rawValue
            input.data32 = index
            if let output = call(&input) { keys.append(Self.name(output.key)) }
        }
        return keys
    }

    // MARK: Ventilateurs

    var fanCount: Int { Int(value("FNum") ?? 0) }

    func fan(_ index: Int) -> FanReading? {
        guard let actual = value("F\(index)Ac") else { return nil }
        let minimum = value("F\(index)Mn") ?? 0
        let maximum = value("F\(index)Mx") ?? max(actual, 1)
        return FanReading(
            index: index,
            actual: actual,
            minimum: minimum,
            maximum: max(maximum, minimum + 1),
            target: value("F\(index)Tg"),
            forced: (value("F\(index)Md") ?? 0) >= 1
        )
    }

    func fans() -> [FanReading] {
        (0..<fanCount).compactMap(fan)
    }

    // MARK: Sondes

    /// Clés de température lisibles, repérées une fois pour toutes : sur un M4 Pro,
    /// plus de 300 sur les ~3 300 clés du contrôleur.
    func temperatureKeys() -> [String] {
        allKeys().filter { key in
            guard key.first == "T", let info = info(key), info.type == "flt " || info.type == "sp78" else { return false }
            return value(key).map(ThermalSensor.isPlausible) ?? false
        }
    }

    func temperatures(_ keys: [String]) -> [ThermalSensor] {
        keys.compactMap { key in
            guard let value = value(key), ThermalSensor.isPlausible(value) else { return nil }
            return ThermalSensor(key: key, celsius: value)
        }
    }
}

// MARK: - Relevés

struct FanReading: Equatable, Sendable {
    let index: Int
    let actual: Double
    let minimum: Double
    let maximum: Double
    let target: Double?
    /// Consigne imposée (mode manuel) plutôt que laissée au système.
    let forced: Bool

    var ratio: Double { max(0, min(1, actual / maximum)) }

    static func name(_ index: Int, of count: Int) -> String {
        if count == 1 { return "Ventilateur" }
        if count == 2 { return index == 0 ? "Gauche" : "Droit" }
        return "Ventilateur \(index + 1)"
    }
}

struct ThermalSensor: Equatable, Sendable, Identifiable {
    let key: String
    let celsius: Double

    var id: String { key }
    var group: ThermalGroup { ThermalGroup(key: key) }

    /// Les clés à 0 °C (sondes absentes) ou à 9 °C (canaux non câblés) existent
    /// sans rien mesurer.
    static func isPlausible(_ value: Double) -> Bool { value > 12 && value < 130 }
}

/// Famille d'une sonde, déduite du préfixe de sa clé. Apple ne publie pas la carte
/// des capteurs : on s'en tient aux familles bien établies, sans prêter à une clé
/// un cœur précis qu'on ne peut pas vérifier.
enum ThermalGroup: String, CaseIterable, Codable, Sendable, Identifiable {
    case cpuPerformance, cpuEfficiency, gpu, ssd, battery, wifi, airflow, palmRest, other

    var id: String { rawValue }

    init(key: String) {
        let chars = Array(key)
        let second = chars.count > 1 ? chars[1] : " "
        let third = chars.count > 2 ? chars[2] : " "
        switch (second, third) {
        case ("p", _):                                   self = .cpuPerformance   // Apple Silicon
        case ("C", let c) where c.isNumber:              self = .cpuPerformance   // Intel : TC0P, TC1C…
        case ("e", _):                                   self = .cpuEfficiency    // M3 et suivants
        case ("g", _):                                   self = .gpu
        case ("G", let c) where c.isNumber:              self = .gpu
        case ("H", _):                                   self = .ssd
        case ("B", _) where key.hasSuffix("T"):          self = .battery
        case ("W", _):                                   self = .wifi
        case ("a", "L"), ("a", "R"):                     self = .airflow
        case ("A", let c) where c.isNumber:              self = .airflow
        case ("s", let c) where c.isNumber && key.hasSuffix("P"): self = .palmRest
        default:                                         self = .other
        }
    }

    var title: String {
        switch self {
        case .cpuPerformance: "CPU"
        case .cpuEfficiency:  "CPU · efficacité"
        case .gpu:            "GPU"
        case .ssd:            "SSD"
        case .battery:        "Batterie"
        case .wifi:           "Wi-Fi"
        case .airflow:        "Flux d'air"
        case .palmRest:       "Repose-poignets"
        case .other:          "Autres sondes"
        }
    }

    var symbol: String {
        switch self {
        case .cpuPerformance, .cpuEfficiency: "cpu"
        case .gpu:      "square.stack.3d.up"
        case .ssd:      "internaldrive"
        case .battery:  "battery.75percent"
        case .wifi:     "wifi"
        case .airflow:  "wind"
        case .palmRest: "hand.raised"
        case .other:    "thermometer.medium"
        }
    }
}

// MARK: - Protocole app ↔ assistant

/// Consigne d'un ventilateur, appliquée en continu par l'assistant root.
enum FanMode: Codable, Equatable, Sendable {
    case auto
    /// Vitesse fixe, en tr/min.
    case constant(rpm: Double)
    /// Vitesse proportionnelle à la sonde la plus chaude du groupe : minimum en
    /// dessous de `low`, maximum au-delà de `high`.
    case sensor(group: ThermalGroup, low: Double, high: Double)
}

struct FanRequest: Codable, Sendable {
    enum Command: String, Codable, Sendable { case status, set, reset }
    var command: Command
    /// Ventilateur visé ; `nil` : tous.
    var fan: Int?
    var mode: FanMode?
}

struct FanResponse: Codable, Sendable {
    var ok: Bool
    var version: Int
    var modes: [FanMode]
    var error: String?
}

enum FanHelper {
    /// À incrémenter à chaque changement de l'assistant : l'app propose alors de le réinstaller.
    static let version = 1
    static let label = "io.github.lechar111.notchkiller.fans"
    static let socketPath = "/var/run/io.github.lechar111.notchkiller.fans.sock"
    static let supportDir = "/Library/Application Support/NotchKiller"
    static let installedPath = supportDir + "/NotchKillerFanHelper"
    static let statePath = supportDir + "/fans.json"
    static let plistPath = "/Library/LaunchDaemons/\(label).plist"
    static let logPath = "/Library/Logs/NotchKiller/fans.log"
}
