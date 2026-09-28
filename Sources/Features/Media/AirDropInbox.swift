import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

struct AirDropFile: Identifiable, Equatable {
    var id: String { url.path }
    let url: URL
    let receivedAt: Date
    let size: Int64
    /// Nom de l'appareil émetteur, quand le système l'a noté.
    let sender: String?

    var name: String { url.lastPathComponent }
}

/// Fichiers reçus par AirDrop. Le système les dépose dans Téléchargements en
/// les marquant d'une quarantaine dont l'agent est `sharingd` : c'est la seule
/// trace fiable, AirDrop ne tient pas d'historique consultable.
@MainActor
@Observable
final class AirDropInbox {
    static let shared = AirDropInbox()

    private(set) var files: [AirDropFile] = []
    private(set) var thumbnails: [String: NSImage] = [:]
    private(set) var receptionMode: ReceptionMode = .unknown
    private(set) var hasScanned = false

    enum ReceptionMode {
        case off, contactsOnly, everyone, unknown

        var label: String {
            switch self {
            case .off:          "Réception désactivée"
            case .contactsOnly: "Contacts uniquement"
            case .everyone:     "Tout le monde"
            case .unknown:      "Réception inconnue"
            }
        }
    }

    nonisolated private static let limit = 8
    private let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    private var watcher: DispatchSourceFileSystemObject?
    private var rescanTask: Task<Void, Never>?

    private init() {
        if Demo.isActive { loadDemo() }
    }

    // MARK: Surveillance

    /// Lire Téléchargements déclenche la demande d'accès de macOS : on attend
    /// que la page Média s'affiche plutôt que de le faire au lancement.
    func activate() {
        guard !Demo.isActive else { return }
        readReceptionMode()
        guard watcher == nil else { return }
        scan()
        watch()
    }

    private func watch() {
        let descriptor = Darwin.open(downloads.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.scheduleScan() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    /// Un transfert AirDrop écrit le fichier par morceaux : on laisse passer
    /// la rafale d'événements avant de relire.
    private func scheduleScan() {
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.scan()
        }
    }

    func scan() {
        let folder = downloads
        Task.detached(priority: .utility) {
            let found = Self.collect(in: folder)
            await MainActor.run {
                self.hasScanned = true
                guard found != self.files else { return }
                self.files = found
                self.loadThumbnails()
            }
        }
    }

    nonisolated private static func collect(in folder: URL) -> [AirDropFile] {
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .creationDateKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }

        let received = entries.compactMap { url -> AirDropFile? in
            guard quarantineAgent(of: url) == "sharingd" else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            return AirDropFile(
                url: url,
                receivedAt: values?.addedToDirectoryDate ?? values?.creationDate ?? .distantPast,
                size: Int64(values?.fileSize ?? values?.totalFileAllocatedSize ?? 0),
                sender: whereFrom(of: url)
            )
        }
        return Array(received.sorted { $0.receivedAt > $1.receivedAt }.prefix(limit))
    }

    /// `drapeaux;horodatage;agent;identifiant` — l'agent nomme le processus
    /// qui a déposé le fichier.
    nonisolated private static func quarantineAgent(of url: URL) -> String? {
        guard let data = extendedAttribute("com.apple.quarantine", of: url),
              let value = String(data: data, encoding: .utf8) else { return nil }
        let fields = value.split(separator: ";", omittingEmptySubsequences: false)
        return fields.count > 2 ? String(fields[2]) : nil
    }

    nonisolated private static func whereFrom(of url: URL) -> String? {
        guard let data = extendedAttribute("com.apple.metadata:kMDItemWhereFroms", of: url),
              let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String]
        else { return nil }
        return list.first { !$0.isEmpty && !$0.contains("://") }
    }

    nonisolated private static func extendedAttribute(_ name: String, of url: URL) -> Data? {
        url.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else { return nil }
            let length = getxattr(path, name, nil, 0, 0, 0)
            guard length > 0 else { return nil }
            var data = Data(count: length)
            let read = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, length, 0, 0) }
            return read > 0 ? data : nil
        }
    }

    // MARK: Mode de réception

    private func readReceptionMode() {
        let value = CFPreferencesCopyAppValue("DiscoverableMode" as CFString, "com.apple.sharingd" as CFString) as? String
        receptionMode = switch value?.lowercased() {
        case "off":                      .off
        case "contacts only":            .contactsOnly
        case .some(let v) where v.hasPrefix("everyone"): .everyone
        default:                         .unknown
        }
    }

    // MARK: Vignettes

    private func loadThumbnails() {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        for file in files where thumbnails[file.id] == nil {
            let request = QLThumbnailGenerator.Request(
                fileAt: file.url, size: CGSize(width: 30, height: 30), scale: scale, representationTypes: .all)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                guard let image = representation?.nsImage else { return }
                Task { @MainActor in self.thumbnails[file.id] = image }
            }
        }
    }

    func icon(for file: AirDropFile) -> NSImage {
        if let thumbnail = thumbnails[file.id] { return thumbnail }
        if FileManager.default.fileExists(atPath: file.url.path) {
            return NSWorkspace.shared.icon(forFile: file.url.path)
        }
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: file.url.pathExtension) ?? .data)
    }

    // MARK: Actions

    func open(_ file: AirDropFile) {
        NSWorkspace.shared.open(file.url)
    }

    func reveal(_ file: AirDropFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    func quickLook(_ file: AirDropFile) {
        guard let qlmanage = Shell.locate("qlmanage") else { return }
        let path = file.url.path
        Task.detached(priority: .userInitiated) {
            _ = Shell.run(qlmanage, ["-p", path], timeout: 120)
        }
    }

    func addToShelf(_ file: AirDropFile) {
        ShelfModel.shared.addFile(file.url)
    }

    /// La fenêtre AirDrop du Finder : c'est elle qui rend le Mac visible
    /// et permet de changer le mode de réception.
    func openAirDropWindow() {
        let app = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app")
        NSWorkspace.shared.openApplication(at: app, configuration: .init())
    }

    func openDownloads() {
        NSWorkspace.shared.open(downloads)
    }

    // MARK: Démo

    private func loadDemo() {
        let folder = URL(fileURLWithPath: "\(Demo.home)/Downloads")
        let now = Date()
        files = [
            AirDropFile(url: folder.appendingPathComponent("IMG_4821.HEIC"), receivedAt: now.addingTimeInterval(-240),
                        size: 2_400_000, sender: "iPhone de Camille"),
            AirDropFile(url: folder.appendingPathComponent("Maquette accueil.pdf"), receivedAt: now.addingTimeInterval(-3_600),
                        size: 860_000, sender: "MacBook Air"),
            AirDropFile(url: folder.appendingPathComponent("Note vocale.m4a"), receivedAt: now.addingTimeInterval(-26_000),
                        size: 1_100_000, sender: nil),
        ]
        receptionMode = .contactsOnly
        hasScanned = true
    }
}
