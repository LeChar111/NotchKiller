import Foundation

struct DockerContainer: Identifiable, Equatable {
    let id: String
    let name: String
    let image: String
    let state: String
    let status: String

    var isRunning: Bool { state == "running" }

    var stateLabel: String {
        switch state {
        case "running":    "En cours"
        case "exited":     "Arrêté"
        case "paused":     "En pause"
        case "restarting": "Redémarre"
        case "created":    "Créé"
        default:           state.capitalized
        }
    }
}

@MainActor
@Observable
final class DockerModel {
    static let shared = DockerModel()

    private(set) var containers: [DockerContainer] = []
    private(set) var isAvailable = true
    private(set) var isRefreshing = false
    private(set) var lastAction: String?
    private(set) var busyID: String?

    private var timer: Timer?
    private var subscribers = 0

    private init() {}

    nonisolated static var binaryPath: String? {
        Shell.locate("docker", extra: ["/Applications/Docker.app/Contents/Resources/bin/docker"])
    }

    func subscribe() {
        subscribers += 1
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        timer?.tolerance = 1
    }

    func unsubscribe() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task.detached(priority: .utility) {
            guard let docker = Self.binaryPath else {
                await MainActor.run {
                    self.isAvailable = false
                    self.isRefreshing = false
                }
                return
            }

            let raw = Shell.run(docker, [
                "ps", "-a", "--no-trunc",
                "--format", "{{.ID}}\u{1F}{{.Names}}\u{1F}{{.State}}\u{1F}{{.Status}}\u{1F}{{.Image}}",
            ], timeout: 6)

            let parsed = Self.parse(raw ?? "")
            await MainActor.run {
                self.isAvailable = raw != nil
                self.containers = parsed
                self.isRefreshing = false
            }
        }
    }

    private nonisolated static func parse(_ raw: String) -> [DockerContainer] {
        raw.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 5 else { return nil }
            return DockerContainer(id: String(parts[0].prefix(12)), name: parts[1],
                                   image: parts[4], state: parts[2], status: parts[3])
        }
        .sorted { lhs, rhs in
            if lhs.isRunning != rhs.isRunning { return lhs.isRunning }
            return lhs.name < rhs.name
        }
    }

    func toggle(_ container: DockerContainer) {
        command(container.isRunning ? "stop" : "start", on: container)
    }

    func restart(_ container: DockerContainer) {
        command("restart", on: container)
    }

    private func command(_ verb: String, on container: DockerContainer) {
        guard let docker = Self.binaryPath else { return }
        busyID = container.id
        let name = container.name

        Task.detached(priority: .userInitiated) {
            // `stop` attend l'arrêt propre du conteneur : la marge est large exprès.
            _ = Shell.run(docker, [verb, container.id], timeout: 25)
            await MainActor.run {
                self.busyID = nil
                self.lastAction = "\(name) — \(verb)"
                self.refresh()
            }
        }
    }
}
