import AppKit
import ApplicationServices

/// Signale l'ouverture et la fermeture de Mission Control, pour que le panneau
/// s'efface en fondu au lieu de disparaître d'un coup.
///
/// Aucune API publique ne l'annonce : c'est le Dock qui pilote Mission Control
/// et qui publie des notifications d'accessibilité à chaque entrée et sortie.
/// Les écouter exige l'autorisation Accessibilité ; sans elle, le panneau
/// reste en `.transient` et macOS le masque lui-même, sans animation.
@MainActor
final class MissionControlWatcher {
    static let shared = MissionControlWatcher()

    /// `true` à l'entrée dans Mission Control, `false` à la sortie.
    var onChange: ((Bool) -> Void)?

    private(set) var isActive = false
    private var observer: AXObserver?

    nonisolated private static let enterNotifications = [
        "AXExposeShowAllWindows",
        "AXExposeShowFrontWindows",
        "AXExposeShowDesktop",
    ]
    nonisolated private static let exitNotification = "AXExposeExit"

    private init() {
        // Le Dock redémarre (mise à jour, `killall Dock`) : l'observateur
        // attaché à l'ancien processus ne reçoit plus rien.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == "com.apple.dock" else { return }
            Task { @MainActor in MissionControlWatcher.shared.attach() }
        }
    }

    /// Le fondu n'est possible que si l'on reçoit les notifications du Dock.
    var canAnimate: Bool { AXIsProcessTrusted() }

    func start() {
        guard observer == nil else { return }
        attach()
    }

    private func attach() {
        detach()
        guard canAnimate,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return }

        let callback: AXObserverCallback = { _, _, name, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<MissionControlWatcher>.fromOpaque(refcon).takeUnretainedValue()
            let entering = name as String != MissionControlWatcher.exitNotification
            MainActor.assumeIsolated { watcher.set(active: entering) }
        }

        var created: AXObserver?
        guard AXObserverCreate(dock.processIdentifier, callback, &created) == .success, let created else { return }

        let element = AXUIElementCreateApplication(dock.processIdentifier)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.enterNotifications + [Self.exitNotification] {
            AXObserverAddNotification(created, element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)

        observer = created
    }

    private func detach() {
        guard let observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = nil
        set(active: false)
    }

    private func set(active: Bool) {
        guard active != isActive else { return }
        isActive = active
        onChange?(active)
    }
}
