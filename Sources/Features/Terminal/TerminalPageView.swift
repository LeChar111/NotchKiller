import SwiftUI

/// Terminal minimal : on exécute une commande dans le répertoire d'un projet
/// et on lit sa sortie sans changer de fenêtre. Ce n'est pas un émulateur —
/// pas de TTY, pas d'interactivité — et c'est dit dans l'interface.
@MainActor
@Observable
final class MiniTerminal {
    static let shared = MiniTerminal()

    var command = ""
    private(set) var output = ""
    private(set) var isRunning = false
    private(set) var exitCode: Int32?
    private(set) var workingDirectory: String

    private var task: Process?

    private init() {
        if Demo.isActive {
            workingDirectory = "\(Demo.home)/Projects/aurora-web"
            command = "git status -sb"
            output = "## feat/dark-pricing...origin/feat/dark-pricing [ahead 2]\n M src/pages/Pricing.tsx\n M src/styles/tokens.css\n?? src/styles/dark.css\n"
            exitCode = 0
            return
        }
        workingDirectory = AppSettings.shared.projectRoots.first
            .map { ($0 as NSString).expandingTildeInPath }
            ?? FileManager.default.homeDirectoryForCurrentUser.path
    }

    var directoryLabel: String {
        workingDirectory.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
            .replacingOccurrences(of: Demo.home, with: "~")
    }

    func setDirectory(_ path: String) {
        workingDirectory = path
        output = ""
        exitCode = nil
    }

    func run() {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning else { return }

        isRunning = true
        output = ""
        exitCode = nil

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // -l charge le profil : sans lui, ni node, ni git, ni brew dans le PATH.
        process.arguments = ["-lc", trimmed]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        task = process

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                MiniTerminal.shared.append(text)
            }
        }

        process.terminationHandler = { finished in
            Task { @MainActor in
                pipe.fileHandleForReading.readabilityHandler = nil
                MiniTerminal.shared.finish(finished.terminationStatus)
            }
        }

        do { try process.run() } catch {
            append("Impossible de lancer la commande.\n")
            finish(-1)
        }
    }

    func stop() {
        task?.terminate()
    }

    private func append(_ text: String) {
        output += text
        // 40 000 signes suffisent à lire une sortie ; au-delà on coupe le début.
        if output.count > 40_000 {
            output = String(output.suffix(40_000))
        }
    }

    private func finish(_ status: Int32) {
        isRunning = false
        exitCode = status
        task = nil
    }
}

struct TerminalPageView: View {
    var terminal: MiniTerminal = .shared
    var dev: DevModel = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            input
            transcript
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
        .onAppear { dev.refresh() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            SectionLabel("Répertoire")
            Menu {
                ForEach(dev.projects.prefix(12)) { project in
                    Button(project.name) { terminal.setDirectory(project.path) }
                }
            } label: {
                Text(terminal.directoryLabel)
                    .font(NK.mono(10))
                    .foregroundStyle(NK.t2)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: 300, alignment: .leading)

            Spacer(minLength: 0)

            if let code = terminal.exitCode {
                Text(code == 0 ? "code 0" : "code \(code)")
                    .font(NK.mono(9.5))
                    .foregroundStyle(code == 0 ? NK.ok : NK.bad)
            }
        }
    }

    private var input: some View {
        HStack(spacing: 8) {
            Text("$")
                .font(NK.mono(12))
                .foregroundStyle(NK.accent)

            TextField("npm run build", text: Binding(
                get: { terminal.command },
                set: { terminal.command = $0 }
            ))
            .textFieldStyle(.plain)
            .font(NK.mono(11.5))
            .foregroundStyle(NK.t1)
            .onSubmit { terminal.run() }

            Button { terminal.isRunning ? terminal.stop() : terminal.run() } label: {
                Text(terminal.isRunning ? "Arrêter" : "Exécuter")
                    .font(NK.ui(10.5, .semibold))
                    .foregroundStyle(terminal.isRunning ? NK.bad : NK.accent)
                    .padding(.horizontal, 11)
                    .frame(height: 24)
                    .background(Capsule().fill((terminal.isRunning ? NK.bad : NK.accent).opacity(0.14)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: NK.radiusControl, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NK.radiusControl, style: .continuous)
                .stroke(NK.line, lineWidth: 1)
        )
    }

    private var transcript: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(terminal.output.isEmpty
                 ? "Sortie standard et erreur, exécutées par zsh -lc.\nPas de TTY : les commandes interactives ne fonctionneront pas."
                 : terminal.output)
                .font(NK.mono(10, .regular))
                .foregroundStyle(terminal.output.isEmpty ? NK.t4 : NK.t2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(height: 190)
        .background(
            RoundedRectangle(cornerRadius: NK.radiusCard, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NK.radiusCard, style: .continuous)
                .stroke(NK.line, lineWidth: 1)
        )
    }
}
