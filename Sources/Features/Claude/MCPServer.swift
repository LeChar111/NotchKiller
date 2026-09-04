import Foundation

/// Serveur MCP en mode stdio, activé par `NotchKiller --mcp`.
/// Claude Code lance ce processus, appelle `set_session_summary`, et le résumé
/// part vers l'app par le même socket Unix que les hooks.
enum MCPServer {
    private static let protocolVersion = "2024-11-05"

    static func run() -> Never {
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }
            handle(data)
        }
        exit(0)
    }

    // MARK: Boucle JSON-RPC

    private static func handle(_ data: Data) {
        guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let method = message["method"] as? String ?? ""
        let id = message["id"]

        switch method {
        case "initialize":
            respond(id: id, result: [
                "protocolVersion": protocolVersion,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "notchkiller", "version": "2.1.0"],
            ])

        case "tools/list":
            respond(id: id, result: ["tools": [toolDefinition]])

        case "tools/call":
            let params = message["params"] as? [String: Any] ?? [:]
            callTool(id: id, params: params)

        case "ping":
            respond(id: id, result: [String: Any]())

        case "notifications/initialized", "notifications/cancelled":
            break

        default:
            guard id != nil else { return }
            respond(id: id, error: (-32601, "Méthode inconnue : \(method)"))
        }
    }

    private static var toolDefinition: [String: Any] {
        [
            "name": "set_session_summary",
            "description": """
            Décrit la conversation en cours dans le widget NotchKiller (encoche macOS). \
            Le résumé apparaît au survol de la session dans l'onglet Claude. \
            À appeler quand le sujet de la discussion se précise ou change : une phrase \
            en français décrivant ce sur quoi porte le travail, pas ce que tu viens de faire.
            """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "summary": [
                        "type": "string",
                        "description": "Une phrase courte (120 signes max) : le sujet de la conversation.",
                    ],
                    "detail": [
                        "type": "string",
                        "description": "Optionnel — une ou deux phrases de contexte : l'état d'avancement, ce qui reste.",
                    ],
                    "session_id": [
                        "type": "string",
                        "description": "Optionnel — identifiant de session Claude Code. À défaut, le répertoire de travail sert de clé.",
                    ],
                ],
                "required": ["summary"],
            ],
        ]
    }

    private static func callTool(id: Any?, params: [String: Any]) {
        guard (params["name"] as? String) == "set_session_summary" else {
            respond(id: id, error: (-32602, "Outil inconnu"))
            return
        }

        let arguments = params["arguments"] as? [String: Any] ?? [:]
        guard let summary = (arguments["summary"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty else {
            respond(id: id, result: toolResult("Aucun résumé fourni.", isError: true))
            return
        }

        var payload: [String: Any] = [
            "session_id": arguments["session_id"] as? String ?? ProcessInfo.processInfo.environment["CLAUDE_SESSION_ID"] ?? "",
            "cwd": FileManager.default.currentDirectoryPath,
            "event": "Summary",
            "status": "summary",
            "summary": String(summary.prefix(200)),
        ]
        if let detail = (arguments["detail"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
            payload["summary_detail"] = String(detail.prefix(400))
        }

        let delivered = send(payload)
        respond(id: id, result: toolResult(
            delivered
                ? "Résumé affiché dans l'encoche."
                : "NotchKiller ne tourne pas — résumé ignoré.",
            isError: false
        ))
    }

    private static func toolResult(_ text: String, isError: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }

    // MARK: Socket Unix vers l'app

    @discardableResult
    private static func send(_ payload: [String: Any]) -> Bool {
        guard FileManager.default.fileExists(atPath: SocketServer.socketPath),
              let data = try? JSONSerialization.data(withJSONObject: payload) else { return false }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = SocketServer.socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                strcpy(UnsafeMutableRawPointer(pathPtr).assumingMemoryBound(to: CChar.self), ptr)
            }
        }

        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return false }

        return data.withUnsafeBytes { buffer in
            write(fd, buffer.baseAddress, buffer.count) == buffer.count
        }
    }

    // MARK: Écriture stdout

    private static func respond(id: Any?, result: [String: Any]) {
        emit(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result])
    }

    private static func respond(id: Any?, error: (Int, String)) {
        emit(["jsonrpc": "2.0", "id": id ?? NSNull(),
              "error": ["code": error.0, "message": error.1]])
    }

    private static func emit(_ message: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }
}
