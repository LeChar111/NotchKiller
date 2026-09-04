import Foundation
import IOKit.ps
import Darwin.Mach
import Darwin

@MainActor
@Observable
final class SystemStatsModel {
    var cpuUsage: String = "--"
    var memoryUsage: String = "--"
    var battery: String = "N/A"
    var downloadSpeed: String = "--"
    var uploadSpeed: String = "--"
    var diskUsage: String = "--"
    var clock: String = "--:--"
    var uptime: String = "--"
    var networkName: String = "--"

    /// Valeurs numériques 0…1 — les jauges et les courbes ne reparsent plus les chaînes.
    var cpuRatio: Double = 0
    var memoryRatio: Double = 0
    var diskRatio: Double = 0
    var batteryRatio: Double = 0
    var downloadBytes: Double = 0
    var uploadBytes: Double = 0

    /// 9 derniers relevés (≈ 90 s à la cadence d'1 s… en réalité 1 relevé/s, fenêtre glissante).
    var cpuHistory: [Double] = []
    var memoryHistory: [Double] = []
    private static let historyLength = 24

    private var timer: Timer?
    private var previousCPUTicks = [UInt32](repeating: 0, count: Int(CPU_STATE_MAX))
    private var hasPreviousCPU = false

    private var previousRxBytes: UInt64 = 0
    private var previousTxBytes: UInt64 = 0
    private var previousNetTimestamp: TimeInterval = Date().timeIntervalSince1970

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        timer?.tolerance = 0.2
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        let cpu = computeCPUUsage()
        cpuUsage = String(format: "%.0f%%", cpu)
        cpuRatio = max(0, min(1, cpu / 100))
        append(&cpuHistory, cpuRatio)

        let memory = computeMemoryUsage()
        memoryUsage = String(format: "%.0f%%", memory)
        memoryRatio = max(0, min(1, memory / 100))
        append(&memoryHistory, memoryRatio)

        battery = computeBatteryStatus() ?? "N/A"
        batteryRatio = Self.ratio(from: battery)

        let (download, upload) = computeNetworkSpeed()
        downloadSpeed = formatBytesPerSecond(download)
        uploadSpeed = formatBytesPerSecond(upload)
        downloadBytes = download
        uploadBytes = upload

        diskUsage = computeDiskUsage()
        diskRatio = Self.ratio(from: diskUsage)
        clock = Self.clockFormatter.string(from: Date())
        uptime = formatUptime(ProcessInfo.processInfo.systemUptime)
        networkName = currentNetworkInterface()
    }

    private func append(_ series: inout [Double], _ value: Double) {
        series.append(value)
        while series.count > Self.historyLength { series.removeFirst() }
    }

    /// « 80% ⚡ » ou « 61% » → 0…1. Retourne 0 quand la chaîne ne porte pas de pourcentage.
    private static func ratio(from text: String) -> Double {
        guard text.contains("%"),
              let value = Double(text.prefix(while: { $0.isNumber || $0 == "." })) else { return 0 }
        return max(0, min(1, value / 100))
    }

    // MARK: - CPU

    private nonisolated func computeCPUUsage() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var cpuLoadInfo = host_cpu_load_info()

        let result = withUnsafeMutablePointer(to: &cpuLoadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let ticks: [UInt32] = [
            cpuLoadInfo.cpu_ticks.0,
            cpuLoadInfo.cpu_ticks.1,
            cpuLoadInfo.cpu_ticks.2,
            cpuLoadInfo.cpu_ticks.3
        ]

        return MainActor.assumeIsolated {
            guard hasPreviousCPU else {
                previousCPUTicks = ticks
                hasPreviousCPU = true
                return 0.0
            }

            let diff = zip(ticks, previousCPUTicks).map { current, previous in
                current >= previous ? current - previous : current
            }

            previousCPUTicks = ticks

            let totalTicks = diff.reduce(0, +)
            guard totalTicks > 0 else { return 0.0 }

            let idleTicks = diff[Int(CPU_STATE_IDLE)]
            let usage = Double(totalTicks - idleTicks) / Double(totalTicks) * 100
            return max(0, min(100, usage))
        }
    }

    // MARK: - Memory

    private nonisolated func computeMemoryUsage() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let usedPages = stats.active_count + stats.inactive_count + stats.wire_count
        let usedBytes = Double(usedPages) * Double(vm_kernel_page_size)
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)

        guard totalBytes > 0 else { return 0 }
        return max(0, min(100, usedBytes / totalBytes * 100))
    }

    // MARK: - Battery

    private nonisolated func computeBatteryStatus() -> String? {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
            let source = list.first,
            let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
            let current = description[kIOPSCurrentCapacityKey as String] as? Int,
            let max = description[kIOPSMaxCapacityKey as String] as? Int,
            max > 0
        else {
            return nil
        }

        let percent = Int((Double(current) / Double(max)) * 100)
        let charging = (description[kIOPSIsChargingKey as String] as? Bool) ?? false
        let suffix = charging ? " ⚡" : ""
        return "\(percent)%\(suffix)"
    }

    // MARK: - Network

    private func computeNetworkSpeed() -> (Double, Double) {
        let now = Date().timeIntervalSince1970
        let elapsed = max(now - previousNetTimestamp, 1)
        let (rxBytes, txBytes) = networkBytes()

        defer {
            previousRxBytes = rxBytes
            previousTxBytes = txBytes
            previousNetTimestamp = now
        }

        guard previousRxBytes > 0 || previousTxBytes > 0 else {
            return (0, 0)
        }

        let down = Double(rxBytes.saturatingSubtract(previousRxBytes)) / elapsed
        let up = Double(txBytes.saturatingSubtract(previousTxBytes)) / elapsed
        return (down, up)
    }

    private nonisolated func networkBytes() -> (UInt64, UInt64) {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return (0, 0) }
        defer { freeifaddrs(addrs) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK

            if isUp && !isLoopback,
               let data = current.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                rx = rx.saturatingAdd(UInt64(data.pointee.ifi_ibytes))
                tx = tx.saturatingAdd(UInt64(data.pointee.ifi_obytes))
            }

            pointer = current.pointee.ifa_next
        }

        return (rx, tx)
    }

    // MARK: - Disk

    private nonisolated func computeDiskUsage() -> String {
        guard
            let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
            let total = (attributes[.systemSize] as? NSNumber)?.doubleValue,
            let free = (attributes[.systemFreeSize] as? NSNumber)?.doubleValue,
            total > 0
        else {
            return "--"
        }

        let used = total - free
        let usedPercent = (used / total) * 100
        let usedGB = used / 1_073_741_824
        return String(format: "%.0f%% (%.0f GB)", usedPercent, usedGB)
    }

    // MARK: - Formatting

    private nonisolated func formatBytesPerSecond(_ value: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var speed = max(0, value)
        var index = 0

        while speed >= 1024 && index < units.count - 1 {
            speed /= 1024
            index += 1
        }

        if index == 0 {
            return String(format: "%.0f %@", speed, units[index])
        }
        return String(format: "%.1f %@", speed, units[index])
    }

    private nonisolated func formatUptime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60

        if days > 0 {
            return "\(days)j \(hours)h"
        }
        return "\(hours)h \(minutes)m"
    }

    private nonisolated func currentNetworkInterface() -> String {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else {
            return "Aucun reseau"
        }
        defer { freeifaddrs(addrs) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK

            if isUp && !isLoopback,
               let nameCString = current.pointee.ifa_name {
                let name = String(cString: nameCString)
                if !name.isEmpty {
                    return name
                }
            }

            pointer = current.pointee.ifa_next
        }

        return "Aucun reseau"
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

// MARK: - UInt64 Helpers

extension UInt64 {
    func saturatingAdd(_ other: UInt64) -> UInt64 {
        let (result, overflow) = addingReportingOverflow(other)
        return overflow ? UInt64.max : result
    }

    func saturatingSubtract(_ other: UInt64) -> UInt64 {
        let (result, overflow) = subtractingReportingOverflow(other)
        return overflow ? 0 : result
    }
}
