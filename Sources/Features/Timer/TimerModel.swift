import AppKit

@MainActor
@Observable
final class NotchTimer {
    static let shared = NotchTimer()

    enum Phase: Equatable { case idle, work, rest }

    private(set) var phase: Phase = .idle
    private(set) var isRunning = false
    private(set) var remaining: TimeInterval = 0
    private(set) var total: TimeInterval = 0
    private(set) var completedRounds = 0
    private(set) var finishedAt: Date?

    /// Pomodoro classique — la pause suit automatiquement le cycle de travail.
    static let workMinutes = 25
    static let restMinutes = 5

    private var ticker: Task<Void, Never>?

    private init() {}

    var isActive: Bool { phase != .idle }

    var label: String {
        switch phase {
        case .idle: "Minuteur"
        case .work: completedRounds > 0 ? "Pomodoro \(completedRounds + 1)" : "Pomodoro"
        case .rest: "Pause"
        }
    }

    var progress: Double {
        total > 0 ? 1 - (remaining / total) : 0
    }

    var display: String {
        let seconds = Int(max(0, remaining.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: Commandes

    func start(minutes: Int, phase: Phase = .work) {
        self.phase = phase
        total = TimeInterval(minutes * 60)
        remaining = total
        finishedAt = nil
        resume()
    }

    func startPomodoro() {
        completedRounds = 0
        start(minutes: Self.workMinutes, phase: .work)
    }

    func toggle() {
        isRunning ? pause() : resume()
    }

    func pause() {
        isRunning = false
        ticker?.cancel()
        ticker = nil
    }

    func resume() {
        guard phase != .idle, remaining > 0 else { return }
        isRunning = true
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.isRunning else { return }
                self.tick(0.5)
            }
        }
    }

    func reset() {
        pause()
        phase = .idle
        remaining = 0
        total = 0
        completedRounds = 0
        finishedAt = nil
    }

    private func tick(_ delta: TimeInterval) {
        remaining = max(0, remaining - delta)
        guard remaining == 0 else { return }
        complete()
    }

    /// Fin de cycle : on enchaîne travail → pause → travail sans rien demander,
    /// c'est tout l'intérêt d'un pomodoro.
    private func complete() {
        pause()
        finishedAt = Date()
        NSSound(named: "Glass")?.play()

        switch phase {
        case .work:
            completedRounds += 1
            start(minutes: Self.restMinutes, phase: .rest)
        case .rest:
            start(minutes: Self.workMinutes, phase: .work)
        case .idle:
            break
        }
    }
}
