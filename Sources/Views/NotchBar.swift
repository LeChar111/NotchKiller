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
    var ableton: AbletonTransport = .shared

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
        let showsDAW = settings.barShowDAW && ableton.isRunning
        // Live en lecture passe devant ; à l'arrêt, il attend son tour.
        if showsDAW && ableton.isPlaying { list.append(.daw) }
        if settings.barShowClaude && claudeStateMachine.hasActiveSessions { list.append(.claude) }
        if settings.barShowMusic && musicManager.isPlaying { list.append(.music) }
        if settings.barShowCalendar && calendar.imminent != nil { list.append(.calendar) }
        if showsDAW && !ableton.isPlaying { list.append(.daw) }
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
        case .volume, .brightness:   base = 104
        case .notification:          base = 118
        case .bluetooth:             base = 108
        case .batteryAlert:          base = 104
        case .claudeDone:            base = 104
        case .timer:                 base = 84
        case .claude, .music:        base = 92
        case .daw:                   base = 104
        case .dawAlert:              base = 116
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
        case .daw:                                           56
        case .timer:                                         44
        case .volume, .brightness, .notification,
             .bluetooth, .batteryAlert, .claudeDone,
             .dawAlert:                                      0
        }
    }

    // MARK: Slot gauche

    @ViewBuilder
    private var leading: some View {
        switch current {
        case .volume:
            levelLabel(icon: volumeManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                       title: volumeManager.isMuted ? "Muet" : "Volume")

        case .brightness:
            levelLabel(icon: brightnessManager.brightness < 0.5 ? "sun.min.fill" : "sun.max.fill",
                       title: "Luminosité")

        case .daw:
            HStack(spacing: 5) {
                BeatPulse(index: ableton.isPlaying ? ableton.beatIndex : nil,
                          downbeat: ableton.isDownbeat,
                          recording: ableton.isRecording, size: 5)
                Text(ableton.setName ?? "Live")
                    .font(NK.ui(9, .semibold))
                    .foregroundStyle(NK.t2)
                    .lineLimit(1)
                if ableton.isSetModified {
                    Circle().fill(NK.warn).frame(width: 4, height: 4)
                }
                if isPeeking {
                    if let track = ableton.live?.track {
                        Text(track.name)
                            .font(NK.ui(9, .medium))
                            .foregroundStyle(AbletonPanel.color(track.color).opacity(0.9))
                            .lineLimit(1)
                    } else if !ableton.isTracking {
                        Text("non synchronisé")
                            .font(NK.ui(9, .medium))
                            .foregroundStyle(NK.t4)
                            .lineLimit(1)
                    }
                }
            }

        case .dawAlert:
            HStack(spacing: 5) {
                Image(systemName: ableton.alert?.kind == .crash ? "exclamationmark.triangle.fill" : "waveform.path.ecg")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(NK.bad)
                Text(ableton.alert?.kind == .crash ? "Live a planté" : "Saturation")
                    .font(NK.ui(9, .semibold))
                    .foregroundStyle(NK.t2)
                    .lineLimit(1)
            }

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
            levelPercent(volumeManager.isMuted ? 0 : volumeManager.volume)

        case .brightness:
            levelPercent(brightnessManager.brightness)

        case .daw:
            HStack(spacing: 7) {
                if ableton.hasScript, ableton.isPlaying, let master = ableton.live?.master {
                    HStack(alignment: .bottom, spacing: 1.5) {
                        StereoBar(value: master.first ?? 0, height: 11, width: 2.5)
                        StereoBar(value: master.last ?? 0, height: 11, width: 2.5)
                    }
                }
                if ableton.isPlaying, let position = ableton.position {
                    Text(position.label)
                        .font(NK.mono(9))
                        .foregroundStyle(ableton.isRecording ? NK.bad : Color.white.opacity(0.8))
                        .monospacedDigit()
                } else if let tempo = ableton.tempo {
                    Text(String(format: "%.0f BPM", tempo))
                        .font(NK.mono(9))
                        .foregroundStyle(NK.t3)
                }
                if isPeeking {
                    barButton(ableton.isRecording ? "record.circle.fill" : "record.circle") { ableton.record() }
                }
                barButton(ableton.isPlaying ? "stop.fill" : "play.fill") { ableton.toggle() }
            }

        case .dawAlert:
            Text(ableton.alert?.kind == .crash ? "récupération au relancement" : "master à 0 dB")
                .font(NK.ui(9, .medium))
                .foregroundStyle(NK.t3)
                .lineLimit(1)

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

    private func levelLabel(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 16)
            Text(title)
                .font(NK.ui(10.5, .semibold))
                .foregroundStyle(NK.t2)
                .lineLimit(1)
        }
    }

    private func levelPercent(_ value: Float) -> some View {
        Text("\(Int((value * 100).rounded())) %")
            .font(NK.mono(11))
            .foregroundStyle(.white)
            .contentTransition(.numericText())
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

/// Jauge du volume ou de la luminosité, dépliée sous l'encoche sur toute la
/// largeur du bandeau : le réglage se lit d'un coup d'œil, comme le HUD natif.
struct LevelDrawer: View {
    let activity: BarActivity
    var volumeManager: VolumeManager = .shared
    var brightnessManager: BrightnessManager = .shared

    private var value: Float {
        switch activity {
        case .brightness: brightnessManager.brightness
        default:          volumeManager.isMuted ? 0 : volumeManager.volume
        }
    }

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.14))
            .frame(height: 7)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.white)
                        .frame(width: proxy.size.width * CGFloat(max(0, min(1, value))))
                        .animation(.spring(response: 0.22, dampingFraction: 0.9), value: value)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 12)
    }
}
