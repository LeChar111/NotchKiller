import AppKit
import UniformTypeIdentifiers

@MainActor
@Observable
final class ShelfModel {
    static let shared = ShelfModel()

    var items: [ShelfItem] = [] {
        didSet { save() }
    }

    var isEmpty: Bool { items.isEmpty }
    var isDropTargeted: Bool = false

    private let persistenceURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("NotchKiller", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("shelf.json")
    }()

    private init() {
        load()
    }

    // MARK: - Add

    func add(_ newItems: [ShelfItem]) {
        var merged = items
        let existingPaths = Set(merged.map(\.displayName))
        for item in newItems where !existingPaths.contains(item.displayName) {
            merged.append(item)
        }
        items = merged
    }

    func addFile(_ url: URL) {
        add([ShelfItem(kind: .file(path: url.path))])
    }

    // MARK: - Partage, compression

    /// AirDrop, Messages, Mail : le sélecteur système les expose tous d'un coup,
    /// et suit la liste des services installés sans qu'on la maintienne.
    func share(_ item: ShelfItem, from view: NSView?) {
        let payload: Any
        switch item.kind {
        case .file(let path): payload = URL(fileURLWithPath: path)
        case .link(let url):  payload = url
        case .text(let text): payload = text
        }

        let picker = NSSharingServicePicker(items: [payload])
        guard let anchor = view ?? NSApp.keyWindow?.contentView else { return }
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    /// Compresse en zip à côté de la source, puis ajoute l'archive à l'étagère.
    func compress(_ item: ShelfItem) {
        guard case .file(let path) = item.kind else { return }
        let source = URL(fileURLWithPath: path)
        let archive = source.deletingPathExtension().appendingPathExtension("zip")

        Task.detached(priority: .userInitiated) {
            guard let ditto = Shell.locate("ditto") else { return }
            _ = Shell.run(ditto, ["-c", "-k", "--sequesterRsrc", "--keepParent",
                                  source.path, archive.path], timeout: 120)
            await MainActor.run {
                guard FileManager.default.fileExists(atPath: archive.path) else { return }
                self.addFile(archive)
            }
        }
    }

    func quickLook(_ item: ShelfItem) {
        guard case .file(let path) = item.kind else { return }
        guard let qlmanage = Shell.locate("qlmanage") else { return }
        Task.detached(priority: .userInitiated) {
            _ = Shell.run(qlmanage, ["-p", path], timeout: 120)
        }
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
    }

    func removeAll() {
        items.removeAll()
    }

    // MARK: - Drop handling

    func handleDrop(providers: [NSItemProvider]) {
        Task {
            var newItems: [ShelfItem] = []

            for provider in providers {
                if let item = await processProvider(provider) {
                    newItems.append(item)
                }
            }

            await MainActor.run {
                self.add(newItems)
            }
        }
    }

    private func processProvider(_ provider: NSItemProvider) async -> ShelfItem? {
        // Try file URL
        if let url = await loadURL(from: provider, type: .fileURL), url.isFileURL {
            return ShelfItem(kind: .file(path: url.path))
        }

        // Try web URL
        if let url = await loadURL(from: provider, type: .url), !url.isFileURL {
            return ShelfItem(kind: .link(url: url))
        }

        // Try text
        if let text = await loadText(from: provider) {
            // Check if it's a URL
            if let url = URL(string: text), url.scheme != nil, !url.isFileURL {
                return ShelfItem(kind: .link(url: url))
            }
            return ShelfItem(kind: .text(string: text))
        }

        return nil
    }

    private func loadURL(from provider: NSItemProvider, type: UTType) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.utf8PlainText.identifier) { item, _ in
                if let string = item as? String {
                    continuation.resume(returning: string)
                } else if let data = item as? Data {
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Persistence

    private func save() {
        Task.detached { [items, persistenceURL] in
            try? JSONEncoder().encode(items).write(to: persistenceURL)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: persistenceURL),
              let loaded = try? JSONDecoder().decode([ShelfItem].self, from: data) else { return }
        // Filter out missing files
        items = loaded.filter { item in
            if case .file(let path) = item.kind {
                return FileManager.default.fileExists(atPath: path)
            }
            return true
        }
    }
}
