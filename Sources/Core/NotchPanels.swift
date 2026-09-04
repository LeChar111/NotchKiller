import AppKit

/// Coordonne un gestionnaire par écran et route les événements souris vers
/// celui qui est concerné. Les moniteurs globaux sont installés une seule fois,
/// quel que soit le nombre de moniteurs branchés.
@MainActor
@Observable
final class NotchPanels {
    static let shared = NotchPanels()

    private(set) var managers: [NotchPanelManager] = []
    private var monitors: [EventMonitor] = []

    private init() {}

    /// Le gestionnaire de l'écran principal — celui que visent le menu et les
    /// raccourcis quand aucun écran n'est désigné.
    var primary: NotchPanelManager { managers.first ?? NotchPanelManager.shared }

    func reset(with list: [NotchPanelManager]) {
        managers = list
        installMonitorsIfNeeded()
    }

    func collapseAll() {
        for manager in managers { manager.collapse() }
    }

    private func installMonitorsIfNeeded() {
        guard monitors.isEmpty else { return }

        let down = EventMonitor(mask: .leftMouseDown) { _ in
            Self.onMain { NotchPanels.shared.managers.forEach { $0.handleMouseDown() } }
        }

        let moved = EventMonitor(mask: [.mouseMoved, .leftMouseDragged]) { _ in
            guard UserDefaults.standard.object(forKey: "panel.hoverPeek") as? Bool ?? true else { return }
            Self.onMain { NotchPanels.shared.managers.forEach { $0.handleMouseMoved() } }
        }

        let scroll = EventMonitor(mask: .scrollWheel) { event in
            guard UserDefaults.standard.object(forKey: "panel.swipeGestures") as? Bool ?? true else { return }
            Self.onMain { NotchPanels.shared.managers.forEach { $0.handleScroll(event) } }
        }

        monitors = [down, moved, scroll]
        monitors.forEach { $0.start() }
    }

    /// Les blocs de `NSEvent` arrivent sur le thread principal : on évite le
    /// détour par une `Task` à chaque mouvement de souris.
    private nonisolated static func onMain(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { body() }
        } else {
            Task { @MainActor in body() }
        }
    }
}
