import SwiftUI

private let cornerRadii = (
    opened: (top: CGFloat(19), bottom: CGFloat(24)),
    closed: (top: CGFloat(6), bottom: CGFloat(14))
)

// MARK: - Navigation

enum WidgetTab: String, CaseIterable, Identifiable {
    case home, dev, claude, media, system, workshop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:     "Accueil"
        case .dev:      "Dev"
        case .media:    "Média"
        case .claude:   "Claude"
        case .system:   "Système"
        case .workshop: "Atelier"
        }
    }

    var icon: String {
        switch self {
        case .home:     "house.fill"
        case .dev:      "chevron.left.forwardslash.chevron.right"
        case .media:    "waveform"
        case .claude:   "terminal"
        case .system:   "gauge.with.dots.needle.bottom.50percent"
        case .workshop: "square.grid.2x2.fill"
        }
    }

    /// Chaque page réclame la largeur qu'il lui faut : une liste de projets avec
    /// chemin et branche n'a pas les mêmes besoins qu'une horloge.
    var contentWidth: CGFloat {
        switch self {
        case .home:     760
        case .dev:      900
        case .claude:   860
        case .media:    820
        case .system:   980
        case .workshop: 980
        }
    }

    var subpages: [WidgetSubpage] {
        switch self {
        case .home:     [.summary, .agenda]
        case .dev:      [.projects, .ports, .docker, .terminal]
        case .claude:   [.sessions, .history, .mcp]
        case .system:   [.stats, .processes, .memory, .cleanup, .battery, .controls]
        case .workshop: [.shelf, .clipboard, .notes, .calculator, .actions, .settings]
        default:        []
        }
    }
}

enum WidgetSubpage: String, CaseIterable, Identifiable {
    case summary, agenda, sessions, history, mcp, projects, ports, docker, terminal, stats, processes, memory, cleanup, battery, controls, shelf, clipboard, calculator, notes, actions, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary:    "Résumé"
        case .agenda:     "Agenda"
        case .terminal:   "Terminal"
        case .calculator: "Calculatrice"
        case .sessions:  "Sessions"
        case .history:   "Historique"
        case .projects:  "Projets"
        case .ports:     "Ports"
        case .docker:    "Docker"
        case .cleanup:   "Nettoyage"
        case .clipboard: "Presse-papiers"
        case .mcp:       "Configuration"
        case .stats:     "Statistiques"
        case .processes: "Processus"
        case .memory:    "Mémoire"
        case .battery:  "Batterie"
        case .controls: "Son & écran"
        case .shelf:    "Étagère"
        case .notes:    "Notes"
        case .actions:  "Actions"
        case .settings: "Réglages"
        }
    }
}

// MARK: - Vue racine

struct NotchContentView: View {
    var panelManager: NotchPanelManager = .shared
    var settings: AppSettings = .shared
    @State private var statsModel = SystemStatsModel()
    var musicManager: MusicManager = .shared
    var batteryModel: BatteryModel = .shared
    var shelfModel: ShelfModel = .shared
    var volumeManager: VolumeManager = .shared
    var brightnessManager: BrightnessManager = .shared
    var claudeStateMachine: ClaudeStateMachine = .shared
    var notchTimer: NotchTimer = .shared

    @State private var tab: WidgetTab = .home
    @State private var subpages: [WidgetTab: WidgetSubpage] = [:]
    var activities: BarActivities = .shared
    var notifications: NotificationRelay = .shared
    var bluetooth: BluetoothModel = .shared
    var calendarModel: CalendarModel = .shared

    private var notchSize: CGSize { panelManager.notchSize }
    private var isExpanded: Bool { panelManager.isExpanded }

    /// Survol du bandeau fermé : il s'enrichit et descend un peu, sans s'ouvrir.
    private var isPeeking: Bool { panelManager.isHovering && !isExpanded }

    /// Résumé de fin de discussion, déplié sous le bandeau le temps de la bannière.
    private var showsDoneDrawer: Bool {
        !isExpanded && activities.current == .claudeDone
            && claudeStateMachine.sessionStore.finishedNotice != nil
    }

    private var panelAnimation: Animation {
        isExpanded
            ? .spring(response: 0.42, dampingFraction: 0.8)
            : .spring(response: 0.45, dampingFraction: 1.0)
    }

    private var topCornerRadius: CGFloat {
        isExpanded ? cornerRadii.opened.top : cornerRadii.closed.top
    }

    private var bottomCornerRadius: CGFloat {
        if isExpanded { return cornerRadii.opened.bottom }
        return isPeeking || showsDoneDrawer ? 18 : cornerRadii.closed.bottom
    }

    private var currentSubpage: WidgetSubpage? {
        guard let first = tab.subpages.first else { return nil }
        return subpages[tab] ?? first
    }

    var body: some View {
        VStack(spacing: 0) {
            notchLayout
        }
        .padding(.horizontal, isExpanded ? NotchConstants.expandedPanelPadding : cornerRadii.closed.bottom)
        .padding(.bottom, isExpanded ? 18 : 0)
        .background(Color.black)
        .clipShape(NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        ))
        .shadow(color: isExpanded ? .black.opacity(0.7) : .clear, radius: 6)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            panelManager.updateMeasuredSize(size)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(panelAnimation, value: isExpanded)
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: panelManager.isHovering)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: showsDoneDrawer)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: tab)
        .animation(.spring(response: 0.30, dampingFraction: 0.88), value: currentSubpage)
        .onReceive(NotificationCenter.default.publisher(for: .notchShouldCollapse)) { _ in
            panelManager.collapse()
        }
        .onReceive(NotificationCenter.default.publisher(for: Demo.navigate)) { note in
            guard let target = (note.userInfo?["tab"] as? String).flatMap(WidgetTab.init) else { return }
            tab = target
            if let sub = (note.userInfo?["subpage"] as? String).flatMap(WidgetSubpage.init),
               target.subpages.contains(sub) {
                subpages[target] = sub
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                if settings.rememberLastTab, let saved = WidgetTab(rawValue: settings.lastTab) {
                    tab = saved
                }
                // Ouvrir depuis la bannière de fin mène droit à la session concernée.
                if activities.current == .claudeDone {
                    tab = .claude
                    claudeStateMachine.sessionStore.clearFinishedNotice()
                }
                activities.dismissTransient()
            } else if !settings.rememberLastTab {
                tab = .home
            }
        }
        .onChange(of: volumeManager.lastChangeAt) { _, _ in
            guard settings.barShowVolumeHUD else { return }
            SystemHUD.suppressNative()
            activities.show(.volume, for: 1.4)
        }
        .onChange(of: brightnessManager.lastChangeAt) { _, _ in
            guard settings.barShowVolumeHUD else { return }
            SystemHUD.suppressNative()
            activities.show(.brightness, for: 1.4)
        }
        .onChange(of: notifications.latest) { _, value in
            guard value != nil, settings.relaySystemNotifications else { return }
            activities.show(.notification, for: 6)
        }
        .onChange(of: bluetooth.lastChange?.at) { _, value in
            guard value != nil, settings.barShowBluetooth else { return }
            activities.show(.bluetooth, for: 4)
        }
        .onChange(of: batteryModel.lastEvent?.at) { _, value in
            guard value != nil, settings.barShowBatteryAlerts else { return }
            activities.show(.batteryAlert, for: 5)
        }
        .onChange(of: claudeStateMachine.sessionStore.finishedNotice) { _, notice in
            guard notice != nil, settings.barShowClaudeDone, !isExpanded else { return }
            activities.show(.claudeDone, for: 10)
        }
        .onChange(of: showsDoneDrawer, initial: true) { _, shows in
            panelManager.showsDrawer = shows
        }
    }

    @ViewBuilder
    private var notchLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isExpanded {
                notchStrip
            } else {
                collapsedBar
                if showsDoneDrawer, let notice = claudeStateMachine.sessionStore.finishedNotice {
                    ClaudeDoneDrawer(notice: notice)
                        .frame(width: notchSize.width - 10 + 2 * (104 + 4))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if isExpanded {
                expandedContent
                    .frame(width: tab.contentWidth)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.8, anchor: .top)
                                .combined(with: .opacity)
                                .animation(.smooth(duration: 0.35)),
                            removal: .opacity.animation(.easeOut(duration: 0.15))
                        )
                    )
            }
        }
    }

    // MARK: Bandeau de l'encoche, ouvert

    private var notchStrip: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title)
                    .font(NK.ui(13.5, .semibold))
                    .foregroundStyle(NK.t1)
                if let sub = currentSubpage {
                    Text(sub.title)
                        .font(NK.ui(10, .medium))
                        .foregroundStyle(NK.t3)
                }
            }
            .padding(.leading, 9)
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: notchSize.width - 8)

            HStack(spacing: 6) {
                stripButton(icon: panelManager.isPinned ? "pin.fill" : "pin") {
                    panelManager.togglePin()
                }
                stripButton(icon: "xmark") { panelManager.collapse() }
            }
            .padding(.trailing, 3)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: tab.contentWidth, height: notchSize.height)
    }

    private func stripButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(width: 24, height: 24)
                .background(Circle().fill(NK.surfaceRaised))
        }
        .buttonStyle(.plain)
    }

    // MARK: Bandeau de l'encoche, fermé

    private var collapsedBar: some View {
        NotchBar(notchSize: notchSize, isPeeking: isPeeking, statsModel: statsModel)
    }

    // MARK: Contenu déployé

    @ViewBuilder
    private var expandedContent: some View {
        VStack(spacing: 0) {
            tabRail
                .padding(.top, 6)

            pageContent
                .frame(
                    maxWidth: .infinity,
                    minHeight: NotchConstants.minExpandedContentHeight,
                    alignment: .top
                )
        }
    }

    private var tabRail: some View {
        HStack(spacing: 2) {
            ForEach(WidgetTab.allCases) { item in
                Button { select(item) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(item.title)
                            .font(NK.ui(12, .semibold))
                    }
                    .foregroundStyle(tab == item ? NK.t1 : NK.t3)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tab == item ? Color.white.opacity(0.10) : .clear)
                    )
                    .overlay(alignment: .bottom) {
                        if tab == item {
                            Capsule()
                                .fill(NK.accent)
                                .frame(height: 2)
                                .padding(.horizontal, 9)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 12)

            if !tab.subpages.isEmpty {
                subnav
            }
        }
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var subnav: some View {
        HStack(spacing: 3) {
            ForEach(tab.subpages) { item in
                Button { subpages[tab] = item } label: {
                    Text(item.title)
                        .font(NK.ui(11, .semibold))
                        .foregroundStyle(currentSubpage == item ? NK.t1 : NK.t3)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(currentSubpage == item ? Color.white.opacity(0.09) : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func select(_ item: WidgetTab) {
        tab = item
        settings.lastTab = item.rawValue
    }

    @ViewBuilder
    private var pageContent: some View {
        switch tab {
        case .home:
            switch currentSubpage ?? .summary {
            case .agenda: AgendaPageView()
            default:      NotchHomeView(statsModel: statsModel, musicManager: musicManager, batteryModel: batteryModel,
                                        onOpenMedia: { select(.media) })
            }
        case .dev:
            switch currentSubpage ?? .projects {
            case .ports:    PortsPageView()
            case .docker:   DockerPageView()
            case .terminal: TerminalPageView()
            default:      DevPageView()
            }
        case .media:
            MediaPlayerView(musicManager: musicManager)
        case .claude:
            switch currentSubpage ?? .sessions {
            case .mcp:     ClaudeSetupView()
            case .history: ClaudeHistoryView()
            default:   ClaudeView(stateMachine: claudeStateMachine)
            }
        case .system:
            switch currentSubpage ?? .stats {
            case .processes: ProcessesPageView()
            case .memory:    MemoryPageView()
            case .cleanup:   CleanupPageView()
            case .battery:   BatteryView(battery: batteryModel)
            case .controls:  InlineHUD(volumeManager: volumeManager, brightnessManager: brightnessManager)
            default:         StatsPageView(model: statsModel, settings: settings)
            }
        case .workshop:
            switch currentSubpage ?? .shelf {
            case .clipboard: ClipboardPageView()
            case .calculator: CalculatorView()
            case .notes:    NotesView()
            case .actions:  ToolsPageView()
            case .settings: SettingsView(settings: settings)
            default:        ShelfView(shelf: shelfModel)
            }
        }
    }
}

// MARK: - Accueil

struct NotchHomeView: View {
    var statsModel: SystemStatsModel
    var musicManager: MusicManager
    var batteryModel: BatteryModel
    /// Le bloc « En cours » mène à la page Média ; ses boutons restent des boutons.
    var onOpenMedia: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 20) {
                clockBlock
                Spacer(minLength: 12)
                metricsGrid
                    .frame(width: 404)
            }
            .padding(.top, 14)

            Hairline()
                .padding(.top, 14)

            bottomRow
                .padding(.top, 14)
                .padding(.bottom, 12)
        }
    }

    // MARK: Colonne gauche — l'heure porte la page

    private var clockBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(clockParts.0)
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NK.t1)
                Text(clockParts.1)
                    .font(.system(size: 23, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NK.t3)
            }
            .kerning(-1.6)

            HStack(spacing: 12) {
                Text(Self.dateFormatter.string(from: Date()))
                    .font(NK.ui(12, .medium))
                    .foregroundStyle(NK.t2)

                Rectangle()
                    .fill(NK.line)
                    .frame(width: 1, height: 11)

                HStack(spacing: 6) {
                    SectionLabel("Session")
                    Text(statsModel.uptime)
                        .font(NK.mono(11))
                        .foregroundStyle(NK.t2)
                }
            }
        }
    }

    /// « 12:04:20 » → (« 12:04 », « :20 ») pour poser la seconde en second plan.
    private var clockParts: (String, String) {
        let value = statsModel.clock
        guard let range = value.range(of: ":", options: .backwards),
              value.filter({ $0 == ":" }).count > 1 else {
            return (value, "")
        }
        return (String(value[value.startIndex..<range.lowerBound]), String(value[range.lowerBound...]))
    }

    // MARK: Colonne droite — quatre mesures alignées

    private var metricsGrid: some View {
        HStack(spacing: 0) {
            metricCell("CPU", statsModel.cpuUsage, statsModel.cpuRatio, NK.accent, first: true)
            metricCell("Mémoire", statsModel.memoryUsage, statsModel.memoryRatio, NK.accent)
            metricCell("Batterie", batteryModel.percentString, batteryModel.normalizedLevel,
                       batteryModel.isCharging ? NK.ok : (batteryModel.level < 20 ? NK.bad : NK.ok))
            metricCell("Réseau", statsModel.downloadSpeed, nil, NK.accent)
        }
        .background(
            RoundedRectangle(cornerRadius: NK.radiusCard, style: .continuous)
                .stroke(NK.line, lineWidth: 1)
        )
    }

    /// Le séparateur est un `overlay` : posé dans le flux, un `Rectangle`
    /// sans hauteur fixe rend toute la rangée élastique et mange la fenêtre.
    private func metricCell(_ key: String, _ value: String, _ ratio: Double?,
                            _ tint: Color, first: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(key)
            Text(value)
                .font(NK.mono(14))
                .foregroundStyle(NK.t1)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            MeterBar(value: ratio ?? 0, tint: tint, height: 2)
                .opacity(ratio == nil ? 0.25 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .leading) {
            if !first {
                Rectangle()
                    .fill(NK.line)
                    .frame(width: 1)
                    .padding(.vertical, 8)
            }
        }
    }

    // MARK: Rangée basse — lecture en cours et raccourcis se partagent la largeur

    private var bottomRow: some View {
        HStack(alignment: .top, spacing: 20) {
            if !musicManager.isIdle {
                nowPlaying
                    .frame(maxWidth: .infinity, alignment: .leading)
                columnDivider
            }

            quickLaunch

            columnDivider

            TimerBlock()

            if musicManager.isIdle { Spacer(minLength: 0) }
        }
    }

    private var columnDivider: some View {
        Rectangle()
            .fill(NK.line)
            .frame(width: 1, height: 58)
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                SectionLabel("En cours")
                StatusPill(text: isSpotify ? "Spotify" : "Musique",
                           tint: isSpotify
                               ? Color(red: 0.14, green: 0.78, blue: 0.43)
                               : Color(red: 0.98, green: 0.16, blue: 0.42))
                Spacer(minLength: 0)
            }

            HStack(spacing: 11) {
                artwork
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(musicManager.songTitle)
                        .font(NK.ui(12, .semibold))
                        .foregroundStyle(NK.t1)
                        .lineLimit(1)
                    Text(musicManager.artistName)
                        .font(NK.ui(10.5, .medium))
                        .foregroundStyle(NK.t3)
                        .lineLimit(1)
                    MeterBar(value: progress, tint: NK.accent, height: 2)
                        .padding(.top, 1)
                }

                HStack(spacing: 12) {
                    Button { Task { await musicManager.previousTrack() } } label: {
                        Image(systemName: "backward.fill").font(.system(size: 12))
                    }
                    Button { Task { await musicManager.togglePlay() } } label: {
                        Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white.opacity(0.72))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenMedia)
        .help("Ouvrir Média")
    }

    private var isSpotify: Bool { musicManager.bundleIdentifier == "com.spotify.client" }

    private var progress: Double {
        musicManager.songDuration > 0 ? musicManager.elapsedTime / musicManager.songDuration : 0
    }

    @ViewBuilder
    private var artwork: some View {
        if let art = musicManager.albumArt {
            Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(LinearGradient(colors: [Color(red: 0.24, green: 0.16, blue: 0.37),
                                              Color(red: 0.07, green: 0.13, blue: 0.25)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    private var quickLaunch: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("Raccourcis")
            HStack(spacing: 12) {
                ForEach(QuickLaunchItem.all) { item in
                    Button(action: item.action) {
                        VStack(spacing: 5) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(RoundedRectangle(cornerRadius: NK.radiusControl, style: .continuous)
                                    .fill(item.tint))
                            Text(item.title)
                                .font(NK.ui(8.5, .medium))
                                .foregroundStyle(NK.t3)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if musicManager.isIdle { Spacer(minLength: 0) }
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM yyyy"
        return f
    }()
}

struct QuickLaunchItem: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    @MainActor static let all: [QuickLaunchItem] = [
        .init(title: "Musique", symbol: "music.note",
              tint: Color(red: 0.98, green: 0.16, blue: 0.42)) { _ = ActionLauncher.openMusic() },
        .init(title: "Spotify", symbol: "waveform",
              tint: Color(red: 0.14, green: 0.78, blue: 0.43)) { _ = ActionLauncher.openSpotify() },
        .init(title: "YouTube", symbol: "play.fill",
              tint: Color(red: 0.98, green: 0.11, blue: 0.06)) { _ = ActionLauncher.openYouTube() },
        .init(title: "Finder", symbol: "folder.fill",
              tint: Color(red: 0.17, green: 0.50, blue: 0.88)) { _ = ActionLauncher.openFinder() },
        .init(title: "Terminal", symbol: "apple.terminal.fill",
              tint: Color(red: 0.23, green: 0.23, blue: 0.24)) { _ = ActionLauncher.openTerminal() },
    ]
}
