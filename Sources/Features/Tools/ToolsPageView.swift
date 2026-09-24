import SwiftUI

enum ToolAction: String, CaseIterable, Identifiable {
    case finder, activity, terminal, console, settings, lock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .finder:   "Finder"
        case .activity: "Moniteur d\u{2019}activité"
        case .terminal: "Terminal"
        case .console:  "Console"
        case .settings: "Réglages système"
        case .lock:     "Verrouiller l\u{2019}écran"
        }
    }

    var symbol: String {
        switch self {
        case .finder:   "folder"
        case .activity: "waveform.path.ecg"
        case .terminal: "apple.terminal"
        case .console:  "list.bullet.rectangle"
        case .settings: "gearshape"
        case .lock:     "lock.shield"
        }
    }

    var target: String {
        switch self {
        case .finder:   "Finder"
        case .activity: "Activity Monitor"
        case .terminal: "Terminal"
        case .console:  "Console"
        case .settings: "System Settings"
        case .lock:     "loginwindow"
        }
    }
}

struct ToolsPageView: View {
    var capture: CaptureModel = .shared
    var awake: AwakeModel = .shared
    var disk: DiskImageModel = .shared

    @State private var feedback: (text: String, ok: Bool)?
    @State private var runningApps: [NSRunningApplication] = []

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: NK.sectionGap) {
                captureBlock
                actionsGrid
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: NK.sectionGap) {
                awakeBlock
                diskBlock
                switcherBlock
            }
            .frame(width: 268, alignment: .topLeading)
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
        .onAppear { refreshApps(); disk.refresh() }
    }

    // MARK: Capture

    private var captureBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                SectionLabel("Capture")
                Spacer(minLength: 0)
                if let action = capture.lastAction {
                    Text(action)
                        .font(NK.ui(9.5, .medium))
                        .foregroundStyle(NK.t4)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 8) {
                captureButton("Sélection", "viewfinder") { capture.captureSelection() }
                captureButton("Fenêtre", "macwindow") { capture.captureWindow() }
                captureButton("Écran", "rectangle.inset.filled") { capture.captureScreen() }
                captureButton(capture.isRecording ? "Arrêter" : "Vidéo",
                              capture.isRecording ? "stop.fill" : "record.circle",
                              tint: capture.isRecording ? NK.bad : NK.t2) {
                    capture.toggleRecording()
                }
            }

            Text("Le fichier atterrit dans l'Étagère, prêt à être glissé ou envoyé.")
                .font(NK.ui(9.5, .medium))
                .foregroundStyle(NK.t4)
        }
    }

    private func captureButton(_ title: String, _ icon: String, tint: Color = NK.t2,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)
                Text(title)
                    .font(NK.ui(10, .semibold))
                    .foregroundStyle(NK.t2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(NK.surface)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private var actionsGrid: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("Actions rapides")

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ToolAction.allCases) { action in
                    Button { run(action) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: action.symbol)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(NK.t2)
                                .frame(width: 15)
                            Text(action.title)
                                .font(NK.ui(11, .semibold))
                                .foregroundStyle(NK.t1)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(NK.surface)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if let feedback {
                HStack(spacing: 8) {
                    Circle().fill(feedback.ok ? NK.ok : NK.bad).frame(width: 5, height: 5)
                    Text(feedback.text)
                        .font(NK.ui(10.5, .medium))
                        .foregroundStyle(NK.t3)
                }
            }
        }
    }

    // MARK: Veille

    private var awakeBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("Veille")
            Button { awake.toggle() } label: {
                HStack(spacing: 9) {
                    Image(systemName: awake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .font(.system(size: 13, weight: .medium))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(awake.isActive ? "Veille suspendue" : "Empêcher la veille")
                            .font(NK.ui(11.5, .semibold))
                        Text(awake.isActive ? "depuis \(awake.durationLabel)" : "l'écran ne s'éteindra plus")
                            .font(NK.ui(9.5, .medium))
                            .foregroundStyle(NK.t4)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(awake.isActive ? NK.warn : NK.t2)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(awake.isActive ? NK.warn.opacity(0.12) : NK.surface)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Bascule d'application

    /// Le T9 ne peut pas porter de partition APFS native : l'espace
    /// d'installation est une image disque, à monter après chaque branchement.
    /// Le LaunchAgent le fait tout seul ; ce bouton sert à forcer le geste, et
    /// surtout à éjecter proprement avant de débrancher le SSD.
    private var diskBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                SectionLabel("Disque externe")
                Spacer(minLength: 0)
                if disk.state == .mounted {
                    Button { disk.revealInFinder() } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(NK.t4)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Ouvrir dans le Finder")
                }
            }

            Button { disk.toggle() } label: {
                HStack(spacing: 9) {
                    Group {
                        if disk.isBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: disk.symbol)
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                    .frame(width: 17)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(disk.title)
                            .font(NK.ui(11.5, .semibold))
                        Text(disk.subtitle)
                            .font(NK.ui(9.5, .medium))
                            .foregroundStyle(disk.lastError == nil ? NK.t4 : NK.bad)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(diskTint)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(disk.state == .mounted ? NK.ok.opacity(0.12) : NK.surface)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(disk.isBusy)
        }
    }

    private var diskTint: Color {
        switch disk.state {
        case .unplugged: NK.t3
        case .detached:  NK.t2
        case .mounted:   NK.ok
        }
    }

    private var switcherBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                SectionLabel("Applications ouvertes")
                Spacer(minLength: 0)
                Button { refreshApps() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(NK.t4)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 38), spacing: 8)], spacing: 8) {
                ForEach(runningApps, id: \.processIdentifier) { app in
                    Button { app.activate() } label: {
                        Image(nsImage: app.icon ?? NSImage())
                            .resizable()
                            .frame(width: 30, height: 30)
                            .opacity(app.isActive ? 1 : 0.75)
                    }
                    .buttonStyle(.plain)
                    .help(app.localizedName ?? "")
                }
            }
        }
    }

    private func refreshApps() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func run(_ action: ToolAction) {
        let ok: Bool
        switch action {
        case .finder:   ok = ActionLauncher.openFinder()
        case .activity: ok = ActionLauncher.openActivityMonitor()
        case .terminal: ok = ActionLauncher.openTerminal()
        case .console:  ok = ActionLauncher.openConsole()
        case .settings: ok = ActionLauncher.openSystemSettings()
        case .lock:     ok = ActionLauncher.lockScreen()
        }
        feedback = (ok ? "\(action.title) — ouvert" : "\(action.title) — échec", ok)
    }
}

enum ActionLauncher {
    static func openMusic() -> Bool {
        openBundleID("com.apple.Music")
    }

    static func openSpotify() -> Bool {
        openBundleID("com.spotify.client") || openURL("https://open.spotify.com")
    }

    static func openYouTube() -> Bool {
        openURL("https://www.youtube.com")
    }

    static func openFinder() -> Bool {
        openBundleID("com.apple.finder")
    }

    static func openActivityMonitor() -> Bool {
        openBundleID("com.apple.ActivityMonitor")
    }

    static func openConsole() -> Bool {
        openBundleID("com.apple.Console")
    }

    /// Terminaux connus, du plus « choisi » au plus générique. On privilégie
    /// celui qui tourne déjà, sinon le premier installé, sinon Terminal.app.
    private static let terminalBundleIDs = [
        "com.mitchellh.ghostty",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "org.alacritty",
        "co.zeit.hyper",
        "com.apple.Terminal",
    ]

    /// Ouvre un terminal positionné sur un dossier — `open -a` le fait pour
    /// tous les terminaux qui déclarent gérer les dossiers.
    static func openTerminal(at path: String) -> Bool {
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let ordered = terminalBundleIDs.sorted { lhs, _ in running.contains(lhs) }
        for identifier in ordered {
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { continue }
            NSWorkspace.shared.open(
                [URL(fileURLWithPath: path)],
                withApplicationAt: app,
                configuration: NSWorkspace.OpenConfiguration()
            )
            return true
        }
        return false
    }

    static func openTerminal() -> Bool {
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        // Ghostty déjà lancé : l'activer ne fait que le ramener au premier plan,
        // il faut lui demander explicitement une nouvelle fenêtre.
        if running.contains(ghosttyBundleID) {
            openGhosttyWindow()
            return true
        }
        if let active = terminalBundleIDs.first(where: { running.contains($0) }),
           openBundleID(active) {
            return true
        }
        for identifier in terminalBundleIDs where openBundleID(identifier) {
            return true
        }
        return false
    }

    private static let ghosttyBundleID = "com.mitchellh.ghostty"

    /// `new window` via le dictionnaire AppleScript de Ghostty (≥ 1.3). Si
    /// l'automatisation est refusée, on se rabat sur la simple activation.
    private static func openGhosttyWindow() {
        Task {
            do {
                try await AppleScriptHelper.executeVoid("""
                    tell application id "\(ghosttyBundleID)"
                        new window
                        activate
                    end tell
                    """)
            } catch {
                _ = await MainActor.run { openBundleID(ghosttyBundleID) }
            }
        }
    }

    static func openSystemSettings() -> Bool {
        openBundleID("com.apple.systempreferences") || openURL("x-apple.systempreferences:")
    }

    static func lockScreen() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession")
        task.arguments = ["-suspend"]
        do {
            try task.run()
            return true
        } catch {
            return false
        }
    }

    private static func openBundleID(_ bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        return true
    }

    private static func openURL(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return NSWorkspace.shared.open(url)
    }
}
