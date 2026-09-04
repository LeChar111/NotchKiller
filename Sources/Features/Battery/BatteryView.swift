import SwiftUI

struct BatteryView: View {
    var battery: BatteryModel
    var bluetooth: BluetoothModel = .shared

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            ring
                .frame(width: 112, height: 112)

            facts
                .frame(maxWidth: .infinity, alignment: .leading)

            devices
                .frame(width: 268, alignment: .topLeading)
        }
        .padding(.top, 14)
        .padding(.bottom, 14)
        .onAppear { bluetooth.refresh() }
    }

    /// Les appareils Bluetooth appartiennent à la même question que la
    /// batterie : ce qui consomme, et ce qu'il reste.
    private var devices: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("Bluetooth")

            if bluetooth.devices.isEmpty {
                Text("Aucun appareil appairé.")
                    .font(NK.ui(10.5, .medium))
                    .foregroundStyle(NK.t3)
            } else {
                ForEach(bluetooth.devices.prefix(6)) { device in
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            Image(systemName: device.symbol)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(device.isConnected ? NK.accent : NK.t4)
                                .frame(width: 16)

                            Text(device.name)
                                .font(NK.ui(11, .medium))
                                .foregroundStyle(device.isConnected ? NK.t1 : NK.t3)
                                .lineLimit(1)

                            Spacer(minLength: 4)

                            if let level = device.battery {
                                Text("\(level) %")
                                    .font(NK.mono(10))
                                    .foregroundStyle(level < 20 ? NK.bad : NK.t2)
                            } else if device.isConnected {
                                Circle().fill(NK.ok).frame(width: 5, height: 5)
                            }
                        }
                        .padding(.vertical, 7)
                        Hairline()
                    }
                }
            }

            Text("Le niveau n'apparaît que pour les appareils qui le publient.")
                .font(NK.ui(9.5, .medium))
                .foregroundStyle(NK.t4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 7)

            Circle()
                .trim(from: 0, to: battery.normalizedLevel)
                .stroke(batteryColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.4), value: battery.normalizedLevel)

            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    Text("\(Int(battery.level))")
                        .font(.system(size: 26, weight: .semibold, design: .monospaced))
                        .kerning(-1)
                        .foregroundStyle(NK.t1)
                    if battery.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(NK.ok)
                    }
                }
                SectionLabel("pour cent")
            }
        }
    }

    private var facts: some View {
        VStack(spacing: 0) {
            fact("État", stateLabel, tint: NK.t1)
            fact(battery.isCharging ? "Charge complète dans" : "Autonomie",
                 battery.remainingLabel, tint: NK.t1)
            fact("Économie d'énergie", battery.isLowPowerMode ? "Activée" : "Désactivée",
                 tint: battery.isLowPowerMode ? NK.hot : NK.t2)
            if battery.cycleCount > 0 {
                fact("Cycles", "\(battery.cycleCount)", tint: NK.t2)
            }
            if battery.healthRatio > 0 {
                fact("Santé", battery.healthLabel, tint: healthColor, last: true)
            }
        }
    }

    private var stateLabel: String {
        if battery.isCharging { return "En charge" }
        if battery.isPluggedIn { return battery.level >= battery.maxCapacity ? "Chargée" : "Sur secteur" }
        return "Sur batterie"
    }

    private func fact(_ key: String, _ value: String, tint: Color, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(key)
                    .font(NK.ui(11, .medium))
                    .foregroundStyle(NK.t3)
                Spacer()
                Text(value)
                    .font(NK.ui(11.5, .semibold))
                    .foregroundStyle(tint)
            }
            .padding(.vertical, 9)

            if !last { Hairline() }
        }
    }

    private var healthColor: Color {
        if battery.healthRatio >= 0.80 { return NK.ok }
        if battery.healthRatio >= 0.65 { return NK.warn }
        return NK.bad
    }

    private var batteryColor: Color {
        if battery.isCharging { return NK.ok }
        if battery.level < 20 { return NK.bad }
        if battery.level < 40 { return NK.hot }
        return NK.accent
    }
}
