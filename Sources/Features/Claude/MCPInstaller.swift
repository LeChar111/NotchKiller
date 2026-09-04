import Foundation

/// Déclare NotchKiller comme serveur MCP utilisateur dans `~/.claude.json`,
/// pour que Claude Code puisse pousser lui-même le résumé de la conversation.
struct MCPInstaller {
    private static let serverName = "notchkiller"

    private static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
    }

    /// Commande actuellement déclarée dans `~/.claude.json`, telle qu'elle y figure.
    static var registeredCommand: String? {
        guard let servers = currentServers(),
              let entry = servers[serverName] as? [String: Any] else { return nil }
        return entry["command"] as? String
    }

    /// Commande à taper soi-même si l'on préfère ne pas laisser l'app écrire
    /// dans `~/.claude.json`.
    static var manualCommand: String {
        "claude mcp add \(serverName) --scope user -- \(executablePath) --mcp"
    }

    static func isInstalled() -> Bool {
        guard let servers = currentServers(),
              let entry = servers[serverName] as? [String: Any],
              let command = entry["command"] as? String else { return false }
        return command == executablePath
    }

    @discardableResult
    static func installIfNeeded() -> Bool {
        guard !isInstalled() else { return true }

        let url = configURL
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: url) {
            guard let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                // Fichier illisible : on n'y touche pas plutôt que de l'écraser.
                return false
            }
            json = existing
            backupOnce(data)
        }

        var servers = json["mcpServers"] as? [String: Any] ?? [:]
        servers[serverName] = [
            "type": "stdio",
            "command": executablePath,
            "args": ["--mcp"],
            "env": [String: String](),
        ]
        json["mcpServers"] = servers

        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) else {
            return false
        }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    private static func currentServers() -> [String: Any]? {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["mcpServers"] as? [String: Any]
    }

    /// Une seule sauvegarde, la première fois qu'on modifie le fichier.
    private static func backupOnce(_ data: Data) {
        let backup = configURL.appendingPathExtension("notchkiller-backup")
        guard !FileManager.default.fileExists(atPath: backup.path) else { return }
        try? data.write(to: backup, options: .atomic)
    }

    static var executablePath: String {
        Bundle.main.executablePath ?? CommandLine.arguments.first ?? "NotchKiller"
    }
}
