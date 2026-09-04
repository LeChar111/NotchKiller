import AppKit

struct BluetoothDevice: Identifiable, Equatable {
    var id: String { address }
    let address: String
    let name: String
    let kind: String
    let isConnected: Bool
    let battery: Int?

    var symbol: String {
        let k = kind.lowercased()
        if k.contains("mouse") { return "magicmouse" }
        if k.contains("keyboard") { return "keyboard" }
        if k.contains("headphone") || k.contains("headset") { return "headphones" }
        if k.contains("speaker") { return "hifispeaker" }
        if k.contains("watch") { return "applewatch" }
        return "dot.radiowaves.right"
    }
}

@MainActor
@Observable
final class BluetoothModel {
    static let shared = BluetoothModel()

    private(set) var devices: [BluetoothDevice] = []
    /// Dernier branchement ou débranchement, pour la bannière de l'encoche.
    private(set) var lastChange: (device: BluetoothDevice, connected: Bool, at: Date)?

    private var timer: Timer?
    private var knownConnected: Set<String> = []
    private var hasBaseline = false

    private init() {}

    var connected: [BluetoothDevice] { devices.filter(\.isConnected) }

    func start() {
        guard timer == nil else { return }
        refresh()
        // system_profiler est coûteux : 15 s suffisent pour un événement
        // de connexion, qui n'est pas une donnée temps réel.
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        timer?.tolerance = 3
    }

    func refresh() {
        Task.detached(priority: .utility) {
            let found = Self.snapshot()
            await MainActor.run { self.apply(found) }
        }
    }

    private func apply(_ found: [BluetoothDevice]) {
        devices = found
        let nowConnected = Set(found.filter(\.isConnected).map(\.address))

        // Le premier relevé sert de référence : on ne signale pas comme
        // « nouveau » ce qui était déjà branché au lancement.
        guard hasBaseline else {
            knownConnected = nowConnected
            hasBaseline = true
            return
        }

        if let arrived = nowConnected.subtracting(knownConnected).first,
           let device = found.first(where: { $0.address == arrived }) {
            lastChange = (device, true, Date())
        } else if let left = knownConnected.subtracting(nowConnected).first,
                  let device = found.first(where: { $0.address == left }) {
            lastChange = (device, false, Date())
        }
        knownConnected = nowConnected
    }

    func clearChange() { lastChange = nil }

    private nonisolated static func snapshot() -> [BluetoothDevice] {
        guard let profiler = Shell.locate("system_profiler"),
              let json = Shell.run(profiler, ["SPBluetoothDataType", "-json"], timeout: 12),
              let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let section = (root["SPBluetoothDataType"] as? [[String: Any]])?.first
        else { return [] }

        var result: [BluetoothDevice] = []

        for (key, connected) in [("device_connected", true), ("device_not_connected", false)] {
            guard let entries = section[key] as? [[String: Any]] else { continue }
            for entry in entries {
                for (name, raw) in entry {
                    guard let info = raw as? [String: Any] else { continue }
                    let address = info["device_address"] as? String ?? name
                    let battery = info.first { $0.key.lowercased().contains("battery") }
                        .flatMap { Self.percent(from: $0.value) }
                    result.append(BluetoothDevice(
                        address: address,
                        name: name,
                        kind: info["device_minorType"] as? String ?? "",
                        isConnected: connected,
                        battery: battery
                    ))
                }
            }
        }

        return result.sorted { lhs, rhs in
            if lhs.isConnected != rhs.isConnected { return lhs.isConnected }
            return lhs.name < rhs.name
        }
    }

    private nonisolated static func percent(from value: Any) -> Int? {
        if let number = value as? Int { return number }
        if let text = value as? String {
            return Int(text.filter(\.isNumber))
        }
        return nil
    }
}
