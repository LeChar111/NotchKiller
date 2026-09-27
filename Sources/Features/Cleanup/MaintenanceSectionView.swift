import SwiftUI

/// Bas de la page Nettoyage : état des disques, purge des caches d'apps,
/// plug-ins audio déportés sur un disque externe et entretien hebdomadaire.
struct MaintenanceSectionView: View {
    var model: MaintenanceModel = .shared

    @State private var pending: String?
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            HStack(alignment: .top, spacing: 12) {
                cachesCard
                audioCard
                agentCard
            }
            // Hauteur idéale de la plus haute carte ; les autres s'alignent dessus.
            .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { model.refresh() }
        .onDisappear { cancelPending() }
    }

    // MARK: En-tête — les deux disques

    private var header: some View {
        HStack(spacing: 10) {
            SectionLabel("Maintenance")

            diskChip(name: "Mac", free: model.internalFree, mounted: true,
                     tint: model.internalFree < 30 * 1_073_741_824 ? NK.warn : NK.ok)
            if let name = model.externalName {
                diskChip(name: name, free: model.externalFree ?? 0, mounted: model.externalFree != nil,
                         tint: model.externalFree == nil ? NK.bad : NK.ok)
            }

            Spacer(minLength: 0)

            if let action = model.lastAction {
                Text(action)
                    .font(NK.ui(9.5, .medium))
                    .foregroundStyle(NK.t4)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func diskChip(name: String, free: Double, mounted: Bool, tint: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(name)
                .font(NK.ui(9.5, .semibold))
                .foregroundStyle(NK.t2)
            Text(mounted ? "\(Shell.formatBytes(free)) libres" : "débranché")
                .font(NK.mono(9.5))
                .foregroundStyle(mounted ? NK.t3 : NK.bad)
        }
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Capsule().fill(Color.white.opacity(0.05)))
    }

    // MARK: Caches d'apps

    private var cachesCard: some View {
        card(title: "Caches d'apps", icon: "internaldrive") {
            if !model.cachesScanned {
                note("Caches de ~/Library, caches Electron des apps fermées et temporaires de plus de 3 jours. Les apps ouvertes ne sont jamais touchées.")
            } else if model.caches.isEmpty {
                note("Rien à purger au-delà de 1 Mo.")
            } else {
                metric(Shell.formatBytes(model.cachesTotal), "\(model.caches.count) cache\(model.caches.count > 1 ? "s" : "")")
                VStack(spacing: 0) {
                    ForEach(model.caches.prefix(3)) { item in
                        HStack {
                            Text(item.name)
                                .font(NK.ui(10, .medium))
                                .foregroundStyle(NK.t2)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 6)
                            Text(Shell.formatBytes(item.bytes))
                                .font(NK.mono(9.5))
                                .foregroundStyle(NK.t3)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        } actions: {
            pill(model.isScanningCaches ? "Analyse…" : (model.cachesScanned ? "Réanalyser" : "Analyser"),
                 icon: model.isScanningCaches ? "hourglass" : "magnifyingglass") { model.scanCaches() }
                .disabled(model.isScanningCaches)
            if model.cachesScanned && !model.caches.isEmpty {
                confirmPill(id: "purge", title: "Purger", armedTitle: "Confirmer · \(Shell.formatBytes(model.cachesTotal))",
                            icon: "trash") { model.purgeCaches() }
            }
        }
    }

    // MARK: Plug-ins audio

    private var audioCard: some View {
        let audio = model.audio
        return card(title: "Plug-ins audio", icon: "pianokeys") {
            if model.audioDest.isEmpty {
                note("VST, VST3, AU, CLAP, AAX et données des éditeurs (banques de sons, iZotope, Native Instruments…) déplacés sur un disque externe, remplacés par des liens : les DAW les retrouvent au même endroit.")
            } else {
                metric("\(audio.onMac)", "sur le Mac · \(Shell.formatBytes(Double(audio.onMacKB) * 1024))",
                       trailing: "\(audio.onDest) déplacés")
                if let onMac = audio.supportOnMac {
                    statusLine(onMac == 0 ? NK.ok : NK.t4,
                               onMac == 0
                                   ? "Données des éditeurs : \(audio.supportOnDest ?? 0) dossier(s) sur le disque"
                                   : "Données des éditeurs : \(onMac) dossier(s) sur le Mac · \(Shell.formatBytes(Double(audio.supportOnMacKB ?? 0) * 1024))")
                }
                statusLine(audio.watching ? NK.ok : NK.t4,
                           audio.watching ? "Surveillance active — les nouveaux plug-ins suivent" : "Surveillance inactive")
                if audio.state == "denied" {
                    statusLine(NK.bad, "macOS bloque l'écriture sur le disque — lancer depuis un terminal")
                }
                if audio.intruders > 0 {
                    statusLine(NK.warn, "\(audio.intruders) fichiers étrangers dans les dossiers de plug-ins")
                }
                if model.audioRunning || audio.state == "running" {
                    progress(audio)
                } else {
                    Text(model.audioDest.replacingOccurrences(of: "/Volumes/", with: ""))
                        .font(NK.mono(8.5))
                        .foregroundStyle(NK.t4)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
        } actions: {
            if model.audioDest.isEmpty {
                pill("Choisir le disque…", icon: "externaldrive") { model.chooseAudioDest() }
            } else {
                pill(model.audioRunning ? "En cours…" : "Déplacer", icon: "arrow.right.doc.on.clipboard") { model.runAudio(.move) }
                    .disabled(model.audioRunning)
                pill(audio.watching ? "Surveillé" : "Surveiller", icon: audio.watching ? "eye.fill" : "eye",
                     tint: audio.watching ? NK.ok : NK.accent) { model.runAudio(audio.watching ? .unwatch : .watch) }
                    .disabled(model.audioRunning)
                Menu {
                    Button("Mettre les fichiers étrangers en quarantaine") { model.runAudio(.quarantine) }
                        .disabled(audio.intruders == 0)
                    Button("Tout rapatrier sur le Mac") { model.runAudio(.restore) }
                    Divider()
                    Button("Changer de dossier…") { model.chooseAudioDest() }
                    Button("Ouvrir le journal") { model.openAudioLog() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(NK.t2)
                        .frame(width: 26, height: 22)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .contentShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(model.audioRunning)
            }
        }
    }

    private func progress(_ audio: AudioOffloadStatus) -> some View {
        let fraction = audio.total > 0 ? Double(audio.done) / Double(audio.total) : 0
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(NK.accent).frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 4)
            .animation(.easeOut(duration: 0.3), value: fraction)
            HStack(spacing: 6) {
                Text(audio.total > 0 ? "\(audio.done)/\(audio.total)" : "Autorisation…")
                    .font(NK.mono(9))
                    .foregroundStyle(NK.t2)
                Text(audio.current)
                    .font(NK.ui(9, .medium))
                    .foregroundStyle(NK.t3)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    // MARK: Entretien hebdomadaire

    private var agentCard: some View {
        card(title: "Entretien hebdo", icon: "calendar.badge.clock") {
            if !model.agentInstalled {
                note("Chaque lundi à 10 h : temporaires, simulateurs orphelins, Homebrew, mises à jour en attente. Alerte sous 30 Go libres ou si le disque externe est débranché.")
            } else {
                statusLine(NK.ok, "Actif · lundi 10 h")
                if let run = model.lastRun, run.lastRun > 0 {
                    metric("\(run.freeGB) Go", "libres après le dernier passage", trailing: "+\(run.freedMB) Mo")
                    Text("Dernier passage \(Self.relative(run.lastRun))")
                        .font(NK.ui(9.5, .medium))
                        .foregroundStyle(NK.t3)
                } else {
                    note("Pas encore passé — « Lancer » pour un premier passage.")
                }
            }
        } actions: {
            pill("Lancer", icon: "play.fill") { model.runAgentNow() }
            if model.agentInstalled {
                pill("Journal", icon: "doc.text") { model.openAgentLog() }
                confirmPill(id: "agent-off", title: "Désactiver", armedTitle: "Confirmer", icon: "power") { model.removeAgent() }
            } else {
                pill("Activer", icon: "checkmark") { model.installAgent() }
            }
        }
    }

    // MARK: Briques

    private func card<Content: View, Actions: View>(title: String, icon: String,
                                                    @ViewBuilder content: () -> Content,
                                                    @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NK.t3)
                Text(title)
                    .font(NK.ui(11, .semibold))
                    .foregroundStyle(NK.t1)
            }
            VStack(alignment: .leading, spacing: 6) { content() }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            Spacer(minLength: 0)
            HStack(spacing: 6) { actions() }
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: NK.radiusCard, style: .continuous).fill(NK.surface))
    }

    private func metric(_ value: String, _ caption: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(NK.mono(15))
                .foregroundStyle(NK.t1)
            Text(caption)
                .font(NK.ui(9.5, .medium))
                .foregroundStyle(NK.t3)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(NK.mono(9.5))
                    .foregroundStyle(NK.t2)
            }
        }
    }

    private func statusLine(_ tint: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(text)
                .font(NK.ui(9.5, .medium))
                .foregroundStyle(NK.t2)
                .lineLimit(1)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(NK.ui(10, .medium))
            .foregroundStyle(NK.t3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func pill(_ title: String, icon: String, tint: Color = NK.accent, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 9, weight: .semibold))
                Text(title).font(NK.ui(9.5, .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(tint.opacity(0.14)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Premier clic : arme ; second clic dans les 4 s : exécute.
    private func confirmPill(id: String, title: String, armedTitle: String, icon: String,
                             action: @escaping () -> Void) -> some View {
        let armed = pending == id
        return pill(armed ? armedTitle : title, icon: armed ? "exclamationmark.triangle.fill" : icon,
                    tint: armed ? NK.bad : NK.t3) {
            if armed { action(); cancelPending() } else { arm(id) }
        }
    }

    private func arm(_ id: String) {
        cancelPending()
        pending = id
        resetTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            pending = nil
        }
    }

    private func cancelPending() {
        resetTask?.cancel()
        resetTask = nil
        pending = nil
    }

    private static func relative(_ timestamp: Double) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: Date(timeIntervalSince1970: timestamp), relativeTo: Date())
    }
}
