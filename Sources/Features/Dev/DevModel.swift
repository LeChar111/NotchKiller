import AppKit
import UniformTypeIdentifiers

struct DevEditor: Identifiable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let url: URL
}

struct DevProject: Identifiable, Equatable {
    var id: String { path }
    let path: String
    let name: String
    let branch: String?
    let lastUsed: Date
    let isFavorite: Bool

    var displayPath: String {
        path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}

@MainActor
@Observable
final class DevModel {
    static let shared = DevModel()

    private(set) var editors: [DevEditor] = []
    private(set) var projects: [DevProject] = []
    private(set) var lastAction: String?
    /// État du lancement d'Overleaf local (nil = jamais lancé depuis l'ouverture).
    private(set) var overleafStatus: String?
    private(set) var overleafBusy = false

    /// Éditeurs reconnus, du plus spécifique au plus générique.
    private static let knownEditors: [(String, String)] = [
        ("com.todesktop.230313mzl4w4u92", "Cursor"),
        ("com.microsoft.VSCode", "VS Code"),
        ("com.microsoft.VSCodeInsiders", "VS Code Insiders"),
        ("com.exafunction.windsurf", "Windsurf"),
        ("dev.zed.Zed", "Zed"),
        ("com.sublimetext.4", "Sublime Text"),
        ("com.jetbrains.WebStorm", "WebStorm"),
        ("com.apple.dt.Xcode", "Xcode"),
    ]

    private init() {}

    var defaultEditor: DevEditor? {
        let stored = AppSettings.shared.defaultEditorBundleID
        return editors.first { $0.bundleID == stored } ?? editors.first
    }

    func refresh() {
        editors = Self.knownEditors.compactMap { bundleID, name in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
            return DevEditor(bundleID: bundleID, name: name, url: url)
        }

        let favorites = Set(AppSettings.shared.favoriteProjects)
        let roots = AppSettings.shared.projectRoots

        Task.detached(priority: .utility) {
            let found = Self.discover(roots: roots, favorites: favorites)
            await MainActor.run { self.projects = found }
        }
    }

    // MARK: Découverte

    /// Deux sources : les dépôts présents sous les racines configurées, et les
    /// projets que Claude Code a déjà ouverts (`~/.claude.json`) — c'est le
    /// meilleur signal de « récemment travaillé » qu'on ait sans rien indexer.
    private nonisolated static func discover(roots: [String], favorites: Set<String>) -> [DevProject] {
        var paths = Set<String>()

        for root in roots {
            let expanded = (root as NSString).expandingTildeInPath
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: expanded) else { continue }
            for entry in entries where !entry.hasPrefix(".") {
                let candidate = "\(expanded)/\(entry)"
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }
                paths.insert(candidate)
            }
        }

        // Les projets connus de Claude Code sont un bon signal de récence, mais
        // certains vivent dans ~/Downloads ou ~/Desktop : y toucher déclenche une
        // demande d'accès que rien ne justifie ici. On ne garde que ce qui est
        // sous une racine configurée, ou explicitement mis en favori.
        let expandedRoots = roots.map { ($0 as NSString).expandingTildeInPath + "/" }
        paths.formUnion(claudeProjects().filter { path in
            expandedRoots.contains { path.hasPrefix($0) } || favorites.contains(path)
        })
        paths.formUnion(favorites)

        let projects = paths.compactMap { path -> DevProject? in
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            let attributes = try? FileManager.default.attributesOfItem(atPath: "\(path)/.git")
            let fallback = try? FileManager.default.attributesOfItem(atPath: path)
            let modified = (attributes?[.modificationDate] as? Date)
                ?? (fallback?[.modificationDate] as? Date)
                ?? .distantPast

            return DevProject(
                path: path,
                name: (path as NSString).lastPathComponent,
                branch: branch(at: path),
                lastUsed: modified,
                isFavorite: favorites.contains(path)
            )
        }

        return projects.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            return lhs.lastUsed > rhs.lastUsed
        }
    }

    private nonisolated static func claudeProjects() -> [String] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projects = json["projects"] as? [String: Any] else { return [] }
        return projects.keys.filter { $0.hasPrefix("/") }
    }

    /// Lecture directe de `.git/HEAD` : instantané, là où `git rev-parse`
    /// coûterait un processus par dépôt à chaque rafraîchissement.
    private nonisolated static func branch(at path: String) -> String? {
        let head = "\(path)/.git/HEAD"
        guard let content = try? String(contentsOfFile: head, encoding: .utf8) else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("ref: refs/heads/") else {
            return trimmed.isEmpty ? nil : String(trimmed.prefix(7))
        }
        return String(trimmed.dropFirst("ref: refs/heads/".count))
    }

    // MARK: Actions

    func launch(_ editor: DevEditor) {
        NSWorkspace.shared.openApplication(at: editor.url, configuration: NSWorkspace.OpenConfiguration())
        lastAction = "\(editor.name) — ouvert"
    }

    func open(_ project: DevProject) {
        guard let editor = defaultEditor else {
            lastAction = "Aucun éditeur installé"
            return
        }
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: project.path)],
            withApplicationAt: editor.url,
            configuration: NSWorkspace.OpenConfiguration()
        )
        lastAction = "\(project.name) — \(editor.name)"
    }

    func openInTerminal(_ project: DevProject) {
        _ = ActionLauncher.openTerminal(at: project.path)
        lastAction = "\(project.name) — terminal"
    }

    func revealInFinder(_ project: DevProject) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
    }

    // MARK: Overleaf local

    /// Script du toolkit Overleaf : démarre Docker Desktop si besoin, lance les
    /// conteneurs, attend le serveur puis ouvre l'onglet. Il écrit une ligne
    /// « STATUT: … » ou « ERREUR: … » par étape, affichée telle quelle.
    /// Dossier du toolkit, surchargeable par
    /// `defaults write io.github.lechar111.notchkiller dev.overleafToolkit <chemin>`.
    static let overleafToolkit: URL = {
        if let path = UserDefaults.standard.string(forKey: "dev.overleafToolkit"), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Projects/overleaf-toolkit")
    }()

    static let overleafScript = overleafToolkit.appendingPathComponent("overleaf-launch.sh").path

    static let overleafImportScript = overleafToolkit.appendingPathComponent("overleaf-import.sh").path

    var overleafInstalled: Bool { FileManager.default.isExecutableFile(atPath: Self.overleafScript) }

    func launchOverleaf() {
        runOverleaf(script: Self.overleafScript, arguments: [], label: "Lancement…", done: "ouvert")
    }

    /// Choisit des dossiers ou des zips (y compris l'export global d'overleaf.com)
    /// et les importe comme nouveaux projets, puis ouvre la liste des projets.
    func importIntoOverleaf() {
        guard !overleafBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Importer dans Overleaf local"
        panel.prompt = "Importer"
        panel.message = "Un dossier devient un projet ; un zip d'export overleaf.com donne un projet par zip interne."
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.zip, .folder]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        runOverleaf(script: Self.overleafImportScript, arguments: panel.urls.map(\.path), label: "Import…", done: "importé")
    }

    private func runOverleaf(script: String, arguments: [String], label: String, done: String) {
        guard !overleafBusy else { return }
        guard FileManager.default.isExecutableFile(atPath: script) else {
            overleafStatus = "Toolkit introuvable"
            return
        }
        overleafBusy = true
        overleafStatus = label

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let lines = text.split(separator: "\n").map(String.init)
            Task { @MainActor in
                for line in lines {
                    if line.hasPrefix("STATUT: ") { self.overleafStatus = String(line.dropFirst(8)).capitalizedFirst }
                    else if line.hasPrefix("ERREUR: ") { self.overleafStatus = String(line.dropFirst(8)).capitalizedFirst }
                }
            }
        }
        process.terminationHandler = { finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            let ok = finished.terminationStatus == 0
            Task { @MainActor in
                self.overleafBusy = false
                if !ok, self.overleafStatus == nil || self.overleafStatus == label {
                    self.overleafStatus = "Échec"
                }
                self.lastAction = ok ? "Overleaf local — \(done)" : "Overleaf local — échec"
            }
        }

        do {
            try process.run()
        } catch {
            overleafBusy = false
            overleafStatus = "Impossible de lancer le script"
        }
    }

    func setDefaultEditor(_ editor: DevEditor) {
        AppSettings.shared.defaultEditorBundleID = editor.bundleID
        lastAction = "\(editor.name) — éditeur par défaut"
    }

    func toggleFavorite(_ project: DevProject) {
        var favorites = AppSettings.shared.favoriteProjects
        if let index = favorites.firstIndex(of: project.path) {
            favorites.remove(at: index)
        } else {
            favorites.append(project.path)
        }
        AppSettings.shared.favoriteProjects = favorites
        refresh()
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
