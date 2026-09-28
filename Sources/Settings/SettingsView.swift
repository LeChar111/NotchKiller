import AppKit
import SwiftUI

/// Sections des réglages, affichées comme sous-pages dans la ligne de
/// navigation du panneau.
enum SettingsSection: String, CaseIterable, Identifiable {
    case bar, system, panel, gestures, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bar:        "Bandeau fermé"
        case .system:     "Système"
        case .panel:      "Panneau"
        case .gestures:   "Gestes & haptique"
        case .appearance: "Apparence"
        }
    }
}

struct SettingsView: View {
    var settings: AppSettings
    var section: SettingsSection = .bar

    var body: some View {
        AdaptiveScrollView(maxHeight: NotchConstants.maxExpandedContentHeight - 60) {
            VStack(alignment: .leading, spacing: 0) {
                sectionContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.top, 10)
                    .id(section)
                    .transition(.opacity)

                HStack(spacing: 10) {
                    Button("Réinitialiser") { settings.resetDefaults() }
                        .font(NK.ui(11, .semibold))
                        .foregroundStyle(NK.t2)
                        .padding(.horizontal, 13)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(NK.line2, lineWidth: 1)
                        )
                        .buttonStyle(.plain)

                    Spacer()

                    Text("NotchKiller \(Bundle.main.shortVersion)")
                        .font(NK.mono(9))
                        .foregroundStyle(NK.t4)
                }
                .padding(.top, 16)
                .padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .bar:
            VStack(spacing: 0) {
                toggleRow("Horloge et charge processeur", isOn: bind(\.barShowCPU))
                toggleRow("Titre en cours de lecture", isOn: bind(\.barShowMusic))
                toggleRow("Sessions Claude Code", isOn: bind(\.barShowClaude))
                toggleRow("Annoncer la fin d'une réponse",
                          note: "Tours de moins de 5 s ignorés",
                          isOn: bind(\.barShowClaudeDone))
                toggleRow("Transport d'Ableton Live",
                          note: "Cocher « Sync » sur la sortie MIDI NotchKiller dans Live",
                          isOn: bind(\.barShowDAW))
                toggleRow("Prochain rendez-vous", isOn: bind(\.barShowCalendar), last: true)
            }
        case .system:
            VStack(spacing: 0) {
                toggleRow("Volume et luminosité dans l'encoche", isOn: bind(\.barShowVolumeHUD))
                toggleRow("Remplacer le HUD de macOS",
                          note: "Sinon les deux s'affichent en même temps",
                          isOn: bind(\.replaceSystemHUD))
                toggleRow("Connexions Bluetooth", isOn: bind(\.barShowBluetooth))
                toggleRow("Alertes batterie",
                          note: "Branchement, débranchement, seuil de 20 %",
                          isOn: bind(\.barShowBatteryAlerts))
                toggleRow("Relayer les notifications",
                          note: "Demande l'Accès complet au disque dans Réglages Système",
                          isOn: bind(\.relaySystemNotifications), last: true)
            }
        case .panel:
            VStack(spacing: 0) {
                toggleRow("Aperçu au survol",
                          note: "Le bandeau s'enrichit sans s'ouvrir",
                          isOn: bind(\.hoverPeek))
                toggleRow("Se souvenir du dernier onglet",
                          isOn: bind(\.rememberLastTab))
                toggleRow("Afficher sur tous les écrans",
                          note: screensNote,
                          isOn: bind(\.showOnAllScreens), last: true)
            }
        case .gestures:
            VStack(spacing: 0) {
                toggleRow("Gestes de balayage",
                          note: "Horizontal : activité ou page suivante · vertical : ouvrir, refermer",
                          isOn: bind(\.swipeGestures))
                hapticRow
            }
        case .appearance:
            accentPicker
        }
    }

    /// Chaque niveau joue un exemple au clic : on choisit au ressenti.
    private var hapticRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Retour haptique")
                    .font(NK.ui(11.5, .medium))
                    .foregroundStyle(NK.t1)
                Text("Trackpad Force Touch · chaque niveau joue un exemple")
                    .font(NK.ui(10, .medium))
                    .foregroundStyle(NK.t3)
            }
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                ForEach(HapticLevel.allCases) { level in
                    let active = settings.hapticLevel == level
                    Button {
                        settings.hapticLevel = level
                        Haptics.play(.snap, level: level)
                    } label: {
                        Text(level.title)
                            .font(NK.ui(10.5, .semibold))
                            .foregroundStyle(active ? NK.t1 : NK.t2)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(active ? Color.white.opacity(0.10) : .clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
        }
        .padding(.vertical, 9)
    }

    private var screensNote: String {
        let count = NSScreen.screens.count
        return count > 1
            ? "\(count) écrans connectés — une encoche sur chacun"
            : "Un seul écran connecté pour l'instant"
    }

    private var accentPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Accent")
            HStack(spacing: 8) {
                ForEach(NKAccent.allCases) { theme in
                    Button { settings.accentTheme = theme.rawValue } label: {
                        Circle()
                            .fill(theme.color)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(settings.accentTheme == theme.rawValue ? 0.9 : 0),
                                            lineWidth: 2)
                                    .padding(-3)
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(theme.title)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func bind(_ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }

    private func toggleRow(_ title: String, note: String? = nil,
                           isOn: Binding<Bool>, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(NK.ui(11.5, .medium))
                        .foregroundStyle(NK.t1)
                    if let note {
                        Text(note)
                            .font(NK.ui(10, .medium))
                            .foregroundStyle(NK.t3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                NKToggle(isOn: isOn)
            }
            .padding(.vertical, 9)

            if !last { Hairline() }
        }
    }
}

extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }
}
