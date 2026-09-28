import AppKit

/// Intensité choisie dans les réglages. macOS n'expose pas d'amplitude : on
/// joue sur le motif (du cran d'alignement au choc générique) et sur une
/// seconde impulsion pour le niveau fort.
enum HapticLevel: Int, CaseIterable, Identifiable {
    case off, light, medium, strong

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .off:    "Désactivé"
        case .light:  "Léger"
        case .medium: "Moyen"
        case .strong: "Fort"
        }
    }
}

/// Retour haptique du trackpad Force Touch. Il n'est ressenti que doigt posé :
/// on le réserve aux gestes et aux clics, jamais aux événements spontanés.
@MainActor
enum Haptics {
    enum Kind {
        /// Cran léger : un onglet, une activité, un seuil franchi en cours de geste.
        case tick
        /// Changement d'état franc : ouvrir, refermer, épingler.
        case snap
        /// Retour neutre : chasser un élément, un geste refusé.
        case thud
    }

    static func play(_ kind: Kind, level: HapticLevel? = nil) {
        switch level ?? AppSettings.shared.hapticLevel {
        case .off:
            return
        case .light:
            perform(.alignment)
        case .medium:
            switch kind {
            case .tick: perform(.alignment)
            case .snap: perform(.levelChange)
            case .thud: perform(.generic)
            }
        case .strong:
            switch kind {
            case .tick:
                perform(.levelChange)
            case .snap, .thud:
                perform(kind == .snap ? .levelChange : .generic)
                Task {
                    try? await Task.sleep(for: .milliseconds(45))
                    perform(.generic)
                }
            }
        }
    }

    private static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
