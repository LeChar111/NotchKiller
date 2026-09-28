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
    /// Hauteur de la ligne des sous-pages, sous l'encoche du panneau ouvert.
    static let navRailHeight: CGFloat = 28
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
    /// Un geste ne déclenche qu'une action : l'inertie du trackpad prolonge
    /// le défilement bien après le lever des doigts.
    private var gestureHandled = false

    /// Balayage horizontal sur le panneau ouvert : la vue avance d'une page
    /// dans le sens indiqué à chaque incrément du compteur.
    private(set) var pageSwipe = (count: 0, delta: 0)
    /// Étirement élastique de l'encoche pendant un geste vertical, de -1 à 1 :
    /// positif vers le bas (ouvrir), négatif vers le haut (refermer, chasser).
    private(set) var stretch: CGFloat = 0
    /// Glissement horizontal du contenu pendant un balayage, de -1 à 1.
    private(set) var nudge: CGFloat = 0
    private var settleTask: Task<Void, Never>?

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
    /// les activités du bandeau (ou les pages du panneau ouvert), vertical pour
    /// ouvrir ou refermer — ou chasser le tiroir de fin de discussion.
    func handleScroll(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        let zone = isExpanded ? panelRect : collapsedRect.insetBy(dx: -6, dy: -6)
        guard zone.contains(location) else {
            resetScroll()
            return
        }

        // Un trackpad envoie des dizaines d'événements de 1 à 3 px : tester
        // un événement isolé contre un seuil ne déclenche jamais rien. On
        // cumule, et un nouveau contact ou un silence de 250 ms marque la fin
        // du geste.
        if event.phase == .began || Date().timeIntervalSince(lastScrollAt) > 0.25 {
            resetScroll()
        }
        lastScrollAt = Date()
        scheduleSettle()

        // Doigts levés : l'encoche relâche l'étirement. L'inertie qui suit
        // peut encore faire aboutir un geste lancé, mais n'étire plus rien.
        if event.phase == .ended || event.phase == .cancelled {
            settle()
            return
        }
        let fingersDown = event.momentumPhase.isEmpty
        guard !gestureHandled else { return }
        scrollX += event.scrollingDeltaX
        scrollY += event.scrollingDeltaY

        guard Date().timeIntervalSince(lastGesture) > 0.45 else { return }

        // Une molette envoie des crans de ±1, un trackpad des pixels.
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 34 : 2

        // Panneau ouvert, le défilement vertical appartient aux listes :
        // seul le bandeau du haut (encoche + sous-pages) replie le panneau.
        let navBand = notchSize.height + NotchConstants.navRailHeight
        let verticalAllowed = !isExpanded || location.y >= panelRect.maxY - navBand

        if abs(scrollX) > abs(scrollY) {
            stretch = 0
            let progress = max(-1, min(1, scrollX / threshold))
            if fingersDown { follow(nudge: progress) }
            guard abs(scrollX) > threshold else { return }
            let forward = scrollX < 0
            markGestureHandled()
            Haptics.play(.tick)
            if isExpanded {
                pageSwipe = (pageSwipe.count + 1, forward ? 1 : -1)
            } else {
                BarActivities.shared.advance(forward ? 1 : -1)
            }
        } else if verticalAllowed {
            nudge = 0
            let down = scrollY > 0
            let action: VerticalAction? = switch (down, isExpanded) {
            case (true, false):                  .expand
            case (false, false) where showsDrawer: .dismissDrawer
            case (false, true) where !isPinned:  .collapse
            default:                             nil
            }
            // Épinglé, le panneau résiste : il cède à peine et ne se ferme pas.
            let reach: CGFloat = action == nil ? 0.25 : 1
            if fingersDown { follow(stretch: min(reach, abs(scrollY) / threshold) * (down ? 1 : -1)) }
            guard abs(scrollY) > threshold else { return }
            markGestureHandled()
            switch action {
            case .expand:
                Haptics.play(.snap)
                expand()
            case .collapse:
                Haptics.play(.snap)
                collapse()
            case .dismissDrawer:
                Haptics.play(.thud)
                BarActivities.shared.dismissTransient()
                ClaudeSessionStore.shared.clearFinishedNotice()
            case nil:
                Haptics.play(.thud)
            }
        }
    }

    private enum VerticalAction { case expand, collapse, dismissDrawer }

    /// Étirement suivi au doigt ; un cran haptique marque la mi-course pour
    /// annoncer que le geste va aboutir.
    private func follow(stretch value: CGFloat) {
        if abs(value) >= 0.5, abs(stretch) < 0.5 { Haptics.play(.tick) }
        stretch = value
    }

    private func follow(nudge value: CGFloat) {
        if abs(value) >= 0.5, abs(nudge) < 0.5 { Haptics.play(.tick) }
        nudge = value
    }

    private func settle() {
        if stretch != 0 { stretch = 0 }
        if nudge != 0 { nudge = 0 }
    }

    /// Une molette n'envoie pas de fin de geste : le silence en tient lieu.
    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            self?.settle()
        }
    }

    private func resetScroll() {
        scrollX = 0
        scrollY = 0
        gestureHandled = false
        settle()
    }

    private func markGestureHandled() {
        lastGesture = Date()
        scrollX = 0
        scrollY = 0
        gestureHandled = true
        settle()
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
        if value { Haptics.play(.tick) }
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
        Haptics.play(.snap)
    }
}
