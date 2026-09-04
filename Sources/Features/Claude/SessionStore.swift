import Foundation

@MainActor
@Observable
final class ClaudeSessionStore {
    static let shared = ClaudeSessionStore()

    private(set) var sessions: [String: ClaudeSessionData] = [:]
    private(set) var selectedSessionId: String?

    /// Dernière session ayant terminé un tour, pour la bannière de l'encoche.
    private(set) var finishedNotice: FinishedNotice?

    struct FinishedNotice: Equatable {
        let sessionId: String
        let projectName: String
        let duration: TimeInterval
        let at: Date
    }

    /// Sous ce seuil, le tour est trop court pour mériter d'interrompre l'utilisateur.
    private static let noticeMinimumTurn: TimeInterval = 5
    private var nextSessionNumberByProject: [String: Int] = [:]

    private init() {}

    var sortedSessions: [ClaudeSessionData] {
        sessions.values.sorted { lhs, rhs in
            if lhs.isProcessing != rhs.isProcessing { return lhs.isProcessing }
            return lhs.lastActivity > rhs.lastActivity
        }
    }

    var activeSessionCount: Int { sessions.count }

    var effectiveSession: ClaudeSessionData? {
        if let id = selectedSessionId, let s = sessions[id] { return s }
        if sessions.count == 1 { return sessions.values.first }
        return sortedSessions.first
    }

    func selectSession(_ sessionId: String?) {
        selectedSessionId = sessionId
    }

    func clearFinishedNotice() {
        finishedNotice = nil
    }

    /// Ramène au terminal de la session visée par la bannière.
    @discardableResult
    func focusTerminal(for sessionId: String) -> Bool {
        guard let session = sessions[sessionId] else { return false }
        return TerminalFocus.focus(ancestors: session.ancestorPIDs)
    }

    func process(_ event: HookEvent) -> ClaudeSessionData {
        let isInteractive = event.interactive ?? true

        // Un résumé n'est pas une activité : il ne doit ni relancer l'état
        // « en cours », ni réarmer la minuterie de mise en veille.
        if event.event == "Summary" {
            let target = matchSession(sessionId: event.sessionId, cwd: event.cwd)
                ?? getOrCreateSession(sessionId: event.sessionId, cwd: event.cwd, isInteractive: isInteractive)
            if let summary = event.summary {
                target.recordSummary(summary, detail: event.summaryDetail)
            }
            return target
        }

        let session = getOrCreateSession(sessionId: event.sessionId, cwd: event.cwd, isInteractive: isInteractive)
        session.recordAncestors(event.ancestors)
        let isProcessing = event.status != "waiting_for_input"
        session.updateProcessingState(isProcessing: isProcessing)

        switch event.event {
        case "UserPromptSubmit":
            if let prompt = event.userPrompt {
                session.recordUserPrompt(prompt)
            }
            session.updateTask(.working)

        case "PreCompact":
            session.updateTask(.compacting)

        case "SessionStart":
            if isProcessing { session.updateTask(.working) }

        case "PreToolUse":
            let toolInput = event.toolInput?.mapValues { $0.value }
            session.recordPreToolUse(tool: event.tool, toolInput: toolInput, toolUseId: event.toolUseId)
            if event.tool == "AskUserQuestion" {
                session.updateTask(.waiting)
            } else {
                session.updateTask(.working)
            }

        case "PermissionRequest":
            session.updateTask(.waiting)

        case "PostToolUse":
            let success = event.status != "error"
            session.recordPostToolUse(tool: event.tool, toolUseId: event.toolUseId, success: success)
            session.updateTask(.working)

        case "Stop":
            let duration = session.markFinished()
            session.updateTask(.idle)
            if duration >= Self.noticeMinimumTurn {
                finishedNotice = FinishedNotice(
                    sessionId: session.id,
                    projectName: session.projectName,
                    duration: duration,
                    at: Date()
                )
            }

        case "SubagentStop":
            session.updateTask(.idle)

        case "SessionEnd":
            session.endSession()
            removeSession(event.sessionId)

        default:
            if !isProcessing && session.task != .idle {
                session.updateTask(.idle)
            }
        }

        session.resetSleepTimer()
        return session
    }

    /// L'outil MCP ne connaît pas toujours l'identifiant de session : on
    /// retombe alors sur le répertoire de travail, qui suffit en pratique.
    private func matchSession(sessionId: String, cwd: String) -> ClaudeSessionData? {
        if !sessionId.isEmpty, let exact = sessions[sessionId] { return exact }
        guard !cwd.isEmpty else { return nil }
        return sessions.values
            .filter { $0.cwd == cwd }
            .max { $0.lastActivity < $1.lastActivity }
    }

    private func getOrCreateSession(sessionId: String, cwd: String, isInteractive: Bool) -> ClaudeSessionData {
        if let existing = sessions[sessionId] { return existing }

        let projectName = (cwd as NSString).lastPathComponent
        let number = nextSessionNumberByProject[projectName, default: 0] + 1
        nextSessionNumberByProject[projectName] = number

        let session = ClaudeSessionData(sessionId: sessionId, cwd: cwd, sessionNumber: number, isInteractive: isInteractive)
        sessions[sessionId] = session

        if activeSessionCount == 1 { selectedSessionId = sessionId }
        else { selectedSessionId = nil }
        return session
    }

    private func removeSession(_ sessionId: String) {
        sessions.removeValue(forKey: sessionId)
        if finishedNotice?.sessionId == sessionId { finishedNotice = nil }
        if selectedSessionId == sessionId { selectedSessionId = nil }
        if activeSessionCount == 1 { selectedSessionId = sessions.keys.first }
    }

    func dismissSession(_ sessionId: String) {
        sessions[sessionId]?.endSession()
        removeSession(sessionId)
    }
}
