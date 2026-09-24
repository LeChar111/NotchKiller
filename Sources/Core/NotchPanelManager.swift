import AppKit

enum NotchConstants {
    /// Marge réellement visible entre le contenu et le bord noir.
    static let expandedInset: CGFloat = 20
    /// `NotchShape` rentre ses flancs de `topCornerRadius` : sans compensation,
    /// le padding demandé disparaît sous la découpe et le contenu colle au bord.
    static let expandedShapeInset: CGFloat = 19
    /// Padding à appliquer pour obtenir `expandedInset` à l'écran.
    static let expandedPanelPadding: CGFloat = expandedShapeInset + expandedInset
    /// Largeur utile offerte aux pages.
    static let expandedContentWidth: CGFloat = 720
    /// Largeur totale de la zone noire déployée.
    static let expandedPanelWidth: CGFloat = expandedContentWidth + expandedPanelPadding * 2
    static let expandedPanelHorizontalPadding: CGFloat = 0
    /// Bornes verticales : la hauteur réelle est dictée par le contenu de la page.
    static let minExpandedContentHeight: CGFloat = 118
    static let maxExpandedContentHeight: CGFloat = 380
    /// Hauteur de la fenêtre hôte : doit couvrir le pire cas (notch + barre + contenu max).
    static let windowHeight: CGFloat = 560
    /// De combien le bandeau fermé descend sous l'encoche au survol.
    static let hoverLift: CGFloat = 8
}

@MainActor
@Observable
final class NotchPanelManager {
    static let shared = NotchPanelManager()

    private(set) var isExpanded = false
    private(set) var isPinned = false
    private(set) var notchSize: CGSize = .zero
    private(set) var notchRect: CGRect = .zero
    private(set) var panelRect: CGRect = .zero
    /// Tiroir sous le bandeau fermé (résumé de fin de discussion) : il agrandit
    /// la zone active tant qu'il est affiché.
    private(set) var drawerRect: CGRect = .zero
    var showsDrawer = false {
        didSet {
            guard !showsDrawer else { return }
            drawerRect = .zero
            BarActivities.shared.hold(false)
        }
    }

    /// Zone cliquable de l'encoche fermée, tiroir compris.
    var collapsedRect: CGRect {
        drawerRect.isEmpty ? notchRect : notchRect.union(drawerRect)
    }
    private var screenFrame: CGRect = .zero

    private var hoverExitTask: Task<Void, Never>?
    private var lastGesture = Date.distantPast
    private var scrollX: CGFloat = 0
    private var scrollY: CGFloat = 0
    private var lastScrollAt = Date.distantPast

    /// Le survol ne fait qu'enrichir le bandeau : c'est le clic qui ouvre.
    private(set) var isHovering = false

    /// Un gestionnaire par écran : la géométrie, l'état d'ouverture et le
    /// survol sont propres à chaque moniteur.
    init() {}

    func updateGeometry(for screen: NSScreen) {
        let newNotchSize = screen.notchSize
        screenFrame = screen.frame

        notchSize = newNotchSize

        let notchCenterX = screenFrame.origin.x + screenFrame.width / 2
        let sideWidth = max(0, newNotchSize.height - 12) + 24
        let notchTotalWidth = newNotchSize.width + sideWidth

        notchRect = CGRect(
            x: notchCenterX - notchTotalWidth / 2,
            y: screenFrame.maxY - newNotchSize.height,
            width: notchTotalWidth,
            height: newNotchSize.height
        )

        // Valeur de départ, remplacée dès que SwiftUI mesure le panneau réel.
        panelRect = CGRect(
            x: notchCenterX - (NotchConstants.expandedPanelWidth + NotchConstants.expandedPanelHorizontalPadding) / 2,
            y: screenFrame.maxY - (newNotchSize.height + NotchConstants.minExpandedContentHeight),
            width: NotchConstants.expandedPanelWidth + NotchConstants.expandedPanelHorizontalPadding,
            height: newNotchSize.height + NotchConstants.minExpandedContentHeight
        )
    }

    /// Recalcule la zone active (hit-test / clic extérieur) à partir de la taille
    /// réellement rendue par SwiftUI : la hauteur du panneau et la largeur du
    /// bandeau fermé suivent toutes deux leur contenu.
    func updateMeasuredSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0, screenFrame.width > 0 else { return }

        let notchCenterX = screenFrame.origin.x + screenFrame.width / 2
        let newRect = CGRect(
            x: notchCenterX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )

        if isExpanded {
            guard newRect != panelRect else { return }
            panelRect = newRect
        } else if showsDrawer {
            let ceiling = notchSize.height + NotchConstants.hoverLift + 4
            if size.height > ceiling { drawerRect = newRect }
        } else {
            // Pendant l'animation de repli, la mesure passe par des tailles
            // intermédiaires : on n'accepte que celles d'un vrai bandeau.
            let ceiling = notchSize.height + NotchConstants.hoverLift + 4
            guard size.height <= ceiling, newRect != notchRect else { return }
            notchRect = newRect
        }
    }

    /// Gestes sur la zone de l'encoche : balayage horizontal pour faire défiler
    /// les activités du bandeau, vertical pour ouvrir ou refermer.
    func handleScroll(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        let zone = isExpanded ? panelRect : notchRect.insetBy(dx: -6, dy: -6)
        guard zone.contains(location) else {
            scrollX = 0
            scrollY = 0
            return
        }

        // Un trackpad envoie des dizaines d'événements de 1 à 3 px : tester
        // un événement isolé contre un seuil ne déclenche jamais rien. On
        // cumule, et un silence de 250 ms marque la fin du geste.
        if Date().timeIntervalSince(lastScrollAt) > 0.25 {
            scrollX = 0
            scrollY = 0
        }
        lastScrollAt = Date()
        scrollX += event.scrollingDeltaX
        scrollY += event.scrollingDeltaY

        guard Date().timeIntervalSince(lastGesture) > 0.45 else { return }

        // Une molette envoie des crans de ±1, un trackpad des pixels.
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 24 : 2

        if abs(scrollX) > abs(scrollY), abs(scrollX) > threshold {
            guard !isExpanded else { return }
            lastGesture = Date()
            let forward = scrollX < 0
            scrollX = 0
            scrollY = 0
            BarActivities.shared.advance(forward ? 1 : -1)
        } else if abs(scrollY) > threshold {
            lastGesture = Date()
            let down = scrollY > 0
            scrollX = 0
            scrollY = 0
            if down && !isExpanded {
                expand()
            } else if !down && isExpanded && !isPinned {
                collapse()
            }
        }
    }

    func handleMouseMoved() {
        guard !isExpanded else {
            setHovering(false)
            return
        }

        // Marge de 4 pt : sans elle, le bandeau clignote quand la souris longe
        // exactement sa bordure.
        let inside = notchRect.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
        if showsDrawer {
            BarActivities.shared.hold(collapsedRect.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation))
        }

        if inside {
            hoverExitTask?.cancel()
            hoverExitTask = nil
            setHovering(true)
        } else if isHovering, hoverExitTask == nil {
            hoverExitTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled, let self else { return }
                self.hoverExitTask = nil
                guard !self.notchRect.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) else { return }
                self.setHovering(false)
            }
        }
    }

    private func setHovering(_ value: Bool) {
        guard isHovering != value else { return }
        isHovering = value
    }

    func handleMouseDown() {
        let location = NSEvent.mouseLocation

        if isExpanded {
            if !isPinned && !panelRect.contains(location) {
                collapse()
            }
        } else {
            if notchRect.contains(location) {
                expand()
            }
        }
    }

    func expand() {
        guard !isExpanded else { return }
        hoverExitTask?.cancel()
        hoverExitTask = nil
        isHovering = false
        isExpanded = true
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        isPinned = false
    }

    func toggle() {
        if isExpanded {
            collapse()
        } else {
            expand()
        }
    }

    func togglePin() {
        isPinned.toggle()
    }
}
