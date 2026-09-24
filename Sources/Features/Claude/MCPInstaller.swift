import Foundation

/// Déclare NotchKiller comme serveur MCP utilisateur dans `~/.claude.json` (et
/// la config de chaque autre profil Claude Code),
/// pour que Claude Code puisse pousser lui-même le résumé de la conversation.
struct MCPInstaller {
    private static let serverName = "notchkiller"

    /// `~/.claude.json` et la config de chaque profil `CLAUDE_CONFIG_DIR`.
    private static var configURLs: [URL] {
        ClaudeProfiles.directories.flatMap(ClaudeProfiles.globalConfigs(for:))
    }

    private static var primaryConfigURL: URL {
        ClaudeProfiles.globalConfig(for: ClaudeProfiles.defaultDirectory)
    }

    /// Commande actuellement déclarée dans `~/.claude.json`, telle qu'elle y figure.
    static var registeredCommand: String? {
        if Demo.isActive { return executablePath }
        guard let servers = currentServers(at: primaryConfigURL),
              let entry = servers[serverName] as? [String: Any] else { return nil }
        return entry["command"] as? String
    }

    /// Commande à taper soi-même si l'on préfère ne pas laisser l'app écrire
    /// dans `~/.claude.json`.
    static var manualCommand: String {
        "claude mcp add \(serverName) --scope user -- \(executablePath) --mcp"
    }

    /// Installé seulement si chaque profil le déclare : un profil oublié, c'est
    /// autant de sessions qui ne peuvent jamais se décrire.
    static func isInstalled() -> Bool {
        if Demo.isActive { return true }
        let urls = configURLs
        return !urls.isEmpty && urls.allSatisfy(isInstalled(at:))
    }

    @discardableResult
    static func installIfNeeded() -> Bool {
        configURLs.map(installIfNeeded(at:)).allSatisfy { $0 }
    }

    private static func isInstalled(at url: URL) -> Bool {
        guard let servers = currentServers(at: url),
              let entry = servers[serverName] as? [String: Any],
              let command = entry["command"] as? String else { return false }
        return command == executablePath
    }

    private static func installIfNeeded(at url: URL) -> Bool {
        guard !isInstalled(at: url) else { return true }

        var json: [String: Any] = [:]
        let permissions = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions]
        if let data = try? Data(contentsOf: url) {
            guard let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                // Fichier illisible : on n'y touche pas plutôt que de l'écraser.
                return false
            }
            json = existing
            backupOnce(data, of: url)
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
        guard (try? data.write(to: url, options: .atomic)) != nil else { return false }
        // Le fichier contient le compte OAuth : l'écriture atomique ne doit pas
        // le rendre lisible par tous.
        try? FileManager.default.setAttributes([.posixPermissions: permissions ?? 0o600], ofItemAtPath: url.path)
        return true
    }

    private static func currentServers(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["mcpServers"] as? [String: Any]
    }

    /// Une seule sauvegarde par fichier, la première fois qu'on le modifie.
    private static func backupOnce(_ data: Data, of url: URL) {
        let backup = url.appendingPathExtension("notchkiller-backup")
        guard !FileManager.default.fileExists(atPath: backup.path) else { return }
        try? data.write(to: backup, options: .atomic)
    }

    static var executablePath: String {
        if Demo.isActive { return "~/Applications/NotchKiller.app/Contents/MacOS/NotchKiller" }
        return Bundle.main.executablePath ?? CommandLine.arguments.first ?? "NotchKiller"
    }
}
