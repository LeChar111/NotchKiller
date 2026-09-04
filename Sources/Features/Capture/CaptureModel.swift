import AppKit

/// Captures d'écran et enregistrements. La CLI `screencapture` couvre l'image
/// et la vidéo sans dépendance ; le résultat atterrit dans l'Étagère, prêt à
/// être glissé ou envoyé.
@MainActor
@Observable
final class CaptureModel {
    static let shared = CaptureModel()

    private(set) var isRecording = false
    private(set) var lastAction: String?
    private var recorder: Process?

    private init() {}

    private var directory: URL {
        let base = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let folder = base.appendingPathComponent("NotchKiller")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func destination(_ ext: String) -> URL {
        let stamp = Self.stamp.string(from: Date())
        return directory.appendingPathComponent("Capture \(stamp).\(ext)")
    }

    // MARK: Image

    func captureSelection() { capture(arguments: ["-i"], label: "Sélection") }
    func captureWindow()    { capture(arguments: ["-iW"], label: "Fenêtre") }
    func captureScreen()    { capture(arguments: [], label: "Écran") }

    private func capture(arguments: [String], label: String) {
        guard let tool = Shell.locate("screencapture") else {
            lastAction = "screencapture introuvable"
            return
        }
        let url = destination("png")

        Task.detached(priority: .userInitiated) {
            _ = Shell.run(tool, arguments + ["-x", url.path], timeout: 120)
            await MainActor.run { self.collect(url, label: label) }
        }
    }

    // MARK: Vidéo

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard let tool = Shell.locate("screencapture") else { return }
        let url = destination("mov")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        // -v vidéo, -V 0 sans limite de durée : c'est nous qui arrêtons.
        task.arguments = ["-v", "-V", "0", url.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        task.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isRecording = false
                self?.recorder = nil
                self?.collect(url, label: "Enregistrement")
            }
        }

        do { try task.run() } catch {
            lastAction = "Enregistrement impossible"
            return
        }
        recorder = task
        isRecording = true
        lastAction = "Enregistrement en cours…"
    }

    private func stopRecording() {
        // SIGINT termine proprement le fichier ; SIGKILL le laisserait corrompu.
        recorder?.interrupt()
    }

    // MARK: Résultat

    private func collect(_ url: URL, label: String) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            lastAction = "\(label) — annulée"
            return
        }
        ShelfModel.shared.addFile(url)
        lastAction = "\(label) → Étagère"
    }

    func openMarkup(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "yyyy-MM-dd 'à' HH.mm.ss"
        return f
    }()
}
