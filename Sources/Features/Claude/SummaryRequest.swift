import Foundation

/// Demande de description adressée à Claude.
///
/// Un serveur MCP ne peut pas réveiller Claude de lui-même : c'est le client qui
/// décide quand appeler un outil. On dépose donc un drapeau que le hook relève au
/// prochain événement de la session (`UserPromptSubmit` ou `PostToolUse`) et
/// transforme en `additionalContext`. Pendant une session active, cela tombe
/// quelques secondes plus tard ; sur une session au repos, au prochain message.
enum SummaryRequest {
    static let directory = "/tmp/notchkiller-requests"

    @discardableResult
    static func arm(sessionId: String) -> Bool {
        guard !sessionId.isEmpty, sessionId.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        else { return false }

        try? FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return FileManager.default.createFile(atPath: path(for: sessionId), contents: nil)
    }

    static func isArmed(sessionId: String) -> Bool {
        FileManager.default.fileExists(atPath: path(for: sessionId))
    }

    static func clear(sessionId: String) {
        try? FileManager.default.removeItem(atPath: path(for: sessionId))
    }

    private static func path(for sessionId: String) -> String {
        "\(directory)/\(sessionId)"
    }
}
