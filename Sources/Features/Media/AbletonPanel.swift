import AppKit
import SwiftUI

/// Page Média quand la source est Ableton Live : transport, niveaux, piste
/// sélectionnée, repères, grille de clips, projets récents et installation du
/// script d'extension. Tout ce qui dépend du script reste visible mais éteint
/// sans lui, avec l'explication pour l'activer.
struct AbletonPanel: View {
    var ableton: AbletonTransport = .shared
    var bridge: AbletonBridge = .shared
    var recents: AbletonRecents = .shared

    @State private var scriptInstalled = AbletonBridge.isScriptInstalled
    @State private var installNote: String?

    private var live: LiveState? { ableton.live }
    private var scripted: Bool { ableton.hasScript }

    var body: some View {
        VStack(alignment: .leading, spacing: NK.sectionGap) {
            header
            transport
            if scripted, let live {
                HStack(alignment: .top, spacing: 22) {
                    levels(live)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    selectedTrack(live.track)
                        .frame(width: 320, alignment: .topLeading)
                }
                if !live.cues.isEmpty { cues(live) }
                if !live.grid.isEmpty { clipGrid(live) }
            }
            HStack(alignment: .top, spacing: 22) {
                recentProjects
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: NK.sectionGap) {
                    todayStats
                    setup
                }
                .frame(width: 320, alignment: .topLeading)
            }
        }
        .onAppear {
            recents.refresh()
            scriptInstalled = AbletonBridge.isScriptInstalled
        }
    }

    // MARK: En-tête

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(ableton.isRunning ? (ableton.isPlaying ? NK.ok : NK.t3) : NK.t4)
                .frame(width: 7, height: 7)
            Text(ableton.setName ?? (ableton.isRunning ? "Live" : "Live n'est pas ouvert"))
                .font(NK.ui(14, .semibold))
                .foregroundStyle(NK.t1)
                .lineLimit(1)
            if ableton.isSetModified {
                Text("non enregistré")
                    .font(NK.ui(9.5, .semibold))
                    .foregroundStyle(NK.warn)
                    .padding(.horizontal, 7)
                    .frame(height: 18)
                    .background(Capsule().fill(NK.warn.opacity(0.14)))
                pill("square.and.arrow.down", "Enregistrer", help: "⌘S dans Live") { ableton.save() }
            }
            Spacer(minLength: 8)
            if let cpu = ableton.cpu {
                stat("CPU", String(format: "%.0f %%", cpu), tint: cpu > 150 ? NK.bad : NK.t2)
            }
            if let memory = ableton.memory {
                stat("RAM", Shell.formatBytes(memory), tint: NK.t2)
            }
            sourceChip
            pill("rectangle.split.2x1", "Session / Arrangement", help: "Tab dans Live") { ableton.switchView() }
                .disabled(!ableton.isRunning)
        }
    }

    private var sourceChip: some View {
        let (label, tint): (String, Color) = scripted ? ("script", NK.ok)
            : ableton.isSynced ? ("sync MIDI", NK.accent) : ("hors ligne", NK.t4)
        return Text(label)
            .font(NK.mono(9))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(Capsule().fill(tint.opacity(0.12)))
    }

    private func stat(_ label: String, _ value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).font(NK.ui(9, .semibold)).foregroundStyle(NK.t4)
            Text(value).font(NK.mono(10)).foregroundStyle(tint)
        }
    }

    // MARK: Transport

    private var transport: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                roundButton(ableton.isRecording ? "record.circle.fill" : "record.circle",
                            active: ableton.isRecording, tint: NK.bad, size: 36,
                            help: "Enregistrer (F9)") { ableton.record() }
                roundButton(ableton.isPlaying ? "stop.fill" : "play.fill",
                            active: ableton.isPlaying, tint: NK.ok, size: 44,
                            help: ableton.isPlaying ? "Arrêter" : "Lire") { ableton.toggle() }
                roundButton("playpause.fill", active: false, tint: NK.ok, size: 36,
                            help: "Reprendre là où la lecture s'est arrêtée (⇧ Espace)") { ableton.continuePlaying() }
            }
            .disabled(!ableton.isRunning)
            .opacity(ableton.isRunning ? 1 : 0.4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    BeatPulse(index: ableton.beatIndex, downbeat: ableton.isDownbeat,
                              recording: ableton.isRecording && ableton.isPlaying, size: 9)
                    Text(ableton.position?.label ?? "–.–.–")
                        .font(NK.mono(20))
                        .foregroundStyle(NK.t1)
                        .monospacedDigit()
                }
                HStack(spacing: 8) {
                    if let live { Text("\(live.num)/\(live.den)").font(NK.mono(10)).foregroundStyle(NK.t3) }
                    if let remaining = ableton.remaining {
                        Text("fin dans \(Self.clock(remaining))").font(NK.mono(10)).foregroundStyle(NK.t3)
                    }
                }
            }
            .frame(minWidth: 150, alignment: .leading)

            tempoControl

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                toggle("metronome", active: live?.metronome, help: "Métronome") { ableton.send("metronome") }
                toggle("repeat", active: live?.loop, help: "Boucle") { ableton.send("loop") }
                toggle("arrow.right.to.line", active: live?.punchIn, help: "Punch-in") { ableton.send("punch_in") }
                toggle("arrow.left.to.line", active: live?.punchOut, help: "Punch-out") { ableton.send("punch_out") }
                toggle("square.stack.3d.down.forward", active: live?.overdub, help: "Overdub MIDI de l'arrangement") {
                    ableton.send("overdub")
                }
                toggle("record.circle", active: live?.sessionRecord, tint: NK.bad,
                       help: "Enregistrement en Session") { ableton.send("session_record") }
                Divider().frame(height: 18).overlay(NK.line)
                toggle("arrow.uturn.backward", active: nil, enabled: ableton.isRunning && (live?.canUndo ?? true),
                       help: "Annuler") { ableton.undo() }
                toggle("arrow.uturn.forward", active: nil, enabled: ableton.isRunning && (live?.canRedo ?? true),
                       help: "Rétablir") { ableton.redo() }
            }
        }
    }

    private var tempoControl: some View {
        HStack(spacing: 4) {
            smallButton("minus", enabled: scripted, help: "−1 BPM (⌥ : −0,1)") {
                ableton.nudgeTempo(NSEvent.modifierFlags.contains(.option) ? -0.1 : -1)
            }
            VStack(spacing: 0) {
                Text(ableton.tempo.map { String(format: "%.2f", $0) } ?? "—")
                    .font(NK.mono(14))
                    .foregroundStyle(NK.t1)
                Text("BPM").font(NK.ui(8, .semibold)).foregroundStyle(NK.t4)
            }
            .frame(width: 66)
            smallButton("plus", enabled: scripted, help: "+1 BPM (⌥ : +0,1)") {
                ableton.nudgeTempo(NSEvent.modifierFlags.contains(.option) ? 0.1 : 1)
            }
            pill("hand.tap", "Tap", help: "Tap tempo") { ableton.send("tap_tempo") }
                .disabled(!scripted)
                .opacity(scripted ? 1 : 0.4)
        }
    }

    // MARK: Niveaux

    private func levels(_ live: LiveState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Niveaux")
            HStack(alignment: .bottom, spacing: 10) {
                meterColumn("Master", l: live.master.first ?? 0, r: live.master.last ?? 0,
                            color: NK.t1, muted: false, height: 64)
                if !live.groups.isEmpty {
                    Divider().frame(height: 64).overlay(NK.line)
                }
                ForEach(Array(live.groups.enumerated()), id: \.offset) { _, group in
                    meterColumn(group.name, l: group.l, r: group.r,
                                color: Self.color(group.color), muted: group.mute, height: 64)
                }
            }
        }
    }

    private func meterColumn(_ name: String, l: Double, r: Double, color: Color, muted: Bool, height: CGFloat) -> some View {
        VStack(spacing: 5) {
            HStack(alignment: .bottom, spacing: 2) {
                StereoBar(value: l, height: height)
                StereoBar(value: r, height: height)
            }
            .opacity(muted ? 0.35 : 1)
            HStack(spacing: 3) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(name)
                    .font(NK.ui(8.5, .semibold))
                    .foregroundStyle(NK.t3)
                    .lineLimit(1)
            }
            .frame(width: 56)
        }
    }

    // MARK: Piste sélectionnée

    private func selectedTrack(_ track: LiveState.Track) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Piste sélectionnée")
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3).fill(Self.color(track.color)).frame(width: 6, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name).font(NK.ui(12, .semibold)).foregroundStyle(NK.t1).lineLimit(1)
                    Text(track.clip ?? "aucun clip en surbrillance")
                        .font(NK.ui(10, .medium)).foregroundStyle(NK.t3).lineLimit(1)
                }
                Spacer(minLength: 4)
                HStack(alignment: .bottom, spacing: 2) {
                    StereoBar(value: track.l, height: 30)
                    StereoBar(value: track.r, height: 30)
                }
            }
            if !track.master {
                HStack(spacing: 6) {
                    trackToggle("Arm", active: track.arm, tint: NK.bad, enabled: track.canArm) { ableton.send("arm") }
                    trackToggle("Solo", active: track.solo, tint: NK.accent, enabled: true) { ableton.send("solo") }
                    trackToggle("Mute", active: track.mute, tint: NK.warn, enabled: true) { ableton.send("mute") }
                }
            }
        }
    }

    private func trackToggle(_ label: String, active: Bool, tint: Color, enabled: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(NK.ui(10, .semibold))
                .foregroundStyle(active ? Color.black : NK.t2)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(active ? tint : Color.white.opacity(0.06)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    // MARK: Repères

    private func cues(_ live: LiveState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Repères")
                Spacer()
                smallButton("chevron.left", enabled: true, help: "Repère précédent") { ableton.send("cue_prev") }
                smallButton("chevron.right", enabled: true, help: "Repère suivant") { ableton.send("cue_next") }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(live.cues.enumerated()), id: \.offset) { index, cue in
                        let passed = live.time >= cue.time
                        let current = live.cues.lastIndex { $0.time <= live.time }
                        Button { ableton.send("cue", ["value": index]) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "flag.fill").font(.system(size: 8))
                                Text(cue.name.isEmpty ? "Repère \(index + 1)" : cue.name)
                                    .font(NK.ui(10, .semibold))
                            }
                            .foregroundStyle(current == index ? NK.t1 : passed ? NK.t3 : NK.t2)
                            .padding(.horizontal, 9)
                            .frame(height: 22)
                            .background(Capsule().fill(current == index ? NK.accent.opacity(0.22) : Color.white.opacity(0.05)))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Grille de clips

    private func clipGrid(_ live: LiveState) -> some View {
        let trackOffset = live.offset.first ?? 0
        let sceneOffset = live.offset.last ?? 0
        let totalTracks = live.size.first ?? 0
        let totalScenes = live.size.last ?? 0
        let cell: CGFloat = 26

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                SectionLabel("Session")
                Text("pistes \(trackOffset + 1)–\(trackOffset + live.grid.count) / \(totalTracks) · scènes \(sceneOffset + 1)–\(sceneOffset + live.scenes.count) / \(totalScenes)")
                    .font(NK.mono(9))
                    .foregroundStyle(NK.t4)
                Spacer()
                smallButton("chevron.left", enabled: trackOffset > 0, help: "Pistes précédentes") {
                    page(track: trackOffset - 8, scene: sceneOffset)
                }
                smallButton("chevron.right", enabled: trackOffset + 8 < totalTracks, help: "Pistes suivantes") {
                    page(track: trackOffset + 8, scene: sceneOffset)
                }
                smallButton("chevron.up", enabled: sceneOffset > 0, help: "Scènes précédentes") {
                    page(track: trackOffset, scene: sceneOffset - 8)
                }
                smallButton("chevron.down", enabled: sceneOffset + 8 < totalScenes, help: "Scènes suivantes") {
                    page(track: trackOffset, scene: sceneOffset + 8)
                }
                pill("stop.fill", "Tout arrêter", help: "Arrêter tous les clips") { ableton.send("stop_all_clips") }
            }

            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                GridRow {
                    Color.clear.frame(width: 110, height: 1)
                    ForEach(Array(live.grid.enumerated()), id: \.offset) { index, column in
                        Button { ableton.send("stop_track", ["value": trackOffset + index]) } label: {
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 1.5).fill(Self.color(column.color)).frame(width: 3, height: 12)
                                Text(column.name).font(NK.ui(9, .semibold)).foregroundStyle(NK.t2).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Arrêter les clips de \(column.name)")
                    }
                }
                ForEach(Array(live.scenes.enumerated()), id: \.offset) { row, scene in
                    GridRow {
                        Button { ableton.send("fire_scene", ["value": sceneOffset + row]) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "play.fill").font(.system(size: 7))
                                    .foregroundStyle(scene.triggered ? NK.ok : NK.t3)
                                Text(scene.name.isEmpty ? "Scène \(sceneOffset + row + 1)" : scene.name)
                                    .font(NK.ui(9.5, .semibold))
                                    .foregroundStyle(NK.t2)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 7)
                            .frame(width: 110, height: cell, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.05)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        ForEach(Array(live.grid.enumerated()), id: \.offset) { column, track in
                            clipCell(row < track.clips.count ? track.clips[row] : nil, height: cell) {
                                ableton.send("fire_clip", ["track": trackOffset + column, "scene": sceneOffset + row])
                            }
                        }
                    }
                }
            }
        }
    }

    private func clipCell(_ clip: LiveState.Clip?, height: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(clip.map { Self.color($0.color).opacity($0.state >= 2 ? 0.95 : 0.45) } ?? Color.white.opacity(0.03))
                if let clip {
                    HStack(spacing: 4) {
                        switch clip.state {
                        case 3: Image(systemName: "record.circle.fill").foregroundStyle(NK.bad)
                        case 2: Image(systemName: "play.fill").foregroundStyle(Color.black)
                        case 1: Image(systemName: "play").foregroundStyle(NK.t1)
                        default: EmptyView()
                        }
                        Text(clip.name)
                            .foregroundStyle(clip.state >= 2 ? Color.black : NK.t1)
                            .lineLimit(1)
                    }
                    .font(NK.ui(9, .semibold))
                    .padding(.horizontal, 6)
                }
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(clip == nil ? "Emplacement vide — arrête la piste" : "Lancer \(clip?.name ?? "")")
    }

    private func page(track: Int, scene: Int) {
        ableton.send("grid", ["track": max(0, track), "scene": max(0, scene)])
    }

    // MARK: Projets récents

    private var recentProjects: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Projets récents")
                Spacer()
                smallButton("arrow.clockwise", enabled: !recents.isLoading, help: "Actualiser") { recents.refresh() }
            }
            if recents.projects.isEmpty {
                Text(recents.isLoading ? "Recherche des sets…" : "Aucun set trouvé par Spotlight.")
                    .font(NK.ui(11, .medium))
                    .foregroundStyle(NK.t3)
            } else {
                let items = recents.projects
                HStack(alignment: .top, spacing: 18) {
                    projectColumn(Array(items.prefix((items.count + 1) / 2)))
                    projectColumn(Array(items.dropFirst((items.count + 1) / 2)))
                }
            }
        }
    }

    private func projectColumn(_ items: [AbletonRecents.Project]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { project in
                Button { ableton.open(project.url) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(NK.t3)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(project.name).font(NK.ui(11, .semibold)).foregroundStyle(NK.t1).lineLimit(1)
                            Text(project.folder).font(NK.ui(9, .medium)).foregroundStyle(NK.t4).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(project.lastUsed, format: .relative(presentation: .named))
                            .font(NK.ui(9, .medium))
                            .foregroundStyle(NK.t4)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(project.url.path)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: Temps de travail

    private var todayStats: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Aujourd'hui dans Live")
            HStack(spacing: 16) {
                statBlock("ouvert", ableton.today.open, tint: NK.t2)
                statBlock("en lecture", ableton.today.playing, tint: NK.ok)
                statBlock("en enregistrement", ableton.today.recording, tint: NK.bad)
            }
        }
    }

    private func statBlock(_ label: String, _ seconds: TimeInterval, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Self.duration(seconds)).font(NK.mono(13)).foregroundStyle(tint)
            Text(label).font(NK.ui(9, .medium)).foregroundStyle(NK.t4)
        }
    }

    // MARK: Installation

    @ViewBuilder
    private var setup: some View {
        if !scripted || bridge.needsUpdate || !AXIsProcessTrusted() {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Configuration")
                if !scriptInstalled || bridge.needsUpdate {
                    note("Le script d'extension donne à NotchKiller l'accès à tout le set : tempo, boucle, pistes, clips, niveaux.")
                    pill("puzzlepiece.extension", bridge.needsUpdate ? "Mettre à jour le script" : "Installer le script dans Live",
                         help: AbletonBridge.remoteScriptsFolder.path) {
                        let ok = AbletonBridge.installScript()
                        scriptInstalled = AbletonBridge.isScriptInstalled
                        installNote = ok ? "Installé — relancez Live puis choisissez-le comme Control Surface."
                                         : "Échec de la copie dans \(AbletonBridge.remoteScriptsFolder.path)"
                    }
                } else if !scripted {
                    note("Dans Live : Préférences → Link, Tempo & MIDI → Control Surface → « NotchKiller ». Relancez Live s'il n'apparaît pas.")
                }
                if let installNote { note(installNote) }
                if !scripted && !ableton.isSynced {
                    note("Sans script, cochez « Sync » sur la sortie MIDI NotchKiller pour suivre la lecture et la position.")
                }
                if !AXIsProcessTrusted() {
                    note("Raccourcis (Tab, ⌘S, F9…) et nom du set : autorisez NotchKiller dans Réglages → Confidentialité → Accessibilité.")
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(NK.ui(10, .medium))
            .foregroundStyle(NK.t3)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Fragments

    private func roundButton(_ icon: String, active: Bool, tint: Color, size: CGFloat, help: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(active ? Color.black : NK.t1)
                .frame(width: size, height: size)
                .background(Circle().fill(active ? tint : Color.white.opacity(0.09)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Bascule du set : allumée, éteinte, ou grisée (`active == nil` pour une
    /// simple action ; sans script, les bascules sont inaccessibles).
    private func toggle(_ icon: String, active: Bool?, tint: Color = NK.accent, enabled: Bool? = nil,
                        help: String, action: @escaping () -> Void) -> some View {
        let isEnabled = enabled ?? scripted
        let on = active ?? false
        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? Color.black : NK.t2)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(on ? tint : Color.white.opacity(0.06)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.3)
        .help(help)
    }

    private func smallButton(_ icon: String, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(NK.t2)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .help(help)
    }

    private func pill(_ icon: String, _ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 9, weight: .semibold))
                Text(title).font(NK.ui(9.5, .semibold))
            }
            .foregroundStyle(NK.t2)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Outils

    /// Couleur Live (entier 0xRRGGBB).
    static func color(_ value: Int) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        return minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min"
    }
}

/// Barre de niveau verticale : vert, orange au-delà de −6 dB environ, rouge à
/// la saturation.
struct StereoBar: View {
    let value: Double
    var height: CGFloat
    var width: CGFloat = 4

    var body: some View {
        let clamped = max(0, min(1, value))
        let tint: Color = clamped >= 0.999 ? NK.bad : clamped > 0.85 ? NK.hot : NK.ok
        Capsule()
            .fill(Color.white.opacity(0.08))
            .frame(width: width, height: height)
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(tint)
                    .frame(width: width, height: height * clamped)
            }
            .animation(.linear(duration: 0.1), value: clamped)
    }
}

/// Point qui pulse à chaque temps : plus fort sur le premier temps de la
/// mesure, rouge pendant l'enregistrement.
struct BeatPulse: View {
    let index: Int?
    let downbeat: Bool
    let recording: Bool
    var size: CGFloat = 6

    @State private var flash = false

    var body: some View {
        Circle()
            .fill(recording ? NK.bad : NK.ok)
            .frame(width: size, height: size)
            .scaleEffect(flash ? (downbeat ? 1.5 : 1.2) : 1)
            .opacity(index == nil ? 0.3 : (flash ? 1 : 0.55))
            .onChange(of: index) { _, value in
                guard value != nil else { return }
                flash = true
                withAnimation(.easeOut(duration: 0.22)) { flash = false }
            }
    }
}
