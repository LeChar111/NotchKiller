import Foundation

struct HookInstaller {
    private static let hookScriptContent = """
    #!/bin/bash
    # NotchKiller Hook - forwards Claude Code events via Unix socket
    SOCKET_PATH="/tmp/notchkiller.sock"
    [ -S "$SOCKET_PATH" ] || exit 0

    IS_INTERACTIVE=true
    for CHECK_PID in $PPID $(ps -o ppid= -p $PPID 2>/dev/null | tr -d ' '); do
        if ps -o args= -p "$CHECK_PID" 2>/dev/null | grep -qE '(^| )(-p|--print)( |$)'; then
            IS_INTERACTIVE=false
            break
        fi
    done
    export NOTCHKILLER_INTERACTIVE=$IS_INTERACTIVE

    # Chaîne des processus parents : sert à ramener l'utilisateur vers son terminal.
    CHAIN=""
    WALK=$PPID
    for _ in 1 2 3 4 5 6 7 8; do
        case "$WALK" in ''|0|1) break ;; esac
        CHAIN="${CHAIN}${WALK},"
        WALK=$(ps -o ppid= -p "$WALK" 2>/dev/null | tr -d ' ')
    done
    export NOTCHKILLER_ANCESTORS="$CHAIN"
    export NOTCHKILLER_CLAUDE_PID=$PPID

    /usr/bin/python3 -c "
    import json, os, socket, sys
    try:
        input_data = json.load(sys.stdin)
    except:
        sys.exit(0)

    hook_event = input_data.get('hook_event_name', '')
    status_map = {
        'UserPromptSubmit': 'processing',
        'PreCompact': 'compacting',
        'SessionStart': 'waiting_for_input',
        'SessionEnd': 'ended',
        'PreToolUse': 'running_tool',
        'PostToolUse': 'processing',
        'PermissionRequest': 'waiting_for_input',
        'Stop': 'waiting_for_input',
        'SubagentStop': 'waiting_for_input'
    }

    output = {
        'session_id': input_data.get('session_id', ''),
        'cwd': input_data.get('cwd', ''),
        'event': hook_event,
        'status': input_data.get('status', status_map.get(hook_event, 'unknown')),
        'pid': int(os.environ.get('NOTCHKILLER_CLAUDE_PID', 0) or 0),
        'tty': None,
        'ancestors': [int(p) for p in os.environ.get('NOTCHKILLER_ANCESTORS', '').split(',') if p.isdigit()],
        'interactive': os.environ.get('NOTCHKILLER_INTERACTIVE', 'true') == 'true',
        'permission_mode': input_data.get('permission_mode', 'default')
    }

    if hook_event == 'UserPromptSubmit':
        prompt = input_data.get('prompt', '')
        if prompt:
            output['user_prompt'] = prompt

    tool = input_data.get('tool_name', '')
    if tool:
        output['tool'] = tool

    tool_id = input_data.get('tool_use_id', '')
    if tool_id:
        output['tool_use_id'] = tool_id

    tool_input = input_data.get('tool_input', {})
    if tool_input:
        output['tool_input'] = tool_input

    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect('$SOCKET_PATH')
        sock.sendall(json.dumps(output).encode())
        sock.close()
    except:
        pass

    # Demande de description postée par le widget : on la relaie une seule fois.
    session = output.get('session_id', '')
    if session and hook_event in ('UserPromptSubmit', 'PostToolUse'):
        flag = os.path.join('/tmp/notchkiller-requests', session)
        if os.path.exists(flag):
            try:
                os.remove(flag)
                print(json.dumps({'hookSpecificOutput': {
                    'hookEventName': hook_event,
                    'additionalContext': (
                        'NotchKiller demande une description de cette conversation. '
                        'Appelle maintenant le tool MCP set_session_summary (serveur notchkiller) '
                        'avec une phrase courte en français décrivant le sujet de la discussion, '
                        'et si utile le champ detail. Ne commente pas cette demande.'
                    ),
                }}))
            except OSError:
                pass
    "
    """

    @discardableResult
    static func installIfNeeded() -> Bool {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")

        guard FileManager.default.fileExists(atPath: claudeDir.path) else { return false }

        let hooksDir = claudeDir.appendingPathComponent("hooks")
        let hookScript = hooksDir.appendingPathComponent("notchkiller-hook.sh")
        let settings = claudeDir.appendingPathComponent("settings.json")

        try? FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)

        do {
            try hookScriptContent.write(to: hookScript, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookScript.path)
        } catch {
            return false
        }

        return updateSettings(at: settings)
    }

    private static func updateSettings(at settingsURL: URL) -> Bool {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        let command = "~/.claude/hooks/notchkiller-hook.sh"
        let hookEntry: [[String: Any]] = [["type": "command", "command": command]]
        let withMatcher: [[String: Any]] = [["matcher": "*", "hooks": hookEntry]]
        let withoutMatcher: [[String: Any]] = [["hooks": hookEntry]]
        let preCompactConfig: [[String: Any]] = [
            ["matcher": "auto", "hooks": hookEntry],
            ["matcher": "manual", "hooks": hookEntry]
        ]

        var hooks = json["hooks"] as? [String: Any] ?? [:]

        let hookEvents: [(String, [[String: Any]])] = [
            ("UserPromptSubmit", withoutMatcher),
            ("SessionStart", withoutMatcher),
            ("PreToolUse", withMatcher),
            ("PostToolUse", withMatcher),
            ("PermissionRequest", withMatcher),
            ("PreCompact", preCompactConfig),
            ("Stop", withoutMatcher),
            ("SubagentStop", withoutMatcher),
            ("SessionEnd", withoutMatcher),
        ]

        for (event, config) in hookEvents {
            if var existing = hooks[event] as? [[String: Any]] {
                let hasOurHook = existing.contains { entry in
                    if let h = entry["hooks"] as? [[String: Any]] {
                        return h.contains { ($0["command"] as? String)?.contains("notchkiller-hook.sh") == true }
                    }
                    return false
                }
                if !hasOurHook {
                    existing.append(contentsOf: config)
                    hooks[event] = existing
                }
            } else {
                hooks[event] = config
            }
        }

        json["hooks"] = hooks

        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }

        return (try? data.write(to: settingsURL)) != nil
    }

    static func isInstalled() -> Bool {
        let settings = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")

        guard let data = try? Data(contentsOf: settings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else { return false }

        return hooks.values.contains { value in
            guard let entries = value as? [[String: Any]] else { return false }
            return entries.contains { entry in
                guard let h = entry["hooks"] as? [[String: Any]] else { return false }
                return h.contains { ($0["command"] as? String)?.contains("notchkiller-hook.sh") == true }
            }
        }
    }
}
