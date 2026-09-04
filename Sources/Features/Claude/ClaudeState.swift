import Foundation

enum ClaudeTask: String, CaseIterable {
    case idle, working, sleeping, compacting, waiting

    var displayName: String {
        switch self {
        case .idle:       "Idle"
        case .working:    "Working..."
        case .sleeping:   "Sleeping"
        case .compacting: "Compacting..."
        case .waiting:    "Waiting..."
        }
    }

    var symbol: String {
        switch self {
        case .idle:       "moon.zzz"
        case .working:    "hammer.fill"
        case .sleeping:   "powersleep"
        case .compacting: "arrow.triangle.2.circlepath"
        case .waiting:    "hand.raised.fill"
        }
    }

    var color: String {
        switch self {
        case .idle:       "gray"
        case .working:    "blue"
        case .sleeping:   "purple"
        case .compacting: "orange"
        case .waiting:    "yellow"
        }
    }
}

enum ToolStatus {
    case running, success, error
}

struct SessionEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: String
    let tool: String?
    var status: ToolStatus
    let toolInput: [String: Any]?
    let toolUseId: String?
    let description: String?

    static func deriveDescription(tool: String?, toolInput: [String: Any]?) -> String? {
        guard let tool, let input = toolInput else { return nil }

        switch tool {
        case "Read":
            if let path = input["file_path"] as? String { return "Reading \(path)" }
        case "Write":
            if let path = input["file_path"] as? String { return "Writing \(path)" }
        case "Edit":
            if let path = input["file_path"] as? String { return "Editing \(path)" }
        case "Bash":
            if let command = input["command"] as? String { return command }
        case "Grep":
            if let pattern = input["pattern"] as? String { return "Searching: \(pattern)" }
        case "Glob":
            if let pattern = input["pattern"] as? String { return "Finding: \(pattern)" }
        default:
            break
        }

        for (_, value) in input {
            if let str = value as? String, !str.isEmpty { return str }
        }
        return nil
    }
}

private let promptMaxLength = 100

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }

    func truncatedForPrompt() -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > promptMaxLength else { return trimmed }
        let index = trimmed.index(trimmed.startIndex, offsetBy: promptMaxLength)
        return String(trimmed[..<index]) + "..."
    }
}
