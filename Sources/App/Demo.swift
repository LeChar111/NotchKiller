import AppKit
import SwiftUI

/// Mode démo : `NotchKiller --demo` remplace toutes les données personnelles
/// (agenda, sessions Claude, projets, presse-papiers, processus…) par un jeu
/// fictif et coupe les effets de bord (hooks Claude, serveur MCP, socket,
/// sauvegarde de l'étagère). Il sert aux captures du README.
///
/// Le panneau se pilote depuis le terminal par notification distribuée :
///   Tools/demo.sh open dev ports     — ouvre le panneau sur l'onglet et la sous-page
///   Tools/demo.sh close              — referme
///   Tools/demo.sh bar music          — fige le bandeau fermé (claude, music, calendar)
///   Tools/demo.sh done               — termine une session : tiroir « Claude a fini »
///
/// Les réglages (`UserDefaults`) restent ceux de l'app : `Tools/capture.sh`
/// les sauvegarde avant la séance et les restaure après.
enum Demo {
    static let isActive = CommandLine.arguments.contains("--demo")

    static let command = Notification.Name("io.github.lechar111.notchkiller.demo")

    /// Relais local vers `NotchContentView`, qui garde l'onglet dans son état.
    static let navigate = Notification.Name("notchDemoNavigate")

    static let home = "/Users/demo"

    @MainActor static func start() {
        guard isActive else { return }
        DistributedNotificationCenter.default().addObserver(
            forName: command, object: nil, queue: .main
        ) { note in
            let words = (note.object as? String ?? "").split(separator: " ").map(String.init)
            Task { @MainActor in handle(words) }
        }
        seedSessions()
    }

    @MainActor private static func handle(_ words: [String]) {
        let panel = NotchPanels.shared.primary
        switch words.first {
        case "open":
            NotificationCenter.default.post(
                name: navigate, object: nil,
                userInfo: ["tab": words.dropFirst().first ?? "home",
                           "subpage": words.dropFirst(2).first ?? ""])
            if !panel.isExpanded {
                panel.expand()
                if !panel.isPinned { panel.togglePin() }
            }
        case "close":
            panel.collapse()
        case "bar":
            if let activity = words.dropFirst().first.flatMap(BarActivity.init) {
                BarActivities.shared.pin(activity)
            }
        case "done":
            send(["session_id": "demo-aurora", "cwd": "\(home)/Projects/aurora-web",
                  "event": "Stop", "status": "waiting_for_input"])
        default:
            break
        }
    }

    // MARK: Sessions Claude

    @MainActor private static func seedSessions() {
        let aurora = "\(home)/Projects/aurora-web"
        let orbit = "\(home)/Projects/orbit-api"
        let lumen = "\(home)/Projects/lumen-ios"

        send(["session_id": "demo-aurora", "cwd": aurora, "event": "UserPromptSubmit",
              "status": "processing",
              "user_prompt": "Ajoute le mode sombre à la page de tarifs et vérifie le contraste"])
        send(["session_id": "demo-aurora", "cwd": aurora, "event": "Summary", "status": "processing",
              "summary": "Mode sombre de la page de tarifs",
              "summary_detail": "Jetons de couleur posés ; reste la vérification du contraste."])
        send(["session_id": "demo-aurora", "cwd": aurora, "event": "PreToolUse", "status": "processing",
              "tool": "Edit", "tool_use_id": "t1",
              "tool_input": ["file_path": "\(aurora)/src/pages/Pricing.tsx"]])

        send(["session_id": "demo-orbit", "cwd": orbit, "event": "UserPromptSubmit",
              "status": "processing", "user_prompt": "Pourquoi le test d'intégration des webhooks échoue ?"])
        send(["session_id": "demo-orbit", "cwd": orbit, "event": "Summary", "status": "processing",
              "summary": "Débogage des webhooks de paiement",
              "summary_detail": "La signature est calculée avant la normalisation du corps."])
        send(["session_id": "demo-orbit", "cwd": orbit, "event": "PreToolUse", "status": "processing",
              "tool": "Bash", "tool_use_id": "t2",
              "tool_input": ["command": "npm test -- webhooks"]])

        send(["session_id": "demo-lumen", "cwd": lumen, "event": "UserPromptSubmit",
              "status": "processing", "user_prompt": "Prépare la note de version 2.4"])
        send(["session_id": "demo-lumen", "cwd": lumen, "event": "Summary", "status": "processing",
              "summary": "Note de version 2.4 de Lumen"])
        send(["session_id": "demo-lumen", "cwd": lumen, "event": "PreToolUse", "status": "processing",
              "tool": "AskUserQuestion", "tool_use_id": "t3", "tool_input": [:]])
    }

    @MainActor private static func send(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let event = try? JSONDecoder().decode(HookEvent.self, from: data) else { return }
        ClaudeStateMachine.shared.handleEvent(event)
    }

    // MARK: Contenus

    static let noteText = """
    Sortie 2.4
    — relire la note de version
    — captures du mode sombre
    — prévenir l'équipe support vendredi
    """

    /// Pochette d'album dessinée : un dégradé, sans image sous droits.
    static func artwork() -> NSImage {
        NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
            let gradient = NSGradient(colors: [
                NSColor(red: 0.98, green: 0.45, blue: 0.35, alpha: 1),
                NSColor(red: 0.55, green: 0.25, blue: 0.85, alpha: 1),
                NSColor(red: 0.10, green: 0.15, blue: 0.45, alpha: 1),
            ])
            gradient?.draw(in: rect, angle: -55)
            NSColor.white.withAlphaComponent(0.85).setStroke()
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 90, dy: 90))
            ring.lineWidth = 6
            ring.stroke()
            return true
        }
    }

    static func ago(_ seconds: TimeInterval) -> Date { Date().addingTimeInterval(-seconds) }
}
