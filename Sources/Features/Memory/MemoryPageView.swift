import SwiftUI

struct MemoryPageView: View {
    var model: MemoryModel = .shared

    @State private var pendingKill: Int32?
    @State private var pendingFree = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            hogList
                .frame(maxWidth: .infinity, alignment: .topLeading)

            sidebar
                .frame(width: 250, alignment: .topLeading)
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
        .onAppear { model.subscribe() }
        .onDisappear {
            model.unsubscribe()
            cancelPending()
        }
    }

    // MARK: Liste

    private var hogList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                SectionLabel("Empreinte mémoire · swap compris")
                Spacer(minLength: 0)
                Text("hors RAM")
                    .font(NK.ui(9.5, .semibold))
                    .foregroundStyle(NK.t4)
                    .frame(width: 70, alignment: .trailing)
                Text("total")
                    .font(NK.ui(9.5, .semibold))
                    .foregroundStyle(NK.t4)
                    .frame(width: 58, alignment: .trailing)
                Color.clear.frame(width: 74, height: 1)
            }
            .padding(.bottom, 8)

            if model.hogs.isEmpty {
                Text(model.isRefreshing ? "Relevé en cours…" : "Rien à signaler")
                    .font(NK.ui(11, .medium))
                    .foregroundStyle(NK.t3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 20)
            } else {
                ForEach(model.hogs.prefix(7)) { hog in
                    row(hog)
                }
            }
        }
    }

    private func row(_ hog: MemoryHog) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(hog.name)
                            .font(NK.ui(11.5, .semibold))
                            .foregroundStyle(NK.t1)
                            .lineLimit(1)
                        Text("\(hog.pid)")
                            .font(NK.mono(8.5))
                            .foregroundStyle(NK.t4)
                        if hog.isStale {
                            Text("depuis \(hog.elapsed.replacingOccurrences(of: "-", with: " j "))")
                                .font(NK.ui(9, .semibold))
                                .foregroundStyle(NK.hot)
                                .padding(.horizontal, 6)
                                .frame(height: 15)
                                .background(Capsule().fill(NK.hot.opacity(0.14)))
                        }
                    }
                    Text(hog.command)
                        .font(NK.mono(8.5))
                        .foregroundStyle(NK.t4)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Text(hog.outOfRAM >= 64 * 1_048_576 ? Shell.formatBytes(hog.outOfRAM) : "—")
                    .font(NK.mono(11))
                    .foregroundStyle(hog.outOfRAM >= 1_073_741_824 ? NK.hot : NK.t3)
                    .frame(width: 70, alignment: .trailing)

                Text(Shell.formatBytes(hog.footprint))
                    .font(NK.mono(11.5))
                    .foregroundStyle(NK.t1)
                    .frame(width: 58, alignment: .trailing)

                killButton(hog)
            }
            .padding(.vertical, 6)

            Hairline()
        }
    }

    private func killButton(_ hog: MemoryHog) -> some View {
        let armed = pendingKill == hog.pid

        return Button {
            if armed {
                model.terminate(hog)
                cancelPending()
            } else {
                arm { pendingKill = hog.pid }
            }
        } label: {
            Text(armed ? "Confirmer" : (hog.isApp ? "Fermer" : "Arrêter"))
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
                HStack {
                    SectionLabel("Swap")
                    Spacer(minLength: 0)
                    Text("pression \(model.pressure.label)")
                        .font(NK.ui(9.5, .semibold))
                        .foregroundStyle(pressureTint)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Shell.formatBytes(model.swapUsed))
                        .font(NK.mono(17))
                        .foregroundStyle(NK.t1)
                    Text("/ \(Shell.formatBytes(model.swapTotal))")
                        .font(NK.mono(11))
                        .foregroundStyle(NK.t3)
                }
                MeterBar(value: model.swapTotal > 0 ? model.swapUsed / model.swapTotal : 0, tint: pressureTint, height: 3)
            }

            Hairline()

            freeBlock

            Button { model.purge() } label: {
                HStack(spacing: 7) {
                    Image(systemName: model.isPurging ? "hourglass" : "arrow.3.trianglepath")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text(model.isPurging ? "Purge…" : "Purger les caches (admin)")
                        .font(NK.ui(10.5, .semibold))
                }
                .foregroundStyle(NK.t2)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.05)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isPurging)

            if let action = model.lastAction {
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

    private var pressureTint: Color {
        switch model.pressure {
        case .normal:   NK.ok
        case .warning:  NK.hot
        case .critical: NK.bad
        }
    }

    private var freeBlock: some View {
        let holders = model.swapHolders
        let bytes = model.swapHoldersBytes

        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Libérer le swap")

            Text(holders.isEmpty
                 ? "Aucun processus hors app ne retient plus de 512 Mo hors RAM."
                 : "\(holders.count) processus hors app retien\(holders.count > 1 ? "nent" : "t") \(Shell.formatBytes(bytes)) hors RAM : \(holders.prefix(3).map(\.name).joined(separator: ", ")).")
                .font(NK.ui(10.5, .medium))
                .foregroundStyle(NK.t3)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                if pendingFree {
                    model.freeSwap()
                    cancelPending()
                } else {
                    arm { pendingFree = true }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: pendingFree ? "exclamationmark.triangle.fill" : "memorychip")
                        .font(.system(size: 11, weight: .semibold))
                    Text(pendingFree ? "Confirmer · \(Shell.formatBytes(bytes))" : "Tout libérer")
                        .font(NK.ui(11, .semibold))
                }
                .foregroundStyle(pendingFree ? NK.bad : NK.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill((pendingFree ? NK.bad : NK.accent).opacity(0.14))
                )
            }
            .buttonStyle(.plain)
            .disabled(holders.isEmpty)
            .opacity(holders.isEmpty ? 0.4 : 1)

            Text("macOS ne vide le swap qu'en libérant la mémoire qui l'occupe : on arrête ces processus (SIGTERM, puis SIGKILL après 5 s), les fichiers de swap se réduisent ensuite d'eux-mêmes. Les apps se ferment ligne par ligne.")
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
            pendingFree = false
        }
    }

    private func cancelPending() {
        resetTask?.cancel()
        resetTask = nil
        pendingKill = nil
        pendingFree = false
    }
}
