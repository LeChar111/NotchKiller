import AppKit

struct ClipEntry: Identifiable, Equatable {
    let id: UUID
    let text: String
    let kind: ClipKind
    let capturedAt: Date
    var isPinned: Bool

    var preview: String {
        text.split(separator: "\n", omittingEmptySubsequences: true).first
            .map { String($0.prefix(120)) } ?? text
    }

    var lineCount: Int {
        text.split(separator: "\n", omittingEmptySubsequences: false).count
    }
}

enum ClipKind: String, Equatable {
    case swift, javascript, python, shell, json, html, css, sql, url, text

    var label: String {
        switch self {
        case .swift:      "Swift"
        case .javascript: "JS / TS"
        case .python:     "Python"
        case .shell:      "Shell"
        case .json:       "JSON"
        case .html:       "HTML"
        case .css:        "CSS"
        case .sql:        "SQL"
        case .url:        "Lien"
        case .text:       "Texte"
        }
    }

    var isCode: Bool { self != .text && self != .url }
}

@MainActor
@Observable
final class ClipboardModel {
    static let shared = ClipboardModel()

    private(set) var entries: [ClipEntry] = []
    private(set) var isWatching = false
    private(set) var lastAction: String?

    private var changeCount = NSPasteboard.general.changeCount
    private var poller: Timer?
    private static let limit = 40

    private init() {}

    /// L'historique reste en mémoire : rien n'est écrit sur disque, et il part
    /// avec l'app. Un presse-papiers persistant est un dépôt de secrets.
    func start() {
        if Demo.isActive { loadDemo(); return }
        guard poller == nil else { return }
        isWatching = true
        poller = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.capture() }
        }
        poller?.tolerance = 0.3
    }

    func stop() {
        poller?.invalidate()
        poller = nil
        isWatching = false
    }

    private func capture() {
        let board = NSPasteboard.general
        guard board.changeCount != changeCount else { return }
        changeCount = board.changeCount

        // Les gestionnaires de mots de passe marquent leur contenu : on n'y touche pas.
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        guard board.data(forType: concealed) == nil else { return }
        guard board.data(forType: .init("org.nspasteboard.TransientType")) == nil else { return }

        guard let text = board.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        guard entries.first(where: { !$0.isPinned })?.text != text else { return }

        entries.removeAll { $0.text == text && !$0.isPinned }
        entries.insert(
            ClipEntry(id: UUID(), text: text, kind: Self.detect(text), capturedAt: Date(), isPinned: false),
            at: 0
        )

        let pinnedCount = entries.filter(\.isPinned).count
        while entries.count > Self.limit + pinnedCount {
            guard let index = entries.lastIndex(where: { !$0.isPinned }) else { break }
            entries.remove(at: index)
        }
    }

    // MARK: Actions

    func copy(_ entry: ClipEntry) {
        changeCount = NSPasteboard.general.changeCount + 1
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        lastAction = "Copié · \(entry.kind.label)"
    }

    func togglePin(_ entry: ClipEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isPinned.toggle()
        entries.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.capturedAt > rhs.capturedAt
        }
    }

    func remove(_ entry: ClipEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    func clear() {
        entries.removeAll { !$0.isPinned }
        lastAction = "Historique vidé"
    }

    // MARK: Détection de langage

    /// Heuristique volontairement grossière : elle sert à étiqueter une ligne
    /// dans une liste, pas à colorer un éditeur.
    nonisolated static func detect(_ text: String) -> ClipKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"),
           !trimmed.contains(" ") { return .url }

        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
            || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")),
           trimmed.contains("\":") || trimmed.contains("\": ") { return .json }

        if trimmed.hasPrefix("<") && (trimmed.contains("</") || trimmed.contains("/>")) { return .html }

        let lower = trimmed.lowercased()
        if lower.hasPrefix("select ") || lower.hasPrefix("insert into ")
            || lower.hasPrefix("update ") || lower.hasPrefix("create table ") { return .sql }

        if trimmed.contains("func ") && (trimmed.contains("let ") || trimmed.contains("var ")) { return .swift }
        if trimmed.contains("import SwiftUI") || trimmed.contains("@State") { return .swift }
        if trimmed.contains("def ") && trimmed.contains(":") { return .python }
        if trimmed.contains("const ") || trimmed.contains("=>") || trimmed.contains("function ") { return .javascript }
        if trimmed.hasPrefix("#!") || trimmed.hasPrefix("$ ")
            || trimmed.hasPrefix("git ") || trimmed.hasPrefix("npm ")
            || trimmed.hasPrefix("cd ") || trimmed.hasPrefix("sudo ") { return .shell }
        if trimmed.contains("{") && trimmed.contains(";") && trimmed.contains(":")
            && !trimmed.contains("(") { return .css }

        return .text
    }
}

// MARK: - Démo

extension ClipboardModel {
    func loadDemo() {
        guard entries.isEmpty else { return }
        let samples = [
            "npm run build && npm run preview",
            "https://github.com/LeChar111/NotchKiller",
            "func greet(_ name: String) -> String {\n    \"Bonjour, \\(name) !\"\n}",
            "{ \"theme\": \"dark\", \"accent\": \"#7C5CFF\" }",
            "SELECT id, email FROM users WHERE created_at > now() - interval '7 days';",
            "Merci pour la relecture, je pousse la correction ce soir.",
        ]
        entries = samples.enumerated().map { index, text in
            ClipEntry(id: UUID(), text: text, kind: Self.detect(text),
                      capturedAt: Demo.ago(Double(index) * 420 + 30), isPinned: index == 1)
        }
    }
}
