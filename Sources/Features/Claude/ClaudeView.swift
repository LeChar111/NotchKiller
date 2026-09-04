import SwiftUI

struct ClaudeView: View {
    var stateMachine: ClaudeStateMachine

    @State private var hoveredSession: String?

    private var store: ClaudeSessionStore { stateMachine.sessionStore }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !stateMachine.hasActiveSessions {
                emptyState
            } else {
                header
                    .padding(.top, NK.sectionGap)
                sessionsList
                    .padding(.top, 14)
                    .padding(.bottom, 8)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            SectionLabel("Sessions actives")
            Hairline()
            StatusPill(text: HookInstaller.isInstalled() ? "Hooks installés" : "Hooks absents",
                       tint: HookInstaller.isInstalled() ? NK.t3 : NK.warn)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 26))
                .foregroundStyle(NK.t4)
            Text("Aucune session Claude")
                .font(NK.ui(13, .medium))
                .foregroundStyle(NK.t2)
            Text("Lancez Claude Code : l'activité de la session s'affiche ici,\net le survol montre le résumé fourni par Claude.")
                .font(NK.ui(11))
                .foregroundStyle(NK.t3)
                .multilineTextAlignment(.center)

            if !HookInstaller.isInstalled() {
                Button("Installer les hooks") {
                    HookInstaller.installIfNeeded()
                    MCPInstaller.installIfNeeded()
                }
                .font(NK.ui(11, .semibold))
                .buttonStyle(.bordered)
                .tint(NK.accent)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    private var sessionsList: some View {
        AdaptiveScrollView(maxHeight: NotchConstants.maxExpandedContentHeight - 74) {
            VStack(spacing: 14) {
                ForEach(store.sortedSessions) { session in
                    sessionCard(session)
                }
            }
        }
    }

    /// Le filet vertical porte l'état : la couleur se lit en périphérie,
    /// sans avoir à lire le texte.
    private func sessionCard(_ session: ClaudeSessionData) -> some View {
        let isHovered = hoveredSession == session.id

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(session.projectName)
                    .font(NK.ui(12.5, .semibold))
                    .foregroundStyle(NK.t1)
                    .lineLimit(1)

                StatusPill(text: taskLabel(session.task), tint: taskColor(session.task))

                Spacer(minLength: 4)

                Text(session.formattedDuration)
                    .font(NK.mono(10))
                    .foregroundStyle(NK.t3)
            }

            if let prompt = session.lastUserPrompt {
                Text("« \(prompt) »")
                    .font(NK.ui(10.5, .medium))
                    .foregroundStyle(NK.t3)
                    .lineLimit(2)
                    .padding(.top, 6)
            }

            if isHovered {
                summaryBlock(session)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !session.recentEvents.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(session.recentEvents.suffix(3)) { event in
                        activityRow(event)
                    }
                }
                .padding(.top, 7)
            }
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(session.isProcessing ? taskColor(session.task) : NK.line2)
                .frame(width: 2)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredSession = hovering ? session.id : (hoveredSession == session.id ? nil : hoveredSession)
        }
        .animation(.smooth(duration: 0.22), value: isHovered)
    }

    /// Ramène à la fenêtre où la conversation se déroule.
    private func terminalButton(_ session: ClaudeSessionData) -> some View {
        Button {
            TerminalFocus.focus(ancestors: session.ancestorPIDs)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.forward.app.fill")
                    .font(.system(size: 9.5))
                Text(session.terminalName ?? "Terminal")
                    .font(NK.ui(9.5, .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(NK.accent)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(NK.accent.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .help("Revenir à la discussion")
    }

    /// Ce que Claude dit lui-même de la conversation, poussé par l'outil MCP.
    @ViewBuilder
    private func summaryBlock(_ session: ClaudeSessionData) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let summary = session.summary {
                Text(summary)
                    .font(NK.ui(11, .semibold))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = session.summaryDetail {
                    Text(detail)
                        .font(NK.ui(10, .medium))
                        .foregroundStyle(NK.t3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Claude n'a pas encore décrit cette conversation.")
                    .font(NK.ui(10.5, .medium))
                    .foregroundStyle(NK.t3)
            }

            HStack(spacing: 8) {
                if let updated = session.summaryUpdatedAt, session.summary != nil {
                    Text("Résumé par Claude · \(Self.timeFormatter.string(from: updated))")
                        .font(NK.mono(8.5))
                        .foregroundStyle(NK.t4)
                }
                Spacer(minLength: 0)
                requestButton(session)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(session.summary == nil ? Color.white.opacity(0.03) : NK.accent.opacity(0.10))
        )
    }

    /// Dépose une demande que le hook remet à Claude au prochain événement
    /// de la session — un serveur MCP ne peut pas provoquer un tour de lui-même.
    private func requestButton(_ session: ClaudeSessionData) -> some View {
        let pending = session.isSummaryPending

        return Button {
            session.requestSummary()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: pending ? "hourglass" : "sparkles")
                    .font(.system(size: 9))
                Text(pending ? "Demandé…" : (session.summary == nil ? "Demander à Claude" : "Actualiser"))
                    .font(NK.ui(9.5, .semibold))
            }
            .foregroundStyle(pending ? NK.warn : NK.accent)
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background(Capsule().fill((pending ? NK.warn : NK.accent).opacity(0.14)))
        }
        .buttonStyle(.plain)
        .disabled(pending)
        .help(pending
              ? "Claude répondra au prochain outil appelé dans cette session"
              : "Demander à Claude de décrire cette conversation")
    }

    private func activityRow(_ event: SessionEvent) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor(event.status))
                .frame(width: 5, height: 5)

            if let tool = event.tool {
                Text(tool)
                    .font(NK.mono(9.5))
                    .foregroundStyle(NK.t2)
            }

            if let desc = event.description {
                Text(desc)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(NK.t4)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
    }

    private func taskLabel(_ task: ClaudeTask) -> String {
        switch task {
        case .idle:       "Au repos"
        case .working:    "Travaille"
        case .sleeping:   "En veille"
        case .compacting: "Compacte"
        case .waiting:    "En attente"
        }
    }

    private func taskColor(_ task: ClaudeTask) -> Color {
        switch task {
        case .idle:       NK.t3
        case .working:    NK.accent
        case .sleeping:   NK.violet
        case .compacting: NK.hot
        case .waiting:    NK.warn
        }
    }

    private func statusColor(_ status: ToolStatus) -> Color {
        switch status {
        case .running: NK.accent
        case .success: NK.ok
        case .error:   NK.bad
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH:mm"
        return f
    }()
}
