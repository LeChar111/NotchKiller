import SwiftUI

struct ClipboardPageView: View {
    var model: ClipboardModel = .shared

    @State private var hovered: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SectionLabel("Presse-papiers")
                Spacer(minLength: 0)
                if let action = model.lastAction {
                    Text(action)
                        .font(NK.ui(9.5, .medium))
                        .foregroundStyle(NK.t4)
                        .lineLimit(1)
                }
                if !model.entries.isEmpty {
                    Button("Vider") { model.clear() }
                        .font(NK.ui(10, .semibold))
                        .foregroundStyle(NK.t3)
                        .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 8)

            if model.entries.isEmpty {
                Text("Copiez quelque chose : l'historique se remplit tout seul.\nRien n'est écrit sur disque, tout part à la fermeture de l'app.")
                    .font(NK.ui(11, .medium))
                    .foregroundStyle(NK.t3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 18)
            } else {
                HStack(alignment: .top, spacing: 22) {
                    column(Array(model.entries.prefix(5)))
                    column(Array(model.entries.dropFirst(5).prefix(5)))
                }
            }

            Text("Les contenus marqués confidentiels par les gestionnaires de mots de passe sont ignorés.")
                .font(NK.ui(9.5, .medium))
                .foregroundStyle(NK.t4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
        .onAppear { model.start() }
    }

    private func column(_ items: [ClipEntry]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { entry in
                row(entry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func row(_ entry: ClipEntry) -> some View {
        let isHovered = hovered == entry.id

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { model.copy(entry) } label: {
                    HStack(spacing: 10) {
                        Text(entry.kind.label)
                            .font(NK.mono(8.5))
                            .foregroundStyle(entry.kind.isCode ? NK.accent : NK.t4)
                            .padding(.horizontal, 6)
                            .frame(height: 17)
                            .background(
                                Capsule().fill((entry.kind.isCode ? NK.accent : Color.white).opacity(0.10))
                            )
                            .frame(width: 58, alignment: .leading)

                        Text(entry.preview)
                            .font(entry.kind.isCode ? NK.mono(10) : NK.ui(11, .medium))
                            .foregroundStyle(NK.t1)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 0)

                        if entry.lineCount > 1 {
                            Text("\(entry.lineCount) l.")
                                .font(NK.mono(9))
                                .foregroundStyle(NK.t4)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Recopier dans le presse-papiers")

                HStack(spacing: 2) {
                    if isHovered {
                        iconButton("xmark", tint: NK.t3) { model.remove(entry) }
                    }
                    iconButton(entry.isPinned ? "pin.fill" : "pin",
                               tint: entry.isPinned ? NK.warn : NK.t4) {
                        model.togglePin(entry)
                    }
                }
            }
            .padding(.vertical, 7)
            .onHover { hovered = $0 ? entry.id : (hovered == entry.id ? nil : hovered) }

            Hairline()
        }
        .animation(.smooth(duration: 0.15), value: isHovered)
    }

    private func iconButton(_ icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
