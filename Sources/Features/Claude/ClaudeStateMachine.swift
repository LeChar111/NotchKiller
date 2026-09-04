import Foundation

@MainActor
@Observable
final class ClaudeStateMachine {
    static let shared = ClaudeStateMachine()

    let sessionStore = ClaudeSessionStore.shared

    var currentTask: ClaudeTask {
        sessionStore.effectiveSession?.task ?? .idle
    }

    var hasActiveSessions: Bool {
        sessionStore.activeSessionCount > 0
    }

    private init() {}

    func handleEvent(_ event: HookEvent) {
        _ = sessionStore.process(event)
    }
}
