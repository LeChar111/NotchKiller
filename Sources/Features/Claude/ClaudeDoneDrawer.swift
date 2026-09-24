import SwiftUI

/// Tiroir déplié sous l'encoche fermée quand une discussion termine son tour :
/// de quoi elle parlait et ce qui vient d'être fait, sans ouvrir le panneau.
/// Un clic ramène au terminal de la session.
struct ClaudeDoneDrawer: View {
    let notice: ClaudeSessionStore.FinishedNotice
    var store: ClaudeSessionStore = .shared
    var activities: BarActivities = .shared

    private var session: ClaudeSessionData? { store.sessions[notice.sessionId] }

    var body: some View {
        let description = session?.currentDescription

        Button {
            if let session { TerminalFocus.focus(ancestors: session.ancestorPIDs) }
            activities.dismissTransient()
            store.clearFinishedNotice()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(description?.text ?? session?.lastUserPrompt ?? "Tour terminé")
                    .font(NK.ui(10.5, .semibold))
                    .foregroundStyle(NK.t1)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = description?.detail {
                    Text(detail)
                        .font(NK.ui(9.5, .medium))
                        .foregroundStyle(NK.t2)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let prompt = session?.lastUserPrompt, prompt != description?.text {
                    Text("« \(prompt) »")
                        .font(NK.ui(9.5, .medium))
                        .foregroundStyle(NK.t3)
                        .lineLimit(2)
                }

                HStack(spacing: 5) {
                    Text("Terminé en \(Self.duration(notice.duration))")
                    Spacer(minLength: 0)
                    Text("Revenir")
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 7.5, weight: .bold))
                }
                .font(NK.mono(8.5))
                .foregroundStyle(NK.t3)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return total < 60 ? "\(total) s" : String(format: "%d min %02d s", total / 60, total % 60)
    }
}
