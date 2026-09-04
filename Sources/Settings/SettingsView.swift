import AppKit
import SwiftUI

struct SettingsView: View {
    var settings: AppSettings

    @State private var confirmQuit = false
    @State private var confirmTask: Task<Void, Never>?

    var body: some View {
        AdaptiveScrollView(maxHeight: NotchConstants.maxExpandedContentHeight - 60) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 24) {
                    group("Bandeau fermé") {
                        toggleRow("Horloge et charge processeur", isOn: bind(\.barShowCPU))
                        toggleRow("Titre en cours de lecture", isOn: bind(\.barShowMusic))
                        toggleRow("Sessions Claude Code", isOn: bind(\.barShowClaude))
                        toggleRow("Annoncer la fin d'une réponse",
                                  note: "Tours de moins de 5 s ignorés",
                                  isOn: bind(\.barShowClaudeDone))
                        toggleRow("Prochain rendez-vous", isOn: bind(\.barShowCalendar), last: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    group("Système") {
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
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: NK.sectionGap) {
                        group("Panneau") {
                            toggleRow("Aperçu au survol",
                                      note: "Le bandeau s'enrichit sans s'ouvrir",
                                      isOn: bind(\.hoverPeek))
                            toggleRow("Gestes de balayage",
                                      note: "Horizontal : activité suivante · vertical : ouvrir",
                                      isOn: bind(\.swipeGestures))
                            toggleRow("Se souvenir du dernier onglet",
                                      isOn: bind(\.rememberLastTab))
                            toggleRow("Afficher sur tous les écrans",
                                      note: screensNote,
                                      isOn: bind(\.showOnAllScreens), last: true)
                        }
                        accentPicker
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .padding(.top, 4)

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

                    quitButton

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

    /// Quitter est irréversible pour la session : on demande une confirmation
    /// plutôt qu'un dialogue système, qui volerait le focus au panneau.
    private var quitButton: some View {
        Button {
            if confirmQuit {
                NSApp.terminate(nil)
            } else {
                confirmQuit = true
                confirmTask?.cancel()
                confirmTask = Task {
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled else { return }
                    confirmQuit = false
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: confirmQuit ? "exclamationmark.triangle.fill" : "power")
                    .font(.system(size: 10, weight: .semibold))
                Text(confirmQuit ? "Confirmer" : "Quitter NotchKiller")
                    .font(NK.ui(11, .semibold))
            }
            .foregroundStyle(NK.bad)
            .padding(.horizontal, 13)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(NK.bad.opacity(confirmQuit ? 0.18 : 0.10))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("L'app se relancera à la prochaine ouverture de session")
    }

    private func bind(_ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title)
            VStack(spacing: 0) { content() }
        }
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
