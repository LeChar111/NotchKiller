import SwiftUI

struct ProcessesPageView: View {
    var monitor: ProcessMonitor = .shared

    @State private var pendingKill: String?
    @State private var pendingReclaim = false
    @State private var resetTask: Task<Void, Never>?

    private var visible: [ProcessGroup] { Array(monitor.groups.prefix(6)) }

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            processList
                .frame(maxWidth: .infinity, alignment: .topLeading)

            sidebar
                .frame(width: 236, alignment: .topLeading)
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
        .onAppear { monitor.subscribe() }
        .onDisappear {
            monitor.unsubscribe()
            cancelPending()
        }
    }

    // MARK: Liste

    private var processList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                SectionLabel("Applications · hors système")
                Spacer(minLength: 0)
                sortToggle
            }
            .padding(.bottom, 8)

            if visible.isEmpty {
                Text(monitor.isRefreshing ? "Relevé en cours…" : "Rien à signaler")
                    .font(NK.ui(11, .medium))
                    .foregroundStyle(NK.t3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 20)
            } else {
                ForEach(visible) { group in
                    row(group)
                }
            }
        }
    }

    private var sortToggle: some View {
        HStack(spacing: 3) {
            sortButton("Mémoire", active: !monitor.sortByCPU) { monitor.sortByCPU = false }
            sortButton("CPU", active: monitor.sortByCPU) { monitor.sortByCPU = true }
        }
    }

    private func sortButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(NK.ui(10, .semibold))
                .foregroundStyle(active ? NK.t1 : NK.t3)
                .padding(.horizontal, 9)
                .frame(height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? Color.white.opacity(0.09) : .clear)
                )
        }
        .buttonStyle(.plain)
    }

    private func row(_ group: ProcessGroup) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(group.name)
                    .font(NK.ui(11.5, .semibold))
                    .foregroundStyle(NK.t1)
                    .lineLimit(1)
                    .frame(width: 150, alignment: .leading)

                if group.pids.count > 1 {
                    Text("\(group.pids.count)")
                        .font(NK.mono(9))
                        .foregroundStyle(NK.t4)
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                }

                Spacer(minLength: 8)

                MeterBar(value: share(group), tint: monitor.sortByCPU ? NK.hot : NK.accent, height: 3)
                    .frame(width: 84)

                Text(monitor.sortByCPU ? group.cpuLabel : group.memoryLabel)
                    .font(NK.mono(11.5))
                    .foregroundStyle(NK.t1)
                    .frame(width: 62, alignment: .trailing)

                killButton(group)
            }
            .padding(.vertical, 7)

            Hairline()
        }
    }

    /// Part relative au plus gros consommateur : la barre compare, elle ne mesure pas.
    private func share(_ group: ProcessGroup) -> Double {
        let reference = monitor.sortByCPU
            ? (monitor.groups.first?.cpu ?? 1)
            : (monitor.groups.first?.memoryBytes ?? 1)
        guard reference > 0 else { return 0 }
        return (monitor.sortByCPU ? group.cpu : group.memoryBytes) / reference
    }

    private func killButton(_ group: ProcessGroup) -> some View {
        let armed = pendingKill == group.id

        return Button {
            if armed {
                monitor.terminate(group)
                cancelPending()
            } else {
                arm { pendingKill = group.id }
            }
        } label: {
            Text(armed ? "Confirmer" : "Fermer")
                .font(NK.ui(10, .semibold))
                .foregroundStyle(armed ? NK.bad : NK.t3)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(armed ? NK.bad.opacity(0.16) : Color.white.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .frame(width: 74, alignment: .trailing)
    }

    // MARK: Colonne latérale

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: NK.sectionGap) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Mémoire des apps")
                Text(ProcessMonitor.formatBytes(monitor.totalUserMemory))
                    .font(NK.mono(17))
                    .foregroundStyle(NK.t1)
            }

            Hairline()

            reclaimBlock

            if let action = monitor.lastAction {
                HStack(spacing: 7) {
                    Circle().fill(NK.ok).frame(width: 5, height: 5)
                    Text(action)
                        .font(NK.ui(10, .medium))
                        .foregroundStyle(NK.t3)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var reclaimBlock: some View {
        let candidates = monitor.reclaimCandidates
        let freed = monitor.reclaimableBytes

        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Libérer la mémoire")

            Text(candidates.isEmpty
                 ? "Aucune app en arrière-plan sans fenêtre."
                 : "\(candidates.count) app\(candidates.count > 1 ? "s" : "") ouverte\(candidates.count > 1 ? "s" : "") sans fenêtre à l'écran.")
                .font(NK.ui(10.5, .medium))
                .foregroundStyle(NK.t3)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                if pendingReclaim {
                    monitor.reclaim(candidates)
                    cancelPending()
                } else {
                    arm { pendingReclaim = true }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: pendingReclaim ? "exclamationmark.triangle.fill" : "wand.and.sparkles")
                        .font(.system(size: 11, weight: .semibold))
                    Text(pendingReclaim
                         ? "Confirmer · \(ProcessMonitor.formatBytes(freed))"
                         : "Fermer les apps en veille")
                        .font(NK.ui(11, .semibold))
                }
                .foregroundStyle(pendingReclaim ? NK.bad : NK.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill((pendingReclaim ? NK.bad : NK.accent).opacity(0.14))
                )
            }
            .buttonStyle(.plain)
            .disabled(candidates.isEmpty)
            .opacity(candidates.isEmpty ? 0.4 : 1)

            Text("Fermeture douce : une app avec des modifications non enregistrées vous le demandera.")
                .font(NK.ui(9.5, .medium))
                .foregroundStyle(NK.t4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Confirmation en deux temps

    private func arm(_ action: @escaping () -> Void) {
        cancelPending()
        action()
        resetTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            pendingKill = nil
            pendingReclaim = false
        }
    }

    private func cancelPending() {
        resetTask?.cancel()
        resetTask = nil
        pendingKill = nil
        pendingReclaim = false
    }
}
