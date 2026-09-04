import AppKit

/// Suppression du HUD natif de macOS.
///
/// Il n'existe aucun réglage public pour le désactiver : `OSDUIHelper` est
/// relancé par le système à chaque appui sur une touche multimédia. On le
/// termine à chaque fois qu'on affiche le nôtre — c'est réversible, et il
/// revient de lui-même dès que l'option est coupée.
@MainActor
enum SystemHUD {
    private static var lastSuppression = Date.distantPast

    static func suppressNative() {
        guard AppSettings.shared.replaceSystemHUD else { return }
        // Inutile de relancer un processus plus de deux fois par seconde.
        guard Date().timeIntervalSince(lastSuppression) > 0.5 else { return }
        lastSuppression = Date()

        Task.detached(priority: .utility) {
            guard let killall = Shell.locate("killall") else { return }
            _ = Shell.run(killall, ["-9", "OSDUIHelper"], timeout: 2)
        }
    }
}
