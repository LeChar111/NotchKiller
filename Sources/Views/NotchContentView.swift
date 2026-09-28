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
        case .system:   [.stats, .processes, .memory, .cleanup, .battery]
        case .workshop: [.shelf, .clipboard, .notes, .calculator, .actions]
        default:        []
        }
    }
}

enum WidgetSubpage: String, CaseIterable, Identifiable {
    case summary, agenda, sessions, history, mcp, projects, ports, docker, terminal, stats, processes, memory, cleanup, battery, shelf, clipboard, calculator, notes, actions, settings

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
    /// Les réglages ne sont pas une page d'onglet : le bouton du bandeau les
    /// affiche par-dessus l'onglet courant, qu'on retrouve en les refermant.
    @State private var showsSettings = false
    @State private var hoveredTab: WidgetTab?
    @State private var settingsSection: SettingsSection = .bar
    @State private var confirmQuit = false
    @State private var confirmTask: Task<Void, Never>?
    @Namespace private var navNamespace
    var ports: PortsModel = .shared
    var docker: DockerModel = .shared
    @State private var subpages: [WidgetTab: WidgetSubpage] = [:]
    var activities: BarActivities = .shared
    var notifications: NotificationRelay = .shared
    var bluetooth: BluetoothModel = .shared
    var calendarModel: CalendarModel = .shared
    var ableton: AbletonTransport = .shared

    private var notchSize: CGSize { panelManager.notchSize }
    private var isExpanded: Bool { panelManager.isExpanded }

    /// Survol du bandeau fermé : il s'enrichit et descend un peu, sans s'ouvrir.
    private var isPeeking: Bool { panelManager.isHovering && !isExpanded }

    /// Résumé de fin de discussion, déplié sous le bandeau le temps de la bannière.
    private var showsDoneDrawer: Bool {
        !isExpanded && activities.current == .claudeDone
            && claudeStateMachine.sessionStore.finishedNotice != nil
    }

    /// Volume ou luminosité en cours de réglage : jauge pleine largeur sous le bandeau.
    private var showsLevelDrawer: Bool {
        !isExpanded && (activities.current == .volume || activities.current == .brightness)
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
        return isPeeking || showsDoneDrawer || showsLevelDrawer ? 18 : cornerRadii.closed.bottom
    }

    private var contentWidth: CGFloat {
        // Une colonne de réglages : pleine largeur de 980, les interrupteurs
        // partiraient loin de leur libellé.
        showsSettings ? 640 : tab.contentWidth
    }

    private var currentSubpage: WidgetSubpage? {
        guard let first = tab.subpages.first else { return nil }
        return subpages[tab] ?? first
    }

    var body: some View {
        VStack(spacing: 0) {
            notchLayout
                .offset(x: panelManager.nudge * 7)
        }
        .padding(.horizontal, isExpanded ? NotchConstants.expandedPanelPadding : cornerRadii.closed.bottom)
        .padding(.bottom, isExpanded ? 18 : max(0, panelManager.stretch) * 12)
        .background(Color.black)
        .clipShape(NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        ))
        .shadow(color: isExpanded ? .black.opacity(0.7) : .clear, radius: 6)
        // Tiré vers le haut, le panneau ouvert se tasse contre l'encoche.
        .scaleEffect(x: 1, y: isExpanded ? 1 + min(0, panelManager.stretch) * 0.04 : 1, anchor: .top)
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
        .animation(.spring(response: 0.30, dampingFraction: 0.88), value: showsSettings)
        .animation(.spring(response: 0.30, dampingFraction: 0.88), value: settingsSection)
        .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.72), value: panelManager.stretch)
        .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.72), value: panelManager.nudge)
        .onReceive(NotificationCenter.default.publisher(for: .notchShouldCollapse)) { _ in
            panelManager.collapse()
        }
        .onReceive(NotificationCenter.default.publisher(for: Demo.navigate)) { note in
            guard let target = (note.userInfo?["tab"] as? String).flatMap(WidgetTab.init) else { return }
            tab = target
            showsSettings = note.userInfo?["subpage"] as? String == WidgetSubpage.settings.rawValue
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
            } else {
                showsSettings = false
                if !settings.rememberLastTab { tab = .home }
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
        .onChange(of: ableton.alert) { _, value in
            guard let value, settings.barShowDAW else { return }
            activities.show(.dawAlert, for: value.kind == .crash ? 10 : 3)
        }
        .onChange(of: batteryModel.lastEvent?.at) { _, value in
            guard value != nil, settings.barShowBatteryAlerts else { return }
            activities.show(.batteryAlert, for: 5)
        }
        .onChange(of: claudeStateMachine.sessionStore.finishedNotice) { _, notice in
            guard notice != nil, settings.barShowClaudeDone, !isExpanded else { return }
            activities.show(.claudeDone, for: 10)
        }
        .onChange(of: panelManager.pageSwipe.count) { _, _ in
            let tabs = WidgetTab.allCases
            guard isExpanded, let position = tabs.firstIndex(of: tab) else { return }
            let target = position + panelManager.pageSwipe.delta
            guard tabs.indices.contains(target) else { return }
            select(tabs[target])
        }
        .onChange(of: watchesDevCounts) { _, watching in
            if watching {
                ports.subscribe()
                docker.subscribe()
            } else {
                ports.unsubscribe()
                docker.unsubscribe()
            }
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
                if showsLevelDrawer {
                    LevelDrawer(activity: activities.current)
                        .frame(width: notchSize.width - 10 + 2 * (104 + 4))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if showsDoneDrawer, let notice = claudeStateMachine.sessionStore.finishedNotice {
                    ClaudeDoneDrawer(notice: notice)
                        .frame(width: notchSize.width - 10 + 2 * (104 + 4))
                        .offset(y: min(0, panelManager.stretch) * 14)
                        .opacity(1 + min(0, panelManager.stretch) * 0.6)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if isExpanded {
                expandedContent
                    .frame(width: contentWidth)
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

    /// Les onglets occupent l'oreille gauche de l'encoche, les actions la
    /// droite : la navigation principale ne coûte aucune ligne au contenu.
    private var notchStrip: some View {
        HStack(spacing: 0) {
            tabPills
                .padding(.leading, 4)
                .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: notchSize.width - 8)

            HStack(spacing: 6) {
                if showsSettings {
                    quitButton
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                stripButton(icon: "gearshape", active: showsSettings) {
                    showsSettings.toggle()
                }
                stripButton(icon: panelManager.isPinned ? "pin.fill" : "pin") {
                    panelManager.togglePin()
                }
                stripButton(icon: "xmark") { panelManager.collapse() }
            }
            .padding(.trailing, 3)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: contentWidth, height: notchSize.height)
    }

    /// Icônes seules ; l'onglet actif déplie son libellé dans une pastille
    /// blanche qui glisse d'un onglet à l'autre.
    private var tabPills: some View {
        HStack(spacing: 2) {
            ForEach(WidgetTab.allCases) { item in
                let active = isCurrent(item)
                Button { select(item) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.icon)
                            .font(.system(size: 11, weight: .semibold))
                        if active {
                            Text(item.title)
                                .font(NK.ui(11.5, .semibold))
                                .fixedSize()
                        }
                    }
                    .foregroundStyle(active ? Color.black : hoveredTab == item ? NK.t1 : NK.t2)
                    .padding(.horizontal, active ? 10 : 7)
                    .frame(height: 24)
                    .background {
                        if active {
                            Capsule()
                                .fill(Color.white)
                                .matchedGeometryEffect(id: "tabPill", in: navNamespace)
                        } else if hoveredTab == item {
                            Capsule().fill(NK.surfaceRaised)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(item.title)
                .onHover { hovering in
                    // Un cran à chaque pastille franchie, comme des crans magnétiques.
                    if hovering, hoveredTab != item { Haptics.play(.tick) }
                    hoveredTab = hovering ? item : (hoveredTab == item ? nil : hoveredTab)
                }
            }
        }
    }

    /// Quitter est irréversible pour la session : un premier clic arme le
    /// bouton, un second dans les 4 s confirme — pas de dialogue système, qui
    /// volerait le focus au panneau.
    private var quitButton: some View {
        Button {
            if confirmQuit {
                NSApp.terminate(nil)
            } else {
                confirmQuit = true
                Haptics.play(.thud)
                confirmTask?.cancel()
                confirmTask = Task {
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled else { return }
                    confirmQuit = false
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: confirmQuit ? "exclamationmark.triangle.fill" : "power")
                    .font(.system(size: 10.5, weight: .bold))
                if confirmQuit {
                    Text("Quitter ?")
                        .font(NK.ui(10.5, .semibold))
                        .fixedSize()
                }
            }
            .foregroundStyle(NK.bad)
            .padding(.horizontal, confirmQuit ? 9 : 0)
            .frame(minWidth: 24, minHeight: 24)
            .background(Capsule().fill(NK.bad.opacity(confirmQuit ? 0.22 : 0.14)))
            .contentShape(Capsule())
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: confirmQuit)
        }
        .buttonStyle(.plain)
        .help(confirmQuit ? "Cliquer à nouveau pour quitter" : "Quitter NotchKiller")
    }

    private func stripButton(icon: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(active ? NK.accent : Color.white.opacity(0.55))
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
            if showsSubpageRail {
                subpageRail
            }

            pageContent
                .frame(
                    maxWidth: .infinity,
                    minHeight: NotchConstants.minExpandedContentHeight,
                    alignment: .top
                )
        }
    }

    private var showsSubpageRail: Bool {
        showsSettings || !tab.subpages.isEmpty
    }

    /// Seconde ligne, réservée aux sous-pages (ou aux sections des réglages) :
    /// soulignées comme des onglets de document, avec un compteur quand la
    /// page a quelque chose à signaler.
    private var subpageRail: some View {
        HStack(spacing: 18) {
            if showsSettings {
                ForEach(SettingsSection.allCases) { item in
                    railButton(item.title, active: settingsSection == item) { settingsSection = item }
                }
            } else {
                ForEach(tab.subpages) { item in
                    railButton(item.title, active: currentSubpage == item, badge: badge(for: item)) {
                        subpages[tab] = item
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func railButton(_ title: String, active: Bool, badge: Int? = nil,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(NK.ui(11.5, .semibold))
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(NK.mono(9))
                        .monospacedDigit()
                        .foregroundStyle(active ? NK.accent : NK.t2)
                        .padding(.horizontal, 4)
                        .frame(height: 14)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(active ? NK.accent.opacity(0.22) : Color.white.opacity(0.10))
                        )
                }
            }
            .foregroundStyle(active ? NK.t1 : NK.t2)
            .frame(height: NotchConstants.navRailHeight)
            .overlay(alignment: .bottom) {
                if active {
                    Capsule()
                        .fill(NK.accent)
                        .frame(height: 2)
                        .matchedGeometryEffect(id: "subUnderline", in: navNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func badge(for subpage: WidgetSubpage) -> Int? {
        switch subpage {
        case .agenda:   calendarModel.events.filter { $0.end > Date() }.count
        case .ports:    ports.ports.count
        case .docker:   docker.containers.filter(\.isRunning).count
        case .sessions: claudeStateMachine.sessionStore.activeSessionCount
        case .shelf:    shelfModel.items.count
        default:        nil
        }
    }

    /// Ports et conteneurs ne sont interrogés que page ouverte : on s'abonne
    /// aussi le temps que l'onglet Dev est affiché, pour ses compteurs.
    private var watchesDevCounts: Bool {
        isExpanded && !showsSettings && tab == .dev
    }

    private func isCurrent(_ item: WidgetTab) -> Bool {
        !showsSettings && tab == item
    }

    private func select(_ item: WidgetTab) {
        showsSettings = false
        tab = item
        settings.lastTab = item.rawValue
    }

    @ViewBuilder
    private var pageContent: some View {
        if showsSettings {
            SettingsView(settings: settings, section: settingsSection)
        } else {
            tabContent
        }
    }

    @ViewBuilder
    private var tabContent: some View {
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
            default:         StatsPageView(model: statsModel, settings: settings)
            }
        case .workshop:
            switch currentSubpage ?? .shelf {
            case .clipboard: ClipboardPageView()
            case .calculator: CalculatorView()
            case .notes:    NotesView()
            case .actions:  ToolsPageView()
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
