import Foundation

/// Titre que Claude Code génère lui-même pour une conversation.
///
/// Claude Code ajoute régulièrement au transcript JSONL une ligne
/// `{"type":"ai-title","aiTitle":…}`. Contrairement au résumé MCP, elle ne
/// dépend pas de la bonne volonté du modèle : toute session en a une, ce qui
/// en fait la description de repli — jamais d'encart vide.
enum TranscriptTitle {
    /// Le titre est réécrit souvent : la fin du fichier suffit presque toujours.
    private static let tailSize: UInt64 = 512 * 1024
    /// Le dossier de travail figure dès les premiers messages.
    private static let headSize = 256 * 1024

    struct Info: Sendable {
        var title: String?
        var lastPrompt: String?
        var workingDirectory: String?
    }

    static func latest(in path: String) -> String? {
        info(in: path, needsDirectory: false).title
    }

    static func info(in path: String, needsDirectory: Bool = true) -> Info {
        guard let handle = FileHandle(forReadingAtPath: path) else { return Info() }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > tailSize ? size - tailSize : 0
        var info = scanTail(handle, from: start)
        if info.title == nil, start > 0 {
            let full = scanTail(handle, from: 0)
            info.title = full.title
            info.lastPrompt = info.lastPrompt ?? full.lastPrompt
        }
        if needsDirectory, info.workingDirectory == nil {
            info.workingDirectory = scanHead(handle)
        }
        return info
    }

    private static func lines(_ handle: FileHandle, from offset: UInt64, limit: Int? = nil) -> [Substring] {
        guard (try? handle.seek(toOffset: offset)) != nil else { return [] }
        let data = limit.map { (try? handle.read(upToCount: $0)) ?? nil } ?? (try? handle.readToEnd())
        guard let data else { return [] }
        // Décodage tolérant : la fenêtre de fin peut couper un caractère multi-octets.
        return String(decoding: data, as: UTF8.self).split(separator: "\n")
    }

    private static func scanTail(_ handle: FileHandle, from offset: UInt64) -> Info {
        var info = Info()
        for line in lines(handle, from: offset).reversed() {
            if info.title == nil, line.contains("\"ai-title\"") {
                info.title = field(line, type: "ai-title", key: "aiTitle")
            } else if info.lastPrompt == nil, line.contains("\"last-prompt\"") {
                info.lastPrompt = field(line, type: "last-prompt", key: "lastPrompt")
            } else if info.workingDirectory == nil, line.contains("\"cwd\"") {
                info.workingDirectory = json(line)?["cwd"] as? String
            }
            if info.title != nil, info.lastPrompt != nil, info.workingDirectory != nil { break }
        }
        return info
    }

    private static func scanHead(_ handle: FileHandle) -> String? {
        for line in lines(handle, from: 0, limit: headSize) where line.contains("\"cwd\"") {
            if let cwd = json(line)?["cwd"] as? String, !cwd.isEmpty { return cwd }
        }
        return nil
    }

    private static func field(_ line: Substring, type: String, key: String) -> String? {
        guard let object = json(line), object["type"] as? String == type,
              let value = (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private static func json(_ line: Substring) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    }
}
