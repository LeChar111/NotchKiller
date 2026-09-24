import AppKit
import Foundation

/// Montage de l'image disque APFS posée sur le SSD Samsung T9.
///
/// Le T9 sort d'usine en exFAT sur schéma MBR : macOS refuse d'y créer un volume
/// APFS natif, et ne sait pas redimensionner l'exFAT pour libérer une partition.
/// L'espace d'installation est donc un sparsebundle APFS de 300 Go, qu'il faut
/// rattacher après chaque branchement. Le LaunchAgent com.example.disk.mount
/// s'en charge tout seul ; ce modèle offre le même geste à la main.
@MainActor
@Observable
final class DiskImageModel {
    static let shared = DiskImageModel()

    /// Constantes plutôt que réglages : il n'y a qu'une image, et son chemin est
    /// imposé par le nom du volume hôte.
    static let imagePath = "/Volumes/T9/T9-Apps.sparsebundle"
    static let volumePath = "/Volumes/T9-Apps"
    static let volumeName = "T9-Apps"

    enum State {
        case unplugged  // le T9 n'est pas branché
        case detached   // image présente, volume non monté
        case mounted    // volume disponible
    }

    private(set) var state: State = .unplugged
    private(set) var isBusy = false
    private(set) var freeSpace: Double?
    private(set) var lastError: String?

    private init() {
        // Le volume peut être monté ou éjecté depuis le Finder, ou par le
        // LaunchAgent : on suit les notifications plutôt que de sonder.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
        refresh()
    }

    // MARK: Libellés

    var title: String {
        switch state {
        case .unplugged: "T9 non branché"
        case .detached:  "Monter \(Self.volumeName)"
        case .mounted:   "\(Self.volumeName) monté"
        }
    }

    var subtitle: String {
        if let lastError { return lastError }
        switch state {
        case .unplugged: return "branchez le SSD pour y installer"
        case .detached:  return "300 Go APFS sur le T9"
        case .mounted:   return freeSpace.map { "\(Shell.formatBytes($0)) libres — cliquer pour éjecter" }
                             ?? "cliquer pour éjecter"
        }
    }

    var symbol: String {
        switch state {
        case .unplugged: "externaldrive.badge.xmark"
        case .detached:  "externaldrive.badge.plus"
        case .mounted:   "externaldrive.fill.badge.checkmark"
        }
    }

    // MARK: Actions

    func toggle() {
        guard !isBusy else { return }
        switch state {
        case .unplugged: refresh()
        case .detached:  attach()
        case .mounted:   detach()
        }
    }

    func revealInFinder() {
        guard state == .mounted else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: Self.volumePath))
    }

    func refresh() {
        let fm = FileManager.default
        if fm.fileExists(atPath: Self.volumePath) {
            state = .mounted
            freeSpace = Self.availableCapacity(at: Self.volumePath)
        } else if fm.fileExists(atPath: Self.imagePath) {
            state = .detached
            freeSpace = nil
        } else {
            state = .unplugged
            freeSpace = nil
        }
    }

    private func attach() {
        run(["attach", Self.imagePath, "-quiet"], expecting: .mounted, failure: "montage impossible")
    }

    private func detach() {
        run(["detach", Self.volumePath], expecting: .detached, failure: "éjection impossible")
    }

    /// `Shell.run` ne remonte pas le code de sortie : on constate le résultat sur
    /// le disque plutôt que de faire confiance à la sortie de `hdiutil`.
    private func run(_ arguments: [String], expecting expected: State, failure: String) {
        guard let hdiutil = Shell.locate("hdiutil") else {
            lastError = "hdiutil introuvable"
            return
        }
        isBusy = true
        lastError = nil

        Task {
            _ = await Task.detached { Shell.run(hdiutil, arguments, timeout: 60) }.value
            self.isBusy = false
            self.refresh()
            if self.state != expected { self.lastError = failure }
        }
    }

    private static func availableCapacity(at path: String) -> Double? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let bytes = values.volumeAvailableCapacity
        else { return nil }
        return Double(bytes)
    }
}
