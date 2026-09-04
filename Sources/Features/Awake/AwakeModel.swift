import IOKit.pwr_mgt
import Foundation

/// Empêche la mise en veille — l'équivalent de caffeinate, sans processus tiers.
@MainActor
@Observable
final class AwakeModel {
    static let shared = AwakeModel()

    private(set) var isActive = false
    private(set) var since: Date?

    private var assertionID: IOPMAssertionID = 0

    private init() {}

    var durationLabel: String {
        guard let since else { return "—" }
        let total = Int(Date().timeIntervalSince(since))
        return total >= 3600
            ? "\(total / 3600) h \(String(format: "%02d", (total % 3600) / 60))"
            : "\(total / 60) min"
    }

    func toggle() {
        isActive ? release() : acquire()
    }

    private func acquire() {
        var identifier: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "NotchKiller — veille suspendue" as CFString,
            &identifier
        )
        guard result == kIOReturnSuccess else { return }
        assertionID = identifier
        isActive = true
        since = Date()
    }

    private func release() {
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
        since = nil
    }
}
