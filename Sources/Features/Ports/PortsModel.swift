import AppKit

struct ListeningPort: Identifiable, Equatable {
    var id: String { "\(port)-\(pid)" }
    let port: Int
    let pid: Int32
    let process: String
    let isOwned: Bool

    /// Ports que les outils de dev occupent le plus souvent.
    var isCommonDevPort: Bool {
        [3000, 3001, 4000, 5000, 5173, 5432, 6379, 8000, 8080, 8081, 9000, 27017].contains(port)
    }
}

@MainActor
@Observable
final class PortsModel {
    static let shared = PortsModel()

    private(set) var ports: [ListeningPort] = []
    private(set) var isRefreshing = false
    private(set) var lastAction: String?

    private var timer: Timer?
    private var subscribers = 0

    private init() {}

    func subscribe() {
        subscribers += 1
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        timer?.tolerance = 0.8
    }

    func unsubscribe() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        if Demo.isActive { loadDemo(); return }
        guard !isRefreshing else { return }
        isRefreshing = true
        let uid = getuid()

        Task.detached(priority: .utility) {
            let found = Self.snapshot(uid: uid)
            await MainActor.run {
                self.ports = found
                self.isRefreshing = false
            }
        }
    }

    /// `lsof` en mode champs : une ligne par attribut, préfixée par sa lettre.
    /// Sans sudo il ne montre que nos propres processus, ce qui est exactement
    /// le périmètre qu'on s'autorise à fermer.
    private nonisolated static func snapshot(uid: uid_t) -> [ListeningPort] {
        guard let lsof = Shell.locate("lsof"),
              let output = Shell.run(lsof, ["-iTCP", "-sTCP:LISTEN", "-P", "-n", "-FpcnL"]) else { return [] }

        var results: [Int: ListeningPort] = [:]
        var pid: Int32 = 0
        var command = ""
        var login = ""

        for line in output.split(separator: "\n") {
            guard let marker = line.first else { continue }
            let value = String(line.dropFirst())

            switch marker {
            case "p": pid = Int32(value) ?? 0
            case "c": command = value
            case "L": login = value
            case "n":
                guard let separator = value.lastIndex(of: ":"),
                      let port = Int(value[value.index(after: separator)...]) else { continue }
                let owned = login == NSUserName()
                // Un même service écoute souvent en IPv4 et IPv6 : une seule ligne.
                if results[port] == nil {
                    results[port] = ListeningPort(port: port, pid: pid, process: command, isOwned: owned)
                }
            default:
                break
            }
        }

        return results.values.sorted { lhs, rhs in
            if lhs.isCommonDevPort != rhs.isCommonDevPort { return lhs.isCommonDevPort }
            return lhs.port < rhs.port
        }
    }

    /// Fermeture douce d'abord : `terminate()` laisse l'app enregistrer,
    /// `SIGTERM` laisse un serveur fermer ses connexions.
    func release(_ entry: ListeningPort) {
        guard entry.isOwned else {
            lastAction = "Port \(entry.port) — processus système, non touché"
            return
        }

        let closed: Bool
        if let app = NSRunningApplication(processIdentifier: entry.pid) {
            closed = app.terminate()
        } else {
            closed = kill(entry.pid, SIGTERM) == 0
        }

        lastAction = closed
            ? "Port \(entry.port) — \(entry.process) arrêté"
            : "Port \(entry.port) — refus (\(entry.process))"

        Task {
            try? await Task.sleep(for: .milliseconds(800))
            refresh()
        }
    }
}

// MARK: - Démo

extension PortsModel {
    func loadDemo() {
        ports = [
            ListeningPort(port: 3000, pid: 48211, process: "node", isOwned: true),
            ListeningPort(port: 5173, pid: 48302, process: "vite", isOwned: true),
            ListeningPort(port: 5432, pid: 812, process: "postgres", isOwned: true),
            ListeningPort(port: 6379, pid: 845, process: "redis-server", isOwned: true),
            ListeningPort(port: 8080, pid: 51007, process: "python3", isOwned: true),
        ]
    }
}
