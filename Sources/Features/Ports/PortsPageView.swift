import SwiftUI

struct PortsPageView: View {
    var model: PortsModel = .shared

    @State private var pending: String?
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SectionLabel("Ports TCP en écoute")
                Spacer(minLength: 0)
                if let action = model.lastAction {
                    Text(action)
                        .font(NK.ui(9.5, .medium))
                        .foregroundStyle(NK.t4)
                        .lineLimit(1)
                }
                Text("\(model.ports.count)")
                    .font(NK.mono(9.5))
                    .foregroundStyle(NK.t4)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
            }
            .padding(.bottom, 8)

            if model.ports.isEmpty {
                Text(model.isRefreshing ? "Relevé en cours…" : "Aucun port en écoute.")
                    .font(NK.ui(11, .medium))
                    .foregroundStyle(NK.t3)
                    .padding(.vertical, 20)
            } else {
                HStack(alignment: .top, spacing: 22) {
                    column(Array(model.ports.prefix(6)))
                    column(Array(model.ports.dropFirst(6).prefix(6)))
                }
            }

            Text("Sans privilèges élevés, lsof ne montre que vos propres processus — c'est aussi le seul périmètre qu'on s'autorise à fermer.")
                .font(NK.ui(9.5, .medium))
                .foregroundStyle(NK.t4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
        .onAppear { model.subscribe() }
        .onDisappear {
            model.unsubscribe()
            cancelPending()
        }
    }

    private func column(_ items: [ListeningPort]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { entry in
                row(entry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func row(_ entry: ListeningPort) -> some View {
        let armed = pending == entry.id

        return VStack(spacing: 0) {
            HStack(spacing: 11) {
                Text("\(entry.port)")
                    .font(NK.mono(13))
                    .foregroundStyle(entry.isCommonDevPort ? NK.accent : NK.t1)
                    .frame(width: 52, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.process)
                        .font(NK.ui(11.5, .semibold))
                        .foregroundStyle(NK.t1)
                        .lineLimit(1)
                    Text("pid \(entry.pid)")
                        .font(NK.mono(9))
                        .foregroundStyle(NK.t4)
                }

                Spacer(minLength: 4)

                if entry.isOwned {
                    Button {
                        if armed {
                            model.release(entry)
                            cancelPending()
                        } else {
                            arm(entry.id)
                        }
                    } label: {
                        Text(armed ? "Confirmer" : "Libérer")
                            .font(NK.ui(10, .semibold))
                            .foregroundStyle(armed ? NK.bad : NK.t3)
                            .padding(.horizontal, 9)
                            .frame(height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(armed ? NK.bad.opacity(0.16) : Color.white.opacity(0.05))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("système")
                        .font(NK.ui(9.5, .medium))
                        .foregroundStyle(NK.t4)
                        .frame(height: 22)
                }
            }
            .padding(.vertical, 7)

            Hairline()
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
}
