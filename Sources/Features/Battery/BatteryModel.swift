import Foundation
import IOKit
import IOKit.ps

@MainActor
@Observable
final class BatteryModel {
    static let shared = BatteryModel()

    var level: Float = 0
    var maxCapacity: Float = 100
    var isPluggedIn: Bool = false
    var isCharging: Bool = false
    var isLowPowerMode: Bool = false
    var timeToFullCharge: Int = 0
    var timeToEmpty: Int = 0
    var statusText: String = ""

    /// Relevés IORegistry (AppleSmartBattery) — absents sur une machine sans batterie.
    var cycleCount: Int = 0
    var healthRatio: Double = 0

    enum PowerEvent: Equatable { case pluggedIn, unplugged, low, full }
    /// Dernier événement d'alimentation, pour la bannière de l'encoche.
    private(set) var lastEvent: (kind: PowerEvent, at: Date)?
    private var previousPluggedIn: Bool?
    private var lowAnnounced = false

    private var batterySource: CFRunLoopSource?
    private var pollTimer: Timer?

    private init() {
        refresh()
        startMonitoring()
        setupLowPowerModeObserver()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    var percentString: String {
        "\(Int(level))%"
    }

    var normalizedLevel: Double {
        maxCapacity > 0 ? Double(level / maxCapacity) : 0
    }

    var hasBattery: Bool { maxCapacity > 0 && statusText != "No battery" }

    var healthLabel: String {
        guard healthRatio > 0 else { return "—" }
        if healthRatio >= 0.80 { return "Normale" }
        if healthRatio >= 0.65 { return "Correcte" }
        return "À remplacer"
    }

    /// Autonomie ou temps de charge restant, formaté « 4 h 12 ».
    var remainingLabel: String {
        let minutes = isCharging ? timeToFullCharge : timeToEmpty
        guard minutes > 0 else { return isPluggedIn ? "Secteur" : "Estimation…" }
        return minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min"
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let model = Unmanaged<BatteryModel>.fromOpaque(ctx).takeUnretainedValue()
            Task { @MainActor in
                model.refresh()
            }
        }, context)?.takeRetainedValue() else { return }

        batterySource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
    }

    private func setupLowPowerModeObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    // MARK: - Refresh

    func refresh() {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
            let source = sources.first,
            let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
        else {
            statusText = "No battery"
            return
        }

        let currentCap = desc[kIOPSCurrentCapacityKey] as? Float ?? 0
        let maxCap = desc[kIOPSMaxCapacityKey] as? Float ?? 100
        let charging = desc["Is Charging"] as? Bool ?? false
        let powerSource = desc[kIOPSPowerSourceStateKey] as? String ?? ""
        let pluggedIn = powerSource == kIOPSACPowerValue
        let ttfc = desc[kIOPSTimeToFullChargeKey] as? Int ?? 0
        let tte = desc[kIOPSTimeToEmptyKey] as? Int ?? 0

        level = currentCap
        maxCapacity = maxCap
        isCharging = charging
        isPluggedIn = pluggedIn
        timeToFullCharge = ttfc
        timeToEmpty = tte
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        refreshSmartBattery()
        detectEvents(pluggedIn: pluggedIn, level: currentCap, maxLevel: maxCap, charging: charging)

        if charging {
            statusText = ttfc > 0 ? "Charging - \(ttfc)min" : "Charging"
        } else if pluggedIn {
            statusText = currentCap >= maxCap ? "Full" : "Plugged in"
        } else {
            statusText = "On battery"
        }
    }

    func clearEvent() { lastEvent = nil }

    /// Le premier relevé sert de référence : brancher l'app n'est pas un
    /// événement de branchement.
    private func detectEvents(pluggedIn: Bool, level: Float, maxLevel: Float, charging: Bool) {
        defer { previousPluggedIn = pluggedIn }
        guard let previous = previousPluggedIn else { return }

        if pluggedIn != previous {
            lastEvent = (pluggedIn ? .pluggedIn : .unplugged, Date())
            lowAnnounced = false
            return
        }

        let percent = maxLevel > 0 ? level / maxLevel * 100 : 100
        if !pluggedIn, percent <= 20, !lowAnnounced {
            lastEvent = (.low, Date())
            lowAnnounced = true
        } else if percent > 25 {
            lowAnnounced = false
        }

        if charging == false, pluggedIn, percent >= 100, lastEvent?.kind != .full {
            lastEvent = (.full, Date())
        }
    }

    /// Cycles et santé : IOPS ne les expose pas, il faut interroger AppleSmartBattery.
    private func refreshSmartBattery() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        func number(_ key: String) -> Int? {
            guard let value = IORegistryEntryCreateCFProperty(
                service, key as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? NSNumber else { return nil }
            return value.intValue
        }

        if let cycles = number("CycleCount") { cycleCount = cycles }

        let nominal = number("NominalChargeCapacity") ?? number("AppleRawMaxCapacity")
        if let nominal, let design = number("DesignCapacity"), design > 0 {
            healthRatio = min(1, Double(nominal) / Double(design))
        }
    }
}
