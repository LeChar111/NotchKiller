import AppKit

enum TerminalFocus {
    /// Tout ce qui permet de retrouver la fenêtre et l'onglet d'une session.
    struct Target: Sendable {
        let ancestors: [Int]
        let cwd: String
        let tty: String?
        let idePort: Int?
        /// Titre généré par Claude Code, repris dans le titre du terminal.
        let title: String?
    }

    /// Ramène l'app hôte au premier plan, puis vise la fenêtre et l'onglet de
    /// la session quand l'app le permet. Renvoie `false` sans app hôte.
    @discardableResult
    static func focus(_ target: Target) -> Bool {
        guard let app = hostApp(ancestors: target.ancestors) else { return false }

        if let folder = ideWorkspace(for: target, hostPID: app.processIdentifier),
           let bundleURL = app.bundleURL {
            // Un IDE Electron n'a qu'un processus pour toutes ses fenêtres :
            // rouvrir le dossier déjà ouvert ramène sa fenêtre au premier plan.
            NSWorkspace.shared.open(
                [URL(fileURLWithPath: folder)],
                withApplicationAt: bundleURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
            return true
        }

        guard let script = tabScript(for: target, bundleID: app.bundleIdentifier) else {
            app.activate()
            return true
        }
        Task {
            let found = (try? await AppleScriptHelper.execute(script))?.booleanValue ?? false
            if !found { _ = await MainActor.run { app.activate() } }
        }
        return true
    }

    static func hostName(ancestors: [Int]) -> String? {
        ancestors
            .compactMap { NSRunningApplication(processIdentifier: pid_t($0)) }
            .first { $0.activationPolicy == .regular }?
            .localizedName
    }

    private static func hostApp(ancestors: [Int]) -> NSRunningApplication? {
        let apps = ancestors.compactMap { NSRunningApplication(processIdentifier: pid_t($0)) }
        return apps.first { $0.activationPolicy == .regular }
            ?? apps.first { $0.bundleURL != nil }
    }

    // MARK: - Cursor, VS Code et dérivés

    /// Chaque fenêtre où l'extension Claude Code tourne publie
    /// `~/.claude/ide/<port>.lock` avec ses dossiers. Le port hérité par la
    /// session désigne sa fenêtre ; à défaut, le dossier qui contient le cwd.
    private static func ideWorkspace(for target: Target, hostPID: pid_t) -> String? {
        let locks = ideLocks().filter { $0.pid == Int(hostPID) }
        guard !locks.isEmpty else { return nil }

        let lock = target.idePort.flatMap { port in locks.first { $0.port == port } }
            ?? locks
                .filter { $0.folders.contains { contains($0, target.cwd) } }
                .max { ($0.folders.map(\.count).max() ?? 0) < ($1.folders.map(\.count).max() ?? 0) }

        // Un espace multi-racines s'ouvre par son fichier .code-workspace, que
        // le verrou ne donne pas : rouvrir un de ses dossiers créerait une fenêtre.
        guard let lock, lock.folders.count == 1 else { return nil }
        return lock.folders[0]
    }

    private struct IDELock {
        let port: Int
        let pid: Int
        let folders: [String]
    }

    private static func ideLocks() -> [IDELock] {
        let fm = FileManager.default
        let dirs = ([fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude")]
            + ClaudeProfiles.directories)
            .map { $0.appendingPathComponent("ide") }

        var seen = Set<Int>()
        return Set(dirs.map(\.standardizedFileURL)).flatMap { dir -> [IDELock] in
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            return files.compactMap { file in
                guard file.pathExtension == "lock",
                      let port = Int(file.deletingPathExtension().lastPathComponent),
                      seen.insert(port).inserted,
                      let data = try? Data(contentsOf: file),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let pid = json["pid"] as? Int
                else { return nil }
                return IDELock(port: port, pid: pid, folders: json["workspaceFolders"] as? [String] ?? [])
            }
        }
    }

    private static func contains(_ folder: String, _ path: String) -> Bool {
        let folder = folder.hasSuffix("/") ? String(folder.dropLast()) : folder
        return path == folder || path.hasPrefix(folder + "/")
    }

    // MARK: - Terminaux scriptables

    /// Script qui sélectionne l'onglet de la session et renvoie `true` s'il
    /// l'a trouvé ; `nil` quand l'app hôte n'expose rien d'utilisable.
    private static func tabScript(for target: Target, bundleID: String?) -> String? {
        switch bundleID {
        case "com.mitchellh.ghostty":
            // Ghostty ne donne pas le tty : on retient les terminaux du bon
            // dossier, départagés par le titre que Claude Code y affiche.
            let title = target.title.map(escape) ?? ""
            return """
                tell application id "com.mitchellh.ghostty"
                    set candidates to {}
                    repeat with t in terminals
                        if working directory of t is "\(escape(target.cwd))" then set end of candidates to t
                    end repeat
                    if candidates is {} then return false
                    set chosen to item 1 of candidates
                    if "\(title)" is not "" then
                        repeat with t in candidates
                            if name of t contains "\(title)" then
                                set chosen to t
                                exit repeat
                            end if
                        end repeat
                    end if
                    focus chosen
                    activate
                    return true
                end tell
                """
        case "com.apple.Terminal":
            guard let tty = target.tty else { return nil }
            return """
                tell application id "com.apple.Terminal"
                    repeat with w in windows
                        repeat with t in tabs of w
                            if tty of t is "/dev/\(escape(tty))" then
                                set selected of t to true
                                set index of w to 1
                                activate
                                return true
                            end if
                        end repeat
                    end repeat
                    return false
                end tell
                """
        case "com.googlecode.iterm2":
            guard let tty = target.tty else { return nil }
            return """
                tell application id "com.googlecode.iterm2"
                    repeat with w in windows
                        repeat with t in tabs of w
                            repeat with s in sessions of t
                                if tty of s is "/dev/\(escape(tty))" then
                                    select w
                                    tell t to select
                                    tell s to select
                                    activate
                                    return true
                                end if
                            end repeat
                        end repeat
                    end repeat
                    return false
                end tell
                """
        default:
            return nil
        }
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
