import Foundation

@MainActor
@Observable
final class ClaudeSessionData: Identifiable {
    let id: String
    let cwd: String
    let sessionNumber: Int
    let sessionStartTime: Date
    let isInteractive: Bool

    private(set) var task: ClaudeTask = .idle
    private(set) var isProcessing: Bool = false
    private(set) var lastActivity: Date
    private(set) var recentEvents: [SessionEvent] = []
    private(set) var lastUserPrompt: String?
    private(set) var formattedDuration: String = "0m 00s"

    /// Ce sur quoi porte la conversation, tel que Claude le décrit lui-même.
    private(set) var summary: String?
    private(set) var summaryDetail: String?
    private(set) var summaryUpdatedAt: Date?
    private(set) var summaryRequestedAt: Date?

    /// Une demande reste « en attente » tant que Claude n'a pas répondu, et au
    /// plus 3 minutes : au-delà, la session ne travaille manifestement plus.
    var isSummaryPending: Bool {
        guard let requested = summaryRequestedAt else { return false }
        if let updated = summaryUpdatedAt, updated > requested { return false }
        return Date().timeIntervalSince(requested) < 180
    }

    /// Chaîne de processus vers l'app terminal, pour pouvoir y revenir.
    private(set) var ancestorPIDs: [Int] = []
    /// Nom de l'app qui héberge la session — résolu une fois, pas à chaque rendu.
    private(set) var terminalName: String?
    private(set) var processingStartedAt: Date?
    private(set) var finishedAt: Date?

    /// Durée du dernier tour, en secondes — sert à ne notifier que ce qui compte.
    var lastTurnDuration: TimeInterval {
        guard let start = processingStartedAt else { return 0 }
        return (finishedAt ?? Date()).timeIntervalSince(start)
    }

    private var durationTimer: Task<Void, Never>?
    private var sleepTimer: Task<Void, Never>?
    private static let maxEvents = 20
    private static let sleepDelay: Duration = .seconds(300)

    var projectName: String {
        (cwd as NSString).lastPathComponent
    }

    var displayTitle: String {
        let title = "\(projectName) #\(sessionNumber)"
        if let prompt = lastUserPrompt {
            return "\(title) - \(prompt)"
        }
        return title
    }

    var activityPreview: String? {
        recentEvents.last?.description ?? recentEvents.last?.tool ?? recentEvents.last?.type
    }

    init(sessionId: String, cwd: String, sessionNumber: Int, isInteractive: Bool = true) {
        self.id = sessionId
        self.cwd = cwd
        self.sessionNumber = sessionNumber
        self.isInteractive = isInteractive
        self.sessionStartTime = Date()
        self.lastActivity = Date()
        startDurationTimer()
    }

    func updateTask(_ newTask: ClaudeTask) {
        task = newTask
        lastActivity = Date()
    }

    func updateProcessingState(isProcessing: Bool) {
        if isProcessing && !self.isProcessing {
            processingStartedAt = Date()
            finishedAt = nil
        }
        self.isProcessing = isProcessing
        lastActivity = Date()
    }

    func recordAncestors(_ pids: [Int]?) {
        guard let pids, !pids.isEmpty, pids != ancestorPIDs else { return }
        ancestorPIDs = pids
        terminalName = TerminalFocus.hostName(ancestors: pids)
    }

    /// Fin d'un tour : `Stop` côté hook. Renvoie la durée du tour écoulé.
    @discardableResult
    func markFinished() -> TimeInterval {
        let duration = lastTurnDuration
        finishedAt = Date()
        isProcessing = false
        return duration
    }

    func requestSummary() {
        guard SummaryRequest.arm(sessionId: id) else { return }
        summaryRequestedAt = Date()
    }

    func recordSummary(_ text: String, detail: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        summary = trimmed
        summaryDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        summaryUpdatedAt = Date()
    }

    func recordUserPrompt(_ prompt: String) {
        lastUserPrompt = prompt.truncatedForPrompt()
        lastActivity = Date()
    }

    func recordPreToolUse(tool: String?, toolInput: [String: Any]?, toolUseId: String?) {
        let description = SessionEvent.deriveDescription(tool: tool, toolInput: toolInput)
        let event = SessionEvent(
            timestamp: Date(), type: "PreToolUse", tool: tool,
            status: .running, toolInput: toolInput, toolUseId: toolUseId,
            description: description
        )
        recentEvents.append(event)
        while recentEvents.count > Self.maxEvents { recentEvents.removeFirst() }
        lastActivity = Date()
    }

    func recordPostToolUse(tool: String?, toolUseId: String?, success: Bool) {
        if let toolUseId,
           let index = recentEvents.lastIndex(where: { $0.toolUseId == toolUseId && $0.status == .running }) {
            recentEvents[index].status = success ? .success : .error
        } else {
            let event = SessionEvent(
                timestamp: Date(), type: "PostToolUse", tool: tool,
                status: success ? .success : .error, toolInput: nil,
                toolUseId: toolUseId, description: nil
            )
            recentEvents.append(event)
            while recentEvents.count > Self.maxEvents { recentEvents.removeFirst() }
        }
        lastActivity = Date()
    }

    func resetSleepTimer() {
        sleepTimer?.cancel()
        sleepTimer = Task {
            try? await Task.sleep(for: Self.sleepDelay)
            guard !Task.isCancelled else { return }
            updateTask(.sleeping)
        }
    }

    func endSession() {
        durationTimer?.cancel()
        sleepTimer?.cancel()
        isProcessing = false
    }

    private func startDurationTimer() {
        durationTimer = Task {
            while !Task.isCancelled {
                let total = Int(Date().timeIntervalSince(sessionStartTime))
                formattedDuration = String(format: "%dm %02ds", total / 60, total % 60)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
