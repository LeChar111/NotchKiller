import AppKit

final class NotchPanel: NSPanel {
    init(frame: CGRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        // Sans ceci, dès que le curseur entre dans l'encoche l'événement vise
        // notre fenêtre, qui ne le reçoit pas — et le moniteur global l'ignore
        // puisqu'il exclut nos propres événements. Le survol ne se déclenche jamais.
        acceptsMouseMovedEvents = true

        level = .mainMenu + 3
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            NotificationCenter.default.post(name: .notchShouldCollapse, object: nil)
        }
    }
}
