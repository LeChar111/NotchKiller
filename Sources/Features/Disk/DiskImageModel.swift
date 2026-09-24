import AppKit
import Foundation

/// Montage d'une image disque APFS posée sur un disque externe.
///
/// Un SSD livré en exFAT sur schéma MBR ne peut pas porter de volume APFS natif :
/// macOS ne sait pas redimensionner l'exFAT pour libérer une partition. Un
/// sparsebundle APFS posé dessus sert alors d'espace d'installation, à rattacher
/// après chaque branchement ; ce modèle offre ce geste à la main.
///
/// Désactivé tant qu'aucune image n'est déclarée :
///   defaults write io.github.lechar111.notchkiller disk.imagePath /Volumes/SSD/Apps.sparsebundle
/// Le volume monté porte le nom du fichier, sans extension.
@MainActor
@Observable
final class DiskImageModel {
    static let shared = DiskImageModel()

    /// Pas d'écran de réglage : une seule image, déclarée une fois pour toutes.
    static let imagePath = UserDefaults.standard.string(forKey: "disk.imagePath") ?? ""
    static let volumeName = URL(fileURLWithPath: imagePath).deletingPathExtension().lastPathComponent
    static let volumePath = "/Volumes/\(volumeName)"

    static var isConfigured: Bool { !imagePath.isEmpty }

    enum State {
        case unplugged  // le disque hôte n'est pas branché
        case detached   // image présente, volume non monté
        case mounted    // volume disponible
    }

    private(set) var state: State = .unplugged
    private(set) var isBusy = false
    private(set) var freeSpace: Double?
    private(set) var lastError: String?

    private init() {
        guard Self.isConfigured else { return }
        // Le volume peut être monté ou éjecté depuis le Finder, ou par un
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
        case .unplugged: "Disque non branché"
        case .detached:  "Monter \(Self.volumeName)"
        case .mounted:   "\(Self.volumeName) monté"
        }
    }

    var subtitle: String {
        if let lastError { return lastError }
        switch state {
        case .unplugged: return "branchez le SSD pour y installer"
        case .detached:  return "image APFS sur le disque externe"
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
        guard Self.isConfigured else { return }
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
