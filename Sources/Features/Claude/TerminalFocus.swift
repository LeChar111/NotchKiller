import AppKit

/// Ramène au terminal qui héberge une session Claude Code.
/// Le hook remonte la chaîne des processus parents ; on active la première
/// application réelle qu'on y trouve (Terminal, iTerm, Ghostty, Cursor…).
enum TerminalFocus {
    @discardableResult
    static func focus(ancestors: [Int]) -> Bool {
        let apps = ancestors.compactMap { NSRunningApplication(processIdentifier: pid_t($0)) }

        if let regular = apps.first(where: { $0.activationPolicy == .regular }) {
            regular.activate()
            return true
        }
        if let any = apps.first(where: { $0.bundleURL != nil }) {
            any.activate()
            return true
        }
        return false
    }

    /// Nom de l'app hôte, pour libeller le bouton avec ce que l'utilisateur va voir.
    static func hostName(ancestors: [Int]) -> String? {
        ancestors
            .compactMap { NSRunningApplication(processIdentifier: pid_t($0)) }
            .first { $0.activationPolicy == .regular }?
            .localizedName
    }
}
