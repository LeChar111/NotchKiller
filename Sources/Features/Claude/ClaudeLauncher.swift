import AppKit

/// Ouvre un terminal dans un dossier, avec éventuellement une commande à y
/// taper — sert au bouton « Ouvrir » des sessions et à la reprise d'une
/// conversation de l'historique.
enum ClaudeLauncher {
    enum Target: String, CaseIterable, Identifiable {
        case ghostty, terminal, cursor, copy

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ghostty:  "Ghostty"
            case .terminal: "Terminal"
            case .cursor:   "Cursor"
            case .copy:     "Copier la commande"
            }
        }

        var symbol: String {
            switch self {
            case .ghostty, .terminal: "apple.terminal"
            case .cursor:             "cursorarrow.rays"
            case .copy:               "doc.on.doc"
            }
        }

        var bundleID: String? {
            switch self {
            case .ghostty:  "com.mitchellh.ghostty"
            case .terminal: "com.apple.Terminal"
            case .cursor:   "com.todesktop.230313mzl4w4u92"
            case .copy:     nil
            }
        }

        var isInstalled: Bool {
            guard let bundleID else { return true }
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        }

        static var available: [Target] { allCases.filter(\.isInstalled) }
    }

    /// Terminal préféré : Ghostty s'il est installé, sinon Terminal.app.
    static var preferredTerminal: Target {
        Target.ghostty.isInstalled ? .ghostty : .terminal
    }

    // MARK: Ouvrir un dossier

    static func openTerminal(at directory: String, target: Target = preferredTerminal) {
        run(nil, in: directory, target: target)
    }

    // MARK: Reprendre une conversation

    static func resume(_ entry: ClaudeHistoryEntry, in target: Target) {
        let command = resumeCommand(for: entry)
        switch target {
        case .copy:
            copy(command)
        case .cursor:
            openInCursor(entry, command: command)
        case .ghostty, .terminal:
            run(command, in: entry.workingDirectory, target: target)
        }
    }

    /// `_claude_run` est la fonction zsh de l'utilisateur : elle ajoute ses
    /// options habituelles sans reposer la question du compte. À défaut, on
    /// appelle le binaire directement — surtout pas la fonction `claude`, qui
    /// demanderait le compte au lieu de reprendre.
    static func resumeCommand(for entry: ClaudeHistoryEntry) -> String {
        "CLAUDE_CONFIG_DIR=\(shellQuote(entry.profile.directory.path)) \(ShellRunner.claude) --resume \(entry.id)"
    }

    // MARK: Cibles

    private static func run(_ command: String?, in directory: String, target: Target) {
        switch target {
        case .ghostty:
            ghostty(command, in: directory)
        case .terminal:
            appleTerminal(command, in: directory)
        case .cursor:
            openFolderInCursor(directory)
            if let command { copy(command) }
        case .copy:
            copy(command ?? "cd \(shellQuote(directory))")
        }
    }

    /// Ghostty ≥ 1.3 : `new window` avec une configuration de surface porte à
    /// la fois le dossier et la commande tapée au démarrage du shell.
    private static func ghostty(_ command: String?, in directory: String) {
        var lines = [
            "set cfg to new surface configuration",
            "set initial working directory of cfg to \(appleScriptString(directory))",
        ]
        if let command {
            lines.append("set initial input of cfg to \(appleScriptString(command)) & linefeed")
        }
        lines.append("new window with configuration cfg")
        lines.append("activate")
        execute("""
            tell application id "com.mitchellh.ghostty"
                \(lines.joined(separator: "\n    "))
            end tell
            """) {
            // Automatisation refusée : on se contente d'ouvrir le dossier.
            _ = ActionLauncher.openTerminal(at: directory)
            if let command { copy(command) }
        }
    }

    private static func appleTerminal(_ command: String?, in directory: String) {
        let line = ["cd \(shellQuote(directory))", command].compactMap { $0 }.joined(separator: " && ")
        execute("""
            tell application id "com.apple.Terminal"
                do script \(appleScriptString(line))
                activate
            end tell
            """) {
            _ = ActionLauncher.openTerminal(at: directory)
            if let command { copy(command) }
        }
    }

    /// L'extension Claude Code de Cursor sait rouvrir une session par lien,
    /// mais elle lit le profil par défaut : pour un autre profil, on ouvre le
    /// dossier et la commande attend dans le presse-papiers.
    private static func openInCursor(_ entry: ClaudeHistoryEntry, command: String) {
        openFolderInCursor(entry.workingDirectory)
        copy(command)
        guard entry.profile.isDefault,
              let url = URL(string: "cursor://anthropic.claude-code/open?session=\(entry.id)") else { return }
        // Laisser à Cursor le temps d'ouvrir la fenêtre du dossier avant le lien.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            NSWorkspace.shared.open(url)
        }
    }

    private static func openFolderInCursor(_ directory: String) {
        guard let bundleID = Target.cursor.bundleID,
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: directory)],
            withApplicationAt: app,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    // MARK: Outils

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static func execute(_ script: String, onFailure: @escaping @MainActor () -> Void) {
        Task {
            do {
                try await AppleScriptHelper.executeVoid(script)
            } catch {
                await onFailure()
            }
        }
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptString(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

/// Comment lancer Claude Code sans passer par la fonction `claude` interactive.
enum ShellRunner {
    /// Résolu une fois au démarrage : `_claude_run` si le shell la définit,
    /// sinon le binaire installé.
    nonisolated(unsafe) private(set) static var claude: String = fallback

    private static var fallback: String {
        let local = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude").path
        return FileManager.default.isExecutableFile(atPath: local) ? ClaudeLauncher.shellQuote(local) : "command claude"
    }

    static func resolve() {
        Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-ic", "whence -w _claude_run"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return }

            // Un .zshrc peut bloquer : on n'attend pas plus de 5 s.
            let deadline = Date().addingTimeInterval(5)
            while process.isRunning && Date() < deadline {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if process.isRunning { process.terminate(); return }

            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            if output.contains("_claude_run: function") {
                claude = "_claude_run"
            }
        }
    }
}
