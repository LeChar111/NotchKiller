import SwiftUI

struct AgendaPageView: View {
    var model: CalendarModel = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.hasAccess {
                permission
            } else if model.events.isEmpty {
                Text("Rien de prévu dans les 36 prochaines heures.")
                    .font(NK.ui(11, .medium))
                    .foregroundStyle(NK.t3)
                    .padding(.vertical, 20)
            } else {
                HStack(alignment: .top, spacing: 22) {
                    column(Array(model.events.prefix(4)))
                    column(Array(model.events.dropFirst(4).prefix(4)))
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
        .onAppear { model.refresh() }
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("Agenda")
            Text("NotchKiller n'a pas accès à vos calendriers. L'autorisation reste locale : rien n'est envoyé nulle part.")
                .font(NK.ui(11, .medium))
                .foregroundStyle(NK.t3)
                .fixedSize(horizontal: false, vertical: true)
            Button { model.requestAccess() } label: {
                Text("Autoriser l'accès")
                    .font(NK.ui(11, .semibold))
                    .foregroundStyle(NK.accent)
                    .padding(.horizontal, 13)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(NK.accent.opacity(0.14)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
    }

    private func column(_ items: [AgendaEvent]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { event in
                VStack(spacing: 0) {
                    HStack(spacing: 11) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(event.tint)
                            .frame(width: 3, height: 30)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.title)
                                .font(NK.ui(11.5, .semibold))
                                .foregroundStyle(NK.t1)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(event.timeLabel)
                                    .font(NK.mono(9.5))
                                    .foregroundStyle(NK.t3)
                                if let location = event.location {
                                    Text(location)
                                        .font(NK.ui(9.5, .medium))
                                        .foregroundStyle(NK.t4)
                                        .lineLimit(1)
                                }
                            }
                        }

                        Spacer(minLength: 4)

                        Text(event.countdown)
                            .font(NK.ui(9.5, .semibold))
                            .foregroundStyle(event.start.timeIntervalSinceNow < 900 ? NK.warn : NK.t3)
                    }
                    .padding(.vertical, 8)

                    Hairline()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
