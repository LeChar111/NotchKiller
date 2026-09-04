import SwiftUI

struct CleanupPageView: View {
    var model: CleanupModel = .shared

    @State private var pending: String?
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 10)

            if !model.hasScanned {
                intro
            } else if model.targets.isEmpty {
                Text("Rien de significatif à récupérer — seuls les dossiers de plus de 16 Mo sont listés.")
                    .font(NK.ui(11, .medium))
                    .foregroundStyle(NK.t3)
                    .padding(.vertical, 18)
            } else {
                HStack(alignment: .top, spacing: 22) {
                    ForEach(CleanupGroup.allCases) { group in
                        groupColumn(group)
                    }
                }
            }

            Text("Tout part à la corbeille, jamais en suppression directe : un node_modules se réinstalle, un chemin mal filtré ne se récupère pas.")
                .font(NK.ui(9.5, .medium))
                .foregroundStyle(NK.t4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
        .onDisappear { cancelPending() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            SectionLabel("Espace récupérable")

            if model.hasScanned {
                Text(Shell.formatBytes(model.totalBytes))
                    .font(NK.mono(15))
                    .foregroundStyle(NK.t1)
            }

            Spacer(minLength: 0)

            if let action = model.lastAction {
                Text(action)
                    .font(NK.ui(9.5, .medium))
                    .foregroundStyle(NK.t4)
                    .lineLimit(1)
            }

            Button { model.scan() } label: {
                HStack(spacing: 6) {
                    Image(systemName: model.isScanning ? "hourglass" : "magnifyingglass")
                        .font(.system(size: 10, weight: .semibold))
                    Text(model.isScanning ? "Analyse…" : (model.hasScanned ? "Réanalyser" : "Analyser"))
                        .font(NK.ui(10.5, .semibold))
                }
                .foregroundStyle(NK.accent)
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(NK.accent.opacity(0.14)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isScanning)
        }
    }

    private var intro: some View {
        Text("L'analyse mesure les node_modules et dossiers de build de vos projets, ainsi que les caches npm, pnpm, pip, Homebrew, Go, Cargo et DerivedData.\nElle prend quelques secondes et n'est pas lancée toute seule.")
            .font(NK.ui(11, .medium))
            .foregroundStyle(NK.t3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 16)
    }

    private func groupColumn(_ group: CleanupGroup) -> some View {
        let items = Array(model.targets(in: group).prefix(4))
        let total = model.targets(in: group).reduce(0) { $0 + $1.bytes }
        let armed = pending == group.rawValue

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SectionLabel(group.title)
                Spacer(minLength: 0)
                if !items.isEmpty {
                    Button {
                        if armed {
                            model.trashAll(in: group)
                            cancelPending()
                        } else {
                            arm(group.rawValue)
                        }
                    } label: {
                        Text(armed ? "Confirmer · \(Shell.formatBytes(total))" : "Tout")
                            .font(NK.ui(9.5, .semibold))
                            .foregroundStyle(armed ? NK.bad : NK.t3)
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(
                                Capsule().fill(armed ? NK.bad.opacity(0.16) : Color.white.opacity(0.05))
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if items.isEmpty {
                Text("—")
                    .font(NK.ui(11, .medium))
                    .foregroundStyle(NK.t4)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { target in
                        row(target)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func row(_ target: CleanupTarget) -> some View {
        let armed = pending == target.id

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(target.name)
                        .font(NK.ui(11, .semibold))
                        .foregroundStyle(NK.t1)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Text(target.displayPath)
                        .font(NK.mono(8.5))
                        .foregroundStyle(NK.t4)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Spacer(minLength: 4)

                Text(target.detail)
                    .font(NK.mono(11))
                    .foregroundStyle(NK.t2)

                Button {
                    if armed {
                        model.trash(target)
                        cancelPending()
                    } else {
                        arm(target.id)
                    }
                } label: {
                    Image(systemName: armed ? "exclamationmark.triangle.fill" : "trash")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(armed ? NK.bad : NK.t3)
                        .frame(width: 24, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(armed ? NK.bad.opacity(0.16) : Color.white.opacity(0.05))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
