import SwiftUI

struct StatsPageView: View {
    var model: SystemStatsModel
    var settings: AppSettings

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(spacing: 0) {
                if settings.showCPU {
                    StatRow(name: "Processeur", value: model.cpuUsage,
                            ratio: model.cpuRatio, tint: NK.accent, trail: model.cpuHistory)
                }
                if settings.showRAM {
                    StatRow(name: "Mémoire", value: model.memoryUsage,
                            ratio: model.memoryRatio, tint: NK.accent, trail: model.memoryHistory)
                }
                if settings.showDisk {
                    StatRow(name: "Disque", value: model.diskUsage,
                            ratio: model.diskRatio, tint: NK.t2, trail: [])
                }
                if settings.showBattery {
                    StatRow(name: "Batterie", value: model.battery,
                            ratio: model.batteryRatio, tint: NK.ok, trail: [])
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: NK.sectionGap) {
                if settings.showNetwork {
                    networkSection
                }
                if settings.showClock || settings.showUptime {
                    timeSection
                }
            }
            .frame(width: 244, alignment: .topLeading)
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionLabel("Réseau")

            VStack(spacing: 10) {
                throughput(icon: "arrow.down", value: model.downloadSpeed, label: "Descendant", tint: NK.accent)
                throughput(icon: "arrow.up", value: model.uploadSpeed, label: "Montant", tint: NK.t3)
            }

            Hairline()

            HStack {
                Text("Interface")
                    .font(NK.ui(11, .medium))
                    .foregroundStyle(NK.t3)
                Spacer()
                Text(model.networkName)
                    .font(NK.ui(11, .semibold))
                    .foregroundStyle(NK.t1)
            }
        }
    }

    private func throughput(icon: String, value: String, label: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(NK.mono(14))
                    .foregroundStyle(NK.t1)
                SectionLabel(label)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeSection: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 22) {
                if settings.showClock {
                    labelled("Horloge", model.clock)
                }
                if settings.showUptime {
                    labelled("Démarré depuis", model.uptime)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 11)
        }
    }

    private func labelled(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionLabel(key)
            Text(value)
                .font(NK.mono(13))
                .foregroundStyle(NK.t2)
        }
    }
}

/// Une ligne = un gabarit unique : nom, jauge, courbe, valeur alignée à droite.
struct StatRow: View {
    let name: String
    let value: String
    let ratio: Double
    let tint: Color
    let trail: [Double]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text(name)
                    .font(NK.ui(11, .semibold))
                    .foregroundStyle(NK.t2)
                    .frame(width: 78, alignment: .leading)

                MeterBar(value: ratio, tint: tint)
                    .frame(maxWidth: .infinity)

                Sparkline(values: trail, tint: tint)
                    .frame(width: 84, height: 16)
                    .opacity(trail.count > 1 ? 1 : 0)

                Text(value)
                    .font(NK.mono(13))
                    .foregroundStyle(NK.t1)
                    .frame(width: 62, alignment: .trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, 11)

            Hairline()
        }
    }
}
