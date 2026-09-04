import Foundation
import IOKit

@MainActor
@Observable
final class BrightnessManager {
    static let shared = BrightnessManager()

    var brightness: Float = 0.5
    var lastChangeAt: Date = .distantPast

    private var poller: Timer?
    var isVisible: Bool { Date().timeIntervalSince(lastChangeAt) < 1.5 }

    private init() {
        startPolling()
        fetchCurrent()
    }

    /// Aucun événement système n'annonce un changement de luminosité : il faut
    /// interroger l'écran pour repérer un appui sur les touches dédiées.
    private func startPolling() {
        poller = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let value = self.getDisplayBrightness() else { return }
                if abs(value - self.brightness) > 0.005 {
                    self.brightness = value
                    self.lastChangeAt = Date()
                }
            }
        }
        poller?.tolerance = 0.1
    }

    func increase() {
        setBrightness(min(1, brightness + 1.0 / 16.0))
    }

    func decrease() {
        setBrightness(max(0, brightness - 1.0 / 16.0))
    }

    func setBrightness(_ value: Float) {
        let clamped = max(0, min(1, value))
        setDisplayBrightness(clamped)
        brightness = clamped
        lastChangeAt = Date()
    }

    func fetchCurrent() {
        brightness = getDisplayBrightness() ?? 0.5
    }

    // MARK: - IOKit Display Brightness

    private nonisolated func getDisplayBrightness() -> Float? {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        )
        guard result == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            var brightness: Float = 0
            let err = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &brightness)
            IOObjectRelease(service)
            if err == kIOReturnSuccess {
                return brightness
            }
            service = IOIteratorNext(iterator)
        }
        return nil
    }

    private nonisolated func setDisplayBrightness(_ value: Float) {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        )
        guard result == kIOReturnSuccess else { return }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, value)
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }
}
