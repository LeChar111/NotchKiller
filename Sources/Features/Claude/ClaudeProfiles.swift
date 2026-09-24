import Foundation

/// Profils Claude Code présents sur la machine.
///
/// `~/.claude` est le profil par défaut ; `CLAUDE_CONFIG_DIR` permet d'en avoir
/// d'autres (`~/.claude-work`…). L'app, lancée par launchd, ne voit pas cette
/// variable : on repère donc les profils sur disque, et chacun doit recevoir
/// hooks et serveur MCP — sinon ses sessions ne peuvent pas se décrire.
enum ClaudeProfiles {
    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static var defaultDirectory: URL { home.appendingPathComponent(".claude") }

    static var directories: [URL] {
        var result: [URL] = []
        if FileManager.default.fileExists(atPath: defaultDirectory.path) {
            result.append(defaultDirectory)
        }
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? []
        for name in entries.sorted() where name.hasPrefix(".claude-") {
            let dir = home.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let looksLikeProfile = ["settings.json", ".claude.json"].contains {
                FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
            }
            if looksLikeProfile { result.append(dir) }
        }
        return result
    }

    /// Toutes les configs que Claude Code peut lire pour ce profil. Le profil
    /// par défaut en a deux : `~/.claude.json` sans `CLAUDE_CONFIG_DIR`, et
    /// `~/.claude/.claude.json` quand la variable pointe explicitement dessus
    /// (ce que fait une fonction `claude` qui demande le compte).
    static func globalConfigs(for directory: URL) -> [URL] {
        let main = globalConfig(for: directory)
        let inside = directory.appendingPathComponent(".claude.json")
        guard inside != main, FileManager.default.fileExists(atPath: inside.path) else { return [main] }
        return [main, inside]
    }

    /// Config globale du profil : `~/.claude.json` pour le profil par défaut,
    /// `<dossier>/.claude.json` pour un profil `CLAUDE_CONFIG_DIR`.
    static func globalConfig(for directory: URL) -> URL {
        directory.standardizedFileURL == defaultDirectory.standardizedFileURL
            ? home.appendingPathComponent(".claude.json")
            : directory.appendingPathComponent(".claude.json")
    }
}
