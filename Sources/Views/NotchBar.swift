import SwiftUI

/// Bandeau de l'encoche fermée. Deux slots, jamais trois : la gauche porte
/// l'identité, la droite la mesure ou l'action. Plusieurs activités peuvent
/// être vraies en même temps — les éphémères passent devant, les permanentes
/// défilent, et un balayage horizontal les fait défiler à la main.
struct NotchBar: View {
    let notchSize: CGSize
    let isPeeking: Bool

    var activities: BarActivities = .shared
    var settings: AppSettings = .shared
    var statsModel: SystemStatsModel
    var musicManager: MusicManager = .shared
    var batteryModel: BatteryModel = .shared
    var volumeManager: VolumeManager = .shared
    var brightnessManager: BrightnessManager = .shared
    var claudeStateMachine: ClaudeStateMachine = .shared
    var notchTimer: NotchTimer = .shared
    var bluetooth: BluetoothModel = .shared
    var notifications: NotificationRelay = .shared
    var calendar: CalendarModel = .shared

    private var current: BarActivity { activities.current }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: slotWidth, alignment: .leading)
                .padding(.leading, 4)

            Color.clear.frame(width: notchSize.width - 10)

            trailing
                .frame(width: slotWidth, alignment: .trailing)
                .padding(.trailing, 4)
        }
        .frame(height: notchSize.height + (isPeeking ? NotchConstants.hoverLift : 0))
        .overlay(alignment: .bottom) {
            if activities.showsIndicator && isPeeking {
                indicator.padding(.bottom, 1)
            }
        }
        .onAppear { activities.updatePersistent(persistentList) }
        .onChange(of: persistentList) { _, list in activities.updatePersistent(list) }
    }

    /// Ordre de priorité des activités permanentes : le minuteur d'abord,
    /// puis Claude, la musique, l'agenda, et le repos en dernier recours.
    private var persistentList: [BarActivity] {
        var list: [BarActivity] = []
        if notchTimer.isActive { list.append(.timer) }
        if settings.barShowClaude && claudeStateMachine.hasActiveSessions { list.append(.claude) }
        if settings.barShowMusic && musicManager.isPlaying { list.append(.music) }
        if settings.barShowCalendar && calendar.imminent != nil { list.append(.calendar) }
        return list
    }

    private var indicator: some View {
        HStack(spacing: 3) {
            ForEach(Array(activities.persistent.enumerated()), id: \.element) { offset, _ in
                Circle()
                    .fill(Color.white.opacity(offset == activities.index ? 0.55 : 0.15))
                    .frame(width: 3, height: 3)
            }
        }
    }

    private var slotWidth: CGFloat {
        let base: CGFloat
        switch current {
        case .volume, .brightness:   base = 64
        case .notification:          base = 118
        case .bluetooth:             base = 108
        case .batteryAlert:          base = 104
        case .claudeDone:            base = 104
        case .timer:                 base = 84
        case .claude, .music:        base = 92
        case .calendar:              base = 104
        case .idle:                  base = 58
        }
        return base + (isPeeking ? peekBonus : 0)
    }

    private var peekBonus: CGFloat {
        switch current {
        case .idle:                                          62
        case .music:                                         46
        case .claude, .calendar:                             40
        case .timer:                                         44
        case .volume, .brightness, .notification,
             .bluetooth, .batteryAlert, .claudeDone:         0
        }
    }

    // MARK: Slot gauche

    @ViewBuilder
    private var leading: some View {
        switch current {
        case .volume:
            gauge(icon: volumeManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                  value: volumeManager.isMuted ? 0 : volumeManager.volume)

        case .brightness:
            gauge(icon: brightnessManager.brightness < 0.5 ? "sun.min.fill" : "sun.max.fill",
                  value: brightnessManager.brightness)

        case .notification:
            HStack(spacing: 5) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(NK.accent)
                Text(notifications.latest?.appName ?? "Notification")
                    .font(NK.ui(9, .semibold))
                    .foregroundStyle(NK.t2)
                    .lineLimit(1)
            }

        case .bluetooth:
            HStack(spacing: 5) {
                Image(systemName: bluetooth.lastChange?.device.symbol ?? "dot.radiowaves.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(bluetooth.lastChange?.connected == true ? NK.accent : NK.t3)
                Text(bluetooth.lastChange?.device.name ?? "Bluetooth")
                    .font(NK.ui(9, .semibold))
                    .foregroundStyle(NK.t2)
                    .lineLimit(1)
            }

        case .batteryAlert:
            HStack(spacing: 5) {
                Image(systemName: batteryAlertIcon)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(batteryAlertTint)
                Text(batteryAlertLabel)
                    .font(NK.ui(9, .semibold))
                    .foregroundStyle(NK.t2)
                    .lineLimit(1)
            }

        case .claudeDone:
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(NK.ok)
                Text(claudeStateMachine.sessionStore.finishedNotice?.projectName ?? "Claude")
                    .font(NK.ui(9, .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(1)
            }

        case .timer:
            HStack(spacing: 5) {
                Circle()
                    .fill(notchTimer.phase == .rest ? NK.ok : NK.accent)
                    .frame(width: 5, height: 5)
                    .opacity(notchTimer.isRunning ? 1 : 0.4)
                Text(notchTimer.label)
                    .font(NK.ui(9, .semibold))
                    .foregroundStyle(NK.t2)
                    .lineLimit(1)
            }

        case .claude:
            HStack(spacing: 5) {
                Circle().fill(claudeTint).frame(width: 5, height: 5)
                Text(claudeStateMachine.sessionStore.effectiveSession?.projectName ?? "Claude")
                    .font(NK.ui(9, .semibold))
                    .foregroundStyle(NK.t2)
                    .lineLimit(1)
                if isPeeking {
                    Text(claudeStateMachine.currentTask.displayName)
                        .font(NK.ui(9, .medium))
                        .foregroundStyle(claudeTint.opacity(0.85))
                        .lineLimit(1)
                }
            }

        case .music:
            HStack(spacing: 5) {
                Image(systemName: "music.note")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color(red: 0.98, green: 0.16, blue: 0.42))
                Text(musicManager.songTitle)
                    .font(NK.ui(9, .semibold))
                    .foregroundStyle(NK.t2)
                    .lineLimit(1)
                if isPeeking, !musicManager.artistName.isEmpty {
                    Text("· \(musicManager.artistName)")
                        .font(NK.ui(9, .medium))
                        .foregroundStyle(NK.t4)
                        .lineLimit(1)
                }
            }

        case .calendar:
            HStack(spacing: 5) {
                Circle()
                    .fill(calendar.imminent?.tint ?? NK.accent)
                    .frame(width: 5, height: 5)
                Text(calendar.imminent?.title ?? "Agenda")
                    .font(NK.ui(9, .semibold))
                    .foregroundStyle(NK.t2)
                    .lineLimit(1)
            }

        case .idle:
            HStack(spacing: 6) {
                Text(statsModel.clock)
                    .font(NK.mono(9))
                    .foregroundStyle(NK.t3)
                if isPeeking {
                    Text(Self.shortDate.string(from: Date()))
                        .font(NK.ui(9, .medium))
                        .foregroundStyle(NK.t4)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: Slot droit

    @ViewBuilder
    private var trailing: some View {
        switch current {
        case .volume:
            Text("\(Int((volumeManager.isMuted ? 0 : volumeManager.volume) * 100)) %")
                .font(NK.mono(9))
                .foregroundStyle(Color.white.opacity(0.8))

        case .brightness:
            Text("\(Int(brightnessManager.brightness * 100)) %")
                .font(NK.mono(9))
                .foregroundStyle(Color.white.opacity(0.8))

        case .notification:
            Text(notifications.latest?.title ?? "")
                .font(NK.ui(9, .medium))
                .foregroundStyle(NK.t3)
                .lineLimit(1)

        case .bluetooth:
            HStack(spacing: 5) {
                if let battery = bluetooth.lastChange?.device.battery {
                    Text("\(battery) %")
                        .font(NK.mono(9))
                        .foregroundStyle(NK.t3)
                }
                Text(bluetooth.lastChange?.connected == true ? "connecté" : "déconnecté")
                    .font(NK.ui(9, .medium))
                    .foregroundStyle(NK.t3)
            }

        case .batteryAlert:
            Text(batteryModel.percentString)
                .font(NK.mono(9))
                .foregroundStyle(batteryAlertTint)

        case .claudeDone:
            HStack(spacing: 6) {
                Text("terminé")
                    .font(NK.ui(9, .medium))
                    .foregroundStyle(NK.ok.opacity(0.85))
                Text(shortDuration(claudeStateMachine.sessionStore.finishedNotice?.duration ?? 0))
                    .font(NK.mono(9))
                    .foregroundStyle(NK.t3)
            }

        case .timer:
            HStack(spacing: 8) {
                Text(notchTimer.display)
                    .font(NK.mono(9.5))
                    .foregroundStyle(notchTimer.isRunning ? Color.white.opacity(0.8) : NK.t3)
                if isPeeking {
                    barButton(notchTimer.isRunning ? "pause.fill" : "play.fill") { notchTimer.toggle() }
                }
            }

        case .claude:
            HStack(spacing: 6) {
                if let tool = claudeStateMachine.sessionStore.effectiveSession?.recentEvents.last?.tool {
                    Text(tool)
                        .font(NK.ui(9, .medium))
                        .foregroundStyle(NK.t3)
                        .lineLimit(1)
                }
                Text(claudeStateMachine.sessionStore.effectiveSession?.formattedDuration ?? "")
                    .font(NK.mono(9))
                    .foregroundStyle(NK.t3)
            }

        case .music:
            HStack(spacing: 8) {
                if isPeeking {
                    barButton("backward.fill") { Task { await musicManager.previousTrack() } }
                } else {
                    Text(remainingTime)
                        .font(NK.mono(9))
                        .foregroundStyle(NK.t3)
                }
                barButton(musicManager.isPlaying ? "pause.fill" : "play.fill") {
                    Task { await musicManager.togglePlay() }
                }
                if isPeeking {
                    barButton("forward.fill") { Task { await musicManager.nextTrack() } }
                }
            }

        case .calendar:
            Text(calendar.imminent?.countdown ?? "")
                .font(NK.mono(9))
                .foregroundStyle(NK.t3)

        case .idle:
            HStack(spacing: 6) {
                if settings.barShowCPU {
                    Text(statsModel.cpuUsage)
                        .font(NK.mono(9))
                        .foregroundStyle(NK.t3)
                }
                if isPeeking {
                    Text(statsModel.memoryUsage)
                        .font(NK.mono(9))
                        .foregroundStyle(NK.t4)
                    Text(batteryModel.percentString)
                        .font(NK.mono(9))
                        .foregroundStyle(NK.t4)
                }
                Circle()
                    .fill(batteryIndicatorColor)
                    .frame(width: 5, height: 5)
            }
        }
    }

    // MARK: Fragments

    private func gauge(icon: String, value: Float) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.white)
            Capsule()
                .fill(Color.white.opacity(0.16))
                .frame(height: 3)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color.white)
                            .frame(width: proxy.size.width * CGFloat(max(0, min(1, value))))
                    }
                }
        }
    }

    private func barButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var batteryAlertIcon: String {
        switch batteryModel.lastEvent?.kind {
        case .pluggedIn: "powerplug.fill"
        case .unplugged: "battery.50"
        case .low:       "battery.25"
        case .full:      "battery.100.bolt"
        case nil:        "battery.50"
        }
    }

    private var batteryAlertTint: Color {
        switch batteryModel.lastEvent?.kind {
        case .low: NK.bad
        case .pluggedIn, .full: NK.ok
        default: NK.t2
        }
    }

    private var batteryAlertLabel: String {
        switch batteryModel.lastEvent?.kind {
        case .pluggedIn: "Sur secteur"
        case .unplugged: "Sur batterie"
        case .low:       "Batterie basse"
        case .full:      "Chargée"
        case nil:        "Batterie"
        }
    }

    private var claudeTint: Color {
        switch claudeStateMachine.currentTask {
        case .working:    NK.accent
        case .waiting:    NK.warn
        case .compacting: NK.hot
        case .sleeping:   NK.violet
        default:          NK.t3
        }
    }

    private var batteryIndicatorColor: Color {
        if batteryModel.isCharging { return NK.ok }
        if batteryModel.level < 20 { return NK.bad }
        return Color.white.opacity(0.35)
    }

    private var remainingTime: String {
        let remaining = max(0, musicManager.songDuration - musicManager.elapsedTime)
        return String(format: "%d:%02d", Int(remaining) / 60, Int(remaining) % 60)
    }

    private func shortDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return total >= 60 ? "\(total / 60)m \(String(format: "%02d", total % 60))s" : "\(total)s"
    }

    private static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEE d"
        return f
    }()
}
