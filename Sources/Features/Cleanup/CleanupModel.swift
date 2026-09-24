import AppKit

struct CleanupTarget: Identifiable, Equatable {
    var id: String { path }
    let path: String
    let name: String
    let detail: String
    let bytes: Double
    let group: CleanupGroup

    var displayPath: String {
        path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}

enum CleanupGroup: String, CaseIterable, Identifiable {
    case modules, caches, builds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .modules: "Dépendances"
        case .caches:  "Caches d'outils"
        case .builds:  "Artefacts de build"
        }
    }
}

@MainActor
@Observable
final class CleanupModel {
    static let shared = CleanupModel()

    private(set) var targets: [CleanupTarget] = []
    private(set) var isScanning = false
    private(set) var hasScanned = false
    private(set) var lastAction: String?

    var totalBytes: Double { targets.reduce(0) { $0 + $1.bytes } }

    private init() {
        if Demo.isActive { loadDemo() }
    }

    func scan() {
        if Demo.isActive { loadDemo(); return }
        guard !isScanning else { return }
        isScanning = true
        let roots = AppSettings.shared.projectRoots

        Task.detached(priority: .utility) {
            let found = Self.collect(roots: roots)
            await MainActor.run {
                self.targets = found
                self.isScanning = false
                self.hasScanned = true
            }
        }
    }

    func targets(in group: CleanupGroup) -> [CleanupTarget] {
        targets.filter { $0.group == group }.sorted { $0.bytes > $1.bytes }
    }

    /// Corbeille, jamais suppression : un `node_modules` se réinstalle, mais un
    /// chemin mal filtré ne se récupère pas. L'utilisateur garde la main.
    func trash(_ target: CleanupTarget) {
        let url = URL(fileURLWithPath: target.path)
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            targets.removeAll { $0.id == target.id }
            lastAction = "\(target.name) → corbeille · \(Shell.formatBytes(target.bytes))"
        } catch {
            lastAction = "\(target.name) — échec : \(error.localizedDescription)"
        }
    }

    func trashAll(in group: CleanupGroup) {
        let batch = targets(in: group)
        let freed = batch.reduce(0) { $0 + $1.bytes }
        for target in batch { trash(target) }
        lastAction = "\(batch.count) élément\(batch.count > 1 ? "s" : "") → corbeille · \(Shell.formatBytes(freed))"
    }

    // MARK: Collecte

    private nonisolated static func collect(roots: [String]) -> [CleanupTarget] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates: [(String, String, CleanupGroup)] = []

        // Dépendances : un niveau sous chaque racine de projets.
        for root in roots {
            let expanded = (root as NSString).expandingTildeInPath
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: expanded) else { continue }
            for entry in entries where !entry.hasPrefix(".") {
                for folder in ["node_modules", ".next", "dist", "build", "target", ".venv"] {
                    let path = "\(expanded)/\(entry)/\(folder)"
                    guard FileManager.default.fileExists(atPath: path) else { continue }
                    let group: CleanupGroup = folder == "node_modules" || folder == ".venv" ? .modules : .builds
                    candidates.append((path, "\(entry)/\(folder)", group))
                }
            }
        }

        // Caches d'outils : reconstruits tout seuls au prochain usage.
        let caches: [(String, String)] = [
            ("\(home)/.npm/_cacache", "Cache npm"),
            ("\(home)/Library/pnpm/store", "Store pnpm"),
            ("\(home)/Library/Caches/Yarn", "Cache Yarn"),
            ("\(home)/Library/Caches/pip", "Cache pip"),
            ("\(home)/Library/Caches/Homebrew", "Cache Homebrew"),
            ("\(home)/Library/Developer/Xcode/DerivedData", "DerivedData Xcode"),
            ("\(home)/Library/Caches/go-build", "Cache Go"),
            ("\(home)/.cargo/registry/cache", "Cache Cargo"),
        ]
        for (path, name) in caches where FileManager.default.fileExists(atPath: path) {
            candidates.append((path, name, name.contains("Xcode") ? .builds : .caches))
        }

        let sizes = Shell.diskUsage(of: candidates.map(\.0))

        return candidates.compactMap { path, name, group in
            guard let bytes = sizes[path], bytes > 16 * 1024 * 1024 else { return nil }
            return CleanupTarget(path: path, name: name,
                                 detail: Shell.formatBytes(bytes), bytes: bytes, group: group)
        }
        .sorted { $0.bytes > $1.bytes }
    }
}

// MARK: - Démo

extension CleanupModel {
    func loadDemo() {
        let gb = 1_073_741_824.0
        let root = "\(Demo.home)/Projects"
        targets = [
            CleanupTarget(path: "\(root)/aurora-web/node_modules", name: "aurora-web", detail: "node_modules", bytes: 1.4 * gb, group: .modules),
            CleanupTarget(path: "\(root)/atlas-docs/node_modules", name: "atlas-docs", detail: "node_modules", bytes: 0.9 * gb, group: .modules),
            CleanupTarget(path: "\(Demo.home)/Library/Caches/Homebrew", name: "Homebrew", detail: "cache", bytes: 2.1 * gb, group: .caches),
            CleanupTarget(path: "\(Demo.home)/Library/Developer/Xcode/DerivedData", name: "Xcode", detail: "DerivedData", bytes: 6.3 * gb, group: .builds),
            CleanupTarget(path: "\(root)/lumen-ios/build", name: "lumen-ios", detail: "build", bytes: 0.7 * gb, group: .builds),
        ]
        hasScanned = true
    }
}
