import AppKit
import SwiftUI

/// Ce qu'il faut pour que Claude Code parle au widget : les hooks pour l'activité,
/// le serveur MCP pour les descriptions de conversation.
struct ClaudeSetupView: View {
    @State private var hooksInstalled = HookInstaller.isInstalled()
    @State private var mcpInstalled = MCPInstaller.isInstalled()
    @State private var mcpCommand = MCPInstaller.registeredCommand
    @State private var feedback: String?

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: NK.sectionGap) {
                statusBlock(
                    title: "Hooks d'activité",
                    detail: "~/.claude/hooks/notchkiller-hook.sh",
                    ok: hooksInstalled,
                    okLabel: "Installés",
                    koLabel: "Absents",
                    action: "Installer les hooks"
                ) {
                    HookInstaller.installIfNeeded()
                    hooksInstalled = HookInstaller.isInstalled()
                    feedback = hooksInstalled ? "Hooks écrits dans ~/.claude/settings.json" : "Échec de l'écriture"
                }

                statusBlock(
                    title: "Serveur MCP",
                    detail: mcpCommand ?? MCPInstaller.executablePath,
                    ok: mcpInstalled,
                    okLabel: "Déclaré",
                    koLabel: "Non déclaré",
                    action: "Déclarer dans ~/.claude.json"
                ) {
                    MCPInstaller.installIfNeeded()
                    mcpInstalled = MCPInstaller.isInstalled()
                    mcpCommand = MCPInstaller.registeredCommand
                    feedback = mcpInstalled ? "Redémarrez Claude Code pour qu'il charge le serveur" : "Échec de l'écriture"
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: NK.sectionGap) {
                toolBlock
                manualBlock

                if let feedback {
                    HStack(spacing: 7) {
                        Circle().fill(NK.ok).frame(width: 5, height: 5)
                        Text(feedback)
                            .font(NK.ui(10, .medium))
                            .foregroundStyle(NK.t3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(width: 292, alignment: .topLeading)
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
        .onAppear {
            hooksInstalled = HookInstaller.isInstalled()
            mcpInstalled = MCPInstaller.isInstalled()
            mcpCommand = MCPInstaller.registeredCommand
        }
    }

    private func statusBlock(
        title: String, detail: String, ok: Bool,
        okLabel: String, koLabel: String, action: String,
        perform: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SectionLabel(title)
                StatusPill(text: ok ? okLabel : koLabel, tint: ok ? NK.ok : NK.warn)
                Spacer(minLength: 0)
            }

            Text(detail)
                .font(NK.mono(9.5))
                .foregroundStyle(NK.t4)
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: perform) {
                Text(ok ? "Réinstaller" : action)
                    .font(NK.ui(11, .semibold))
                    .foregroundStyle(ok ? NK.t2 : NK.accent)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(ok ? Color.white.opacity(0.05) : NK.accent.opacity(0.14))
                    )
            }
            .buttonStyle(.plain)

            Hairline()
        }
    }

    private var toolBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Outil exposé")
            Text("set_session_summary")
                .font(NK.mono(11))
                .foregroundStyle(NK.t1)
            Text("Claude décrit lui-même la conversation en cours ; la description s'affiche au survol d'une session.")
                .font(NK.ui(10.5, .medium))
                .foregroundStyle(NK.t3)
                .fixedSize(horizontal: false, vertical: true)
            Hairline()
        }
    }

    private var manualBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Déclaration manuelle")
            Text(MCPInstaller.manualCommand)
                .font(NK.mono(9))
                .foregroundStyle(NK.t4)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(MCPInstaller.manualCommand, forType: .string)
                feedback = "Commande copiée"
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Copier la commande")
                        .font(NK.ui(11, .semibold))
                }
                .foregroundStyle(NK.t2)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
            }
            .buttonStyle(.plain)
        }
    }
}
