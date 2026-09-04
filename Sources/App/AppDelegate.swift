import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchPanels: [NotchPanel] = []
    private var statusItem: NSStatusItem?
    private var allScreensItem: NSMenuItem?
    private let windowHeight: CGFloat = NotchConstants.windowHeight

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AppSettings.shared          // enregistre le domaine de valeurs par défaut
        NSApplication.shared.setActivationPolicy(.accessory)
        rebuildNotchWindows()
        setupStatusItem()
        observeScreenChanges()
        startClaudeServices()
        startAmbientServices()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Claude Code

    /// Sources d'activité du bandeau : elles tournent en fond, indépendamment
    /// de la page affichée.
    @MainActor private func startAmbientServices() {
        BluetoothModel.shared.start()
        CalendarModel.shared.start()
        NotificationRelay.shared.start()
    }

    private func startClaudeServices() {
        HookInstaller.installIfNeeded()
        MCPInstaller.installIfNeeded()
        SocketServer.shared.start { event in
            Task { @MainActor in
                ClaudeStateMachine.shared.handleEvent(event)
            }
        }
    }

    // MARK: - Notch Window

    /// Une fenêtre et un gestionnaire par écran ciblé. Reconstruit à chaque
    /// changement de configuration d'affichage ou de réglage.
    @MainActor private func rebuildNotchWindows() {
        ScreenSelector.shared.refreshScreens()

        for panel in notchPanels { panel.orderOut(nil) }
        notchPanels.removeAll()

        var managers: [NotchPanelManager] = []

        for (index, screen) in ScreenSelector.shared.targetScreens.enumerated() {
            // L'écran principal garde l'instance partagée : c'est elle que
            // visent le menu et la notification de repli.
            let manager = index == 0 ? NotchPanelManager.shared : NotchPanelManager()
            manager.updateGeometry(for: screen)
            managers.append(manager)

            let panel = NotchPanel(frame: windowFrame(for: screen))
            let hostingView = NSHostingView(rootView: NotchContentView(panelManager: manager))

            let hitTestView = NotchHitTestView()
            hitTestView.panelManager = manager
            hitTestView.addSubview(hostingView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: hitTestView.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: hitTestView.bottomAnchor),
                hostingView.leadingAnchor.constraint(equalTo: hitTestView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: hitTestView.trailingAnchor),
            ])

            panel.contentView = hitTestView
            panel.orderFrontRegardless()
            notchPanels.append(panel)
        }

        NotchPanels.shared.reset(with: managers)
        updateScreensMenuItem()
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(repositionWindow),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Le panneau suit tous les bureaux (`canJoinAllSpaces`) : sans ceci il
        // resterait ouvert par-dessus le bureau vers lequel on vient de basculer.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensSettingChanged),
            name: .notchScreensChanged,
            object: nil
        )
    }

    @objc private func screensSettingChanged() {
        MainActor.assumeIsolated { rebuildNotchWindows() }
    }

    @objc private func activeSpaceChanged() {
        MainActor.assumeIsolated {
            NotchPanels.shared.collapseAll()
        }
    }

    @objc private func repositionWindow() {
        MainActor.assumeIsolated {
            rebuildNotchWindows()
        }
    }

    private func windowFrame(for screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        return NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.maxY - windowHeight,
            width: screenFrame.width,
            height: windowHeight
        )
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "capsule.portrait.tophalf.filled",
                accessibilityDescription: "NotchKiller"
            )
            button.imagePosition = .imageOnly
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Ouvrir le notch", action: #selector(openNotch), keyEquivalent: "o"))
        menu.addItem(.separator())

        let screensItem = NSMenuItem(
            title: "Afficher sur tous les écrans",
            action: #selector(toggleAllScreens),
            keyEquivalent: ""
        )
        menu.addItem(screensItem)
        allScreensItem = screensItem

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quitter", action: #selector(quitApp), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
        MainActor.assumeIsolated { updateScreensMenuItem() }
    }

    @objc private func toggleAllScreens() {
        MainActor.assumeIsolated {
            AppSettings.shared.showOnAllScreens.toggle()
        }
    }

    @MainActor private func updateScreensMenuItem() {
        guard let allScreensItem else { return }
        let enabled = AppSettings.shared.showOnAllScreens
        allScreensItem.state = enabled ? .on : .off

        let count = NSScreen.screens.count
        allScreensItem.toolTip = count > 1
            ? "\(count) écrans connectés"
            : "Un seul écran connecté pour l'instant"
    }

    @objc private func openNotch() {
        Task { @MainActor in
            NotchPanels.shared.primary.expand()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
