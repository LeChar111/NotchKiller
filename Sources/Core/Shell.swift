import Foundation

/// Exécution d'outils en ligne de commande. Les processus lancés depuis une app
/// n'héritent pas du PATH d'un shell de connexion : on résout les binaires nous-mêmes.
enum Shell {
    @discardableResult
    nonisolated static func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval = 8) -> String? {
        guard FileManager.default.isExecutableFile(atPath: launchPath) else { return nil }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do { try task.run() } catch { return nil }

        let deadline = Date().addingTimeInterval(timeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        while task.isRunning && Date() < deadline { usleep(20_000) }
        if task.isRunning { task.terminate() }

        return String(data: data, encoding: .utf8)
    }

    /// Premier chemin exécutable parmi les emplacements usuels.
    nonisolated static func locate(_ name: String, extra: [String] = []) -> String? {
        let candidates = extra + [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)",
            "/sbin/\(name)",
            "/usr/sbin/\(name)",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Taille sur disque en octets, via `du` — bien plus rapide qu'un parcours Foundation.
    nonisolated static func diskUsage(of paths: [String]) -> [String: Double] {
        guard !paths.isEmpty, let du = locate("du") else { return [:] }
        guard let output = run(du, ["-sk"] + paths, timeout: 40) else { return [:] }

        var sizes: [String: Double] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let kilobytes = Double(parts[0]) else { continue }
            sizes[String(parts[1])] = kilobytes * 1024
        }
        return sizes
    }

    nonisolated static func formatBytes(_ value: Double) -> String {
        if value >= 1_073_741_824 { return String(format: "%.1f Go", value / 1_073_741_824) }
        if value >= 1_048_576 { return String(format: "%.0f Mo", value / 1_048_576) }
        return String(format: "%.0f Ko", value / 1024)
    }
}
