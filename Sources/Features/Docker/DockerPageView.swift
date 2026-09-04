import SwiftUI

struct DockerPageView: View {
    var model: DockerModel = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SectionLabel("Conteneurs")
                Spacer(minLength: 0)
                if let action = model.lastAction {
                    Text(action)
                        .font(NK.ui(9.5, .medium))
                        .foregroundStyle(NK.t4)
                        .lineLimit(1)
                }
                StatusPill(text: "\(model.containers.filter(\.isRunning).count) actifs",
                           tint: model.containers.contains(where: \.isRunning) ? NK.ok : NK.t3)
            }
            .padding(.bottom, 8)

            if !model.isAvailable {
                unavailable
            } else if model.containers.isEmpty {
                Text(model.isRefreshing ? "Interrogation de Docker…" : "Aucun conteneur.")
                    .font(NK.ui(11, .medium))
                    .foregroundStyle(NK.t3)
                    .padding(.vertical, 20)
            } else {
                HStack(alignment: .top, spacing: 22) {
                    column(Array(model.containers.prefix(5)))
                    column(Array(model.containers.dropFirst(5).prefix(5)))
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
        .onAppear { model.subscribe() }
        .onDisappear { model.unsubscribe() }
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Docker introuvable.")
                .font(NK.ui(11.5, .semibold))
                .foregroundStyle(NK.t2)
            Text("Le binaire est cherché dans /opt/homebrew/bin, /usr/local/bin et Docker.app — lancez Docker Desktop, ou installez la CLI.")
                .font(NK.ui(10.5, .medium))
                .foregroundStyle(NK.t3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
    }

    private func column(_ items: [DockerContainer]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { container in
                row(container)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func row(_ container: DockerContainer) -> some View {
        let busy = model.busyID == container.id

        return VStack(spacing: 0) {
            HStack(spacing: 11) {
                Circle()
                    .fill(container.isRunning ? NK.ok : NK.t4)
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: 3) {
                    Text(container.name)
                        .font(NK.ui(11.5, .semibold))
                        .foregroundStyle(NK.t1)
                        .lineLimit(1)
                    Text(container.status)
                        .font(NK.mono(9))
                        .foregroundStyle(NK.t4)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if busy {
                    Text("…")
                        .font(NK.mono(11))
                        .foregroundStyle(NK.t3)
                        .frame(width: 62, height: 22)
                } else {
                    HStack(spacing: 4) {
                        if container.isRunning {
                            action(icon: "arrow.clockwise", tint: NK.t3) { model.restart(container) }
                        }
                        action(icon: container.isRunning ? "stop.fill" : "play.fill",
                               tint: container.isRunning ? NK.bad : NK.ok) {
                            model.toggle(container)
                        }
                    }
                }
            }
            .padding(.vertical, 7)

            Hairline()
        }
    }

    private func action(icon: String, tint: Color, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
