import Foundation

/// Ce que le bandeau fermé peut montrer. Plusieurs activités peuvent être
/// vraies en même temps : les éphémères passent devant, les permanentes
/// défilent l'une après l'autre.
enum BarActivity: String, Identifiable, Equatable, CaseIterable {
    case volume, brightness, notification, bluetooth, batteryAlert, claudeDone
    case timer, claude, music, calendar, idle

    var id: String { rawValue }

    var isTransient: Bool {
        switch self {
        case .volume, .brightness, .notification, .bluetooth, .batteryAlert, .claudeDone: true
        default: false
        }
    }
}

@MainActor
@Observable
final class BarActivities {
    static let shared = BarActivities()

    private(set) var transient: BarActivity?
    private(set) var index = 0
    /// Liste des activités permanentes, recalculée par la vue à chaque rendu.
    private(set) var persistent: [BarActivity] = [.idle]

    private var expiry: Task<Void, Never>?
    /// Survolée, une activité éphémère reste affichée ; elle repart à la sortie.
    private var isHeld = false
    private static let releaseDelay: TimeInterval = 3
    private var rotation: Task<Void, Never>?

    private init() {}

    var current: BarActivity {
        if let transient { return transient }
        guard !persistent.isEmpty else { return .idle }
        return persistent[min(index, persistent.count - 1)]
    }

    var showsIndicator: Bool { transient == nil && persistent.count > 1 }

    /// `real` ne contient que les activités en cours. Le repos est toujours
    /// ajouté en fin de liste : sans lui, une seule activité rendrait le
    /// balayage horizontal inopérant, ce qui donne l'impression d'un geste mort.
    func updatePersistent(_ real: [BarActivity]) {
        let next = real.filter { $0 != .idle } + [.idle]
        guard next != persistent else { return }
        persistent = next
        index = 0
        restartRotation(autoRotate: real.filter { $0 != .idle }.count >= 2)
    }

    func show(_ activity: BarActivity, for seconds: TimeInterval) {
        transient = activity
        scheduleExpiry(after: seconds)
    }

    /// Survol du tiroir : on suspend l'expiration, puis on laisse quelques
    /// secondes de lecture une fois la souris partie.
    func hold(_ held: Bool) {
        guard held != isHeld else { return }
        isHeld = held
        guard transient != nil else { return }
        if held {
            expiry?.cancel()
            expiry = nil
        } else {
            scheduleExpiry(after: Self.releaseDelay)
        }
    }

    private func scheduleExpiry(after seconds: TimeInterval) {
        expiry?.cancel()
        guard !isHeld else { expiry = nil; return }
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.transient = nil
        }
    }

    func dismissTransient() {
        expiry?.cancel()
        expiry = nil
        transient = nil
    }

    /// Balayage horizontal : on passe à l'activité suivante et le défilement
    /// automatique repart de zéro, pour ne pas voler la main à l'utilisateur.
    func advance(_ delta: Int) {
        guard persistent.count > 1 else { return }
        dismissTransient()
        index = (index + delta + persistent.count) % persistent.count
        restartRotation(autoRotate: false)
    }

    private func restartRotation(autoRotate: Bool) {
        rotation?.cancel()
        guard autoRotate, persistent.count > 1 else { return }
        rotation = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self, self.persistent.count > 1 else { return }
                self.index = (self.index + 1) % self.persistent.count
            }
        }
    }
}
