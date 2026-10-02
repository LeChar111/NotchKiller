import SwiftUI

/// Système › Ventilation : vitesse et consigne de chaque ventilateur à gauche,
/// sondes de température regroupées par famille à droite.
struct FansPageView: View {
    var model: FanModel = .shared

    @State private var expanded: ThermalGroup?

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            fanColumn
                .frame(maxWidth: .infinity, alignment: .topLeading)

            sensorColumn
                .frame(width: 316, alignment: .topLeading)
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
        .onAppear { model.subscribe() }
        .onDisappear { model.unsubscribe() }
    }

    // MARK: Ventilateurs

    private var fanColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SectionLabel("Ventilateurs")
                Spacer(minLength: 0)
                presetPicker
            }
            .padding(.bottom, 8)

            if let competitor = model.competitor {
                notice(icon: "exclamationmark.triangle.fill", tint: NK.hot,
                       text: "\(competitor.localizedName ?? "Macs Fan Control") pilote aussi les ventilateurs : les deux consignes se contrediraient.",
                       action: "Quitter", perform: model.quitCompetitor)
                    .padding(.bottom, 8)
            }

            helperNotice

            if model.fans.isEmpty {
                Text("Aucun ventilateur détecté sur ce Mac.")
                    .font(NK.ui(11, .medium))
                    .foregroundStyle(NK.t3)
                    .padding(.vertical, 20)
            } else {
                ForEach(model.fans, id: \.index) { fan in
                    FanRow(fan: fan,
                           name: FanReading.name(fan.index, of: model.fans.count),
                           mode: model.mode(of: fan),
                           canControl: model.helper == .ready,
                           groups: model.summaries.map(\.group).filter { $0 != .other },
                           onChange: { model.setMode($0, for: fan) })
                }
            }

            footer
                .padding(.top, 10)
        }
    }

    private var presetPicker: some View {
        HStack(spacing: 3) {
            ForEach([FanPreset.automatic, .full]) { preset in
                Button { model.apply(preset) } label: {
                    Text(preset.title)
                        .font(NK.ui(10, .semibold))
                        .foregroundStyle(model.preset == preset ? NK.t1 : NK.t3)
                        .padding(.horizontal, 9)
                        .frame(height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(model.preset == preset ? Color.white.opacity(0.09) : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
            if model.preset == .custom {
                Text(FanPreset.custom.title)
                    .font(NK.ui(10, .semibold))
                    .foregroundStyle(NK.accent)
                    .padding(.horizontal, 9)
                    .frame(height: 20)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(NK.accent.opacity(0.14)))
            }
        }
        .disabled(model.helper != .ready)
        .opacity(model.helper == .ready ? 1 : 0.4)
    }

    @ViewBuilder
    private var helperNotice: some View {
        switch model.helper {
        case .ready:
            EmptyView()
        case .missing:
            notice(icon: "lock.fill", tint: NK.accent,
                   text: "Lecture seule. Piloter les ventilateurs demande un petit assistant root, installé une fois (mot de passe administrateur).",
                   action: model.isWorking ? "Installation…" : "Installer", perform: model.installHelper)
                .padding(.bottom, 8)
        case .outdated:
            notice(icon: "arrow.triangle.2.circlepath", tint: NK.accent,
                   text: "Une nouvelle version de l'assistant de ventilation est embarquée.",
                   action: model.isWorking ? "Mise à jour…" : "Mettre à jour", perform: model.installHelper)
                .padding(.bottom, 8)
        case .unreachable:
            notice(icon: "bolt.horizontal.circle", tint: NK.hot,
                   text: "L'assistant est installé mais ne répond pas — launchd le relance d'ordinaire en quelques secondes.",
                   action: model.isWorking ? "Réinstallation…" : "Réinstaller", perform: model.installHelper)
                .padding(.bottom, 8)
        }
    }

    private func notice(icon: String, tint: Color, text: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(NK.ui(10.5, .medium))
                .foregroundStyle(NK.t2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(action: perform) {
                Text(action)
                    .font(NK.ui(10.5, .semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 11)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .disabled(model.isWorking)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: NK.radiusControl, style: .continuous).fill(NK.surface))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let action = model.lastAction {
                Circle().fill(NK.ok).frame(width: 5, height: 5)
                Text(action)
                    .font(NK.ui(10, .medium))
                    .foregroundStyle(NK.t3)
                    .lineLimit(1)
            } else {
                Text(model.helper == .ready
                     ? "Consignes gardées par l'assistant, même NotchKiller fermé."
                     : "Vitesses relues toutes les 2 s.")
                    .font(NK.ui(10, .medium))
                    .foregroundStyle(NK.t4)
            }
            Spacer(minLength: 0)
            if model.helper != .missing {
                Menu {
                    Button("Réinstaller l'assistant") { model.installHelper() }
                    Button("Désinstaller l'assistant") { model.uninstallHelper() }
                    Divider()
                    Button("Ouvrir le journal") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: FanHelper.logPath))
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(NK.t2)
                        .frame(width: 26, height: 22)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .contentShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(model.isWorking)
            }
        }
    }

    // MARK: Sondes

    private var sensorColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Sondes de température")
                Spacer(minLength: 0)
                Text("\(model.sensors.count)")
                    .font(NK.mono(9.5))
                    .foregroundStyle(NK.t4)
            }

            if let cpu = model.summaries.first(where: { $0.group == .cpuPerformance }) {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CPU · plus chaud")
                            .font(NK.ui(9.5, .semibold))
                            .foregroundStyle(NK.t3)
                        TemperatureText(celsius: cpu.hottest, font: NK.mono(17))
                    }
                    .fixedSize()
                    TemperatureTrend(history: model.cpuHistory, tint: Self.tint(cpu.hottest))
                        .frame(height: 34)
                }
            }

            Hairline()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(model.summaries) { summary in
                        summaryRow(summary)
                    }
                }
            }
            .frame(height: 250)
        }
    }

    private func summaryRow(_ summary: ThermalSummary) -> some View {
        let isOpen = expanded == summary.group

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                expanded = isOpen ? nil : summary.group
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: summary.group.symbol)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(NK.t3)
                        .frame(width: 16)
                    Text(summary.group.title)
                        .font(NK.ui(11, .semibold))
                        .foregroundStyle(NK.t1)
                        .lineLimit(1)
                        .fixedSize()
                    Text("\(summary.sensors.count)")
                        .font(NK.mono(8.5))
                        .foregroundStyle(NK.t4)
                    Spacer(minLength: 4)
                    HStack(spacing: 3) {
                        Text("moy.")
                        TemperatureText(celsius: summary.average, font: NK.mono(9.5, .medium), tint: NK.t3, unit: false)
                    }
                    .font(NK.mono(9.5, .medium))
                    .foregroundStyle(NK.t3)
                    .fixedSize()
                    TemperatureText(celsius: summary.hottest, font: NK.mono(11))
                        .frame(width: 66, alignment: .trailing)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(NK.t4)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), alignment: .leading, spacing: 4) {
                    ForEach(summary.sensors) { sensor in
                        HStack(spacing: 4) {
                            Text(sensor.key)
                                .font(NK.mono(9, .medium))
                                .foregroundStyle(NK.t4)
                            Spacer(minLength: 2)
                            TemperatureText(celsius: sensor.celsius, font: NK.mono(9.5), unit: false)
                        }
                    }
                }
                .padding(.leading, 24)
                .padding(.bottom, 8)
            }

            Hairline()
        }
    }

    static func format(_ celsius: Double) -> String {
        String(format: "%.1f °C", celsius)
    }

    static func tint(_ celsius: Double) -> Color {
        if celsius >= 95 { return NK.bad }
        if celsius >= 80 { return NK.hot }
        return NK.t1
    }
}

// MARK: - Ventilateur

private struct FanRow: View {
    let fan: FanReading
    let name: String
    let mode: FanMode
    let canControl: Bool
    let groups: [ThermalGroup]
    let onChange: (FanMode) -> Void

    /// Valeur suivie pendant le glissé : la consigne n'est envoyée qu'au relâché.
    @State private var draft: Double?

    private enum Kind { case auto, constant, sensor }

    private var kind: Kind {
        switch mode {
        case .auto:     .auto
        case .constant: .constant
        case .sensor:   .sensor
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 11) {
                Image(systemName: "fan.fill")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(fan.forced ? NK.accent : NK.t2)
                    .symbolEffect(.rotate, options: .repeat(.continuous).speed(0.4 + fan.ratio * 2.4),
                                  isActive: fan.actual > 0)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(NK.ui(12.5, .semibold))
                        .foregroundStyle(NK.t1)
                    Text(subtitle)
                        .font(NK.ui(9.5, .medium))
                        .foregroundStyle(NK.t3)
                }

                Spacer(minLength: 8)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Self.rpm(fan.minimum))
                        .font(NK.mono(9.5, .medium))
                        .foregroundStyle(NK.t4)
                    Text("—").font(NK.mono(9.5)).foregroundStyle(NK.t4)
                    Text(Self.rpm(fan.actual))
                        .font(NK.mono(15))
                        .foregroundStyle(NK.t1)
                        .contentTransition(.numericText())
                    Text("—").font(NK.mono(9.5)).foregroundStyle(NK.t4)
                    Text(Self.rpm(fan.maximum))
                        .font(NK.mono(9.5, .medium))
                        .foregroundStyle(NK.t4)
                    Text("tr/min")
                        .font(NK.ui(9, .medium))
                        .foregroundStyle(NK.t4)
                }
            }

            MeterBar(value: fan.ratio, tint: fan.forced ? NK.accent : NK.t2, height: 3)

            HStack(spacing: 10) {
                segmented
                    .disabled(!canControl)
                    .opacity(canControl ? 1 : 0.4)

                switch mode {
                case .auto:
                    Text("Consigne du système")
                        .font(NK.ui(10, .medium))
                        .foregroundStyle(NK.t4)
                    Spacer(minLength: 0)
                case .constant(let rpm):
                    constantControl(rpm)
                case .sensor(let group, let low, let high):
                    sensorControl(group: group, low: low, high: high)
                }
            }
            .frame(height: 24)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Hairline() }
        .animation(.easeOut(duration: 0.25), value: fan.actual)
    }

    private var subtitle: String {
        switch mode {
        case .auto:
            return fan.forced ? "Automatique · consigne imposée ailleurs" : "Automatique"
        case .constant(let rpm):
            return "Constante · \(Self.rpm(rpm)) tr/min"
        case .sensor(let group, let low, let high):
            return "Selon \(group.title) · \(Int(low)) → \(Int(high)) °C"
        }
    }

    private var segmented: some View {
        HStack(spacing: 2) {
            segment("Auto", active: kind == .auto) { onChange(.auto) }
            segment("Constante", active: kind == .constant) {
                let start = (fan.actual / 100).rounded() * 100
                onChange(.constant(rpm: max(fan.minimum, min(fan.maximum, start))))
            }
            segment("Capteur", active: kind == .sensor) {
                onChange(.sensor(group: groups.first ?? .cpuPerformance, low: 55, high: 90))
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func segment(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            if !active { action() }
        } label: {
            Text(title)
                .font(NK.ui(10, .semibold))
                .foregroundStyle(active ? NK.t1 : NK.t3)
                .padding(.horizontal, 9)
                .frame(height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? Color.white.opacity(0.11) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func constantControl(_ rpm: Double) -> some View {
        let shown = draft ?? rpm
        return HStack(spacing: 10) {
            NKSlider(value: shown, range: fan.minimum...fan.maximum, step: 50,
                     onDrag: { draft = $0 },
                     onCommit: { value in
                         draft = nil
                         onChange(.constant(rpm: value))
                     })
                .disabled(!canControl)
            Text("\(Self.rpm(shown))")
                .font(NK.mono(10.5))
                .foregroundStyle(NK.accent)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func sensorControl(group: ThermalGroup, low: Double, high: Double) -> some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(groups) { option in
                    Button(option.title) { onChange(.sensor(group: option, low: low, high: high)) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(group.title)
                        .font(NK.ui(10, .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(NK.t1)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.08)))
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer(minLength: 0)

            Text("min. à")
                .font(NK.ui(9.5, .medium))
                .foregroundStyle(NK.t4)
            stepper(low, range: 30...(high - 5)) { onChange(.sensor(group: group, low: $0, high: high)) }
            Text("max. à")
                .font(NK.ui(9.5, .medium))
                .foregroundStyle(NK.t4)
            stepper(high, range: (low + 5)...105) { onChange(.sensor(group: group, low: low, high: $0)) }
        }
        .disabled(!canControl)
    }

    private func stepper(_ value: Double, range: ClosedRange<Double>, set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 0) {
            stepButton("minus", enabled: value - 5 >= range.lowerBound) { set(value - 5) }
            Text("\(Int(value)) °C")
                .font(NK.mono(10))
                .foregroundStyle(NK.t1)
                .frame(width: 40)
            stepButton("plus", enabled: value + 5 <= range.upperBound) { set(value + 5) }
        }
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(enabled ? NK.t2 : NK.t4)
                .frame(width: 20, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    static func rpm(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}

/// Curseur dessiné : rail de 4 pt façon `MeterBar`, pastille blanche. Le système
/// n'offre pas de rail lisible sur du noir pur à cette taille.
private struct NKSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let onDrag: (Double) -> Void
    let onCommit: (Double) -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let span = max(range.upperBound - range.lowerBound, 1)
            let fraction = (value - range.lowerBound) / span

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 4)
                Capsule()
                    .fill(NK.accent)
                    .frame(width: max(4, width * fraction), height: 4)
                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.45), radius: 1.5, y: 0.5)
                    .offset(x: (width - 14) * fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in onDrag(snap(gesture.location.x, width: width)) }
                    .onEnded { gesture in onCommit(snap(gesture.location.x, width: width)) }
            )
        }
        .frame(height: 22)
        .opacity(isEnabled ? 1 : 0.4)
    }

    private func snap(_ x: CGFloat, width: CGFloat) -> Double {
        let fraction = max(0, min(1, Double(x / max(width, 1))))
        let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
        let stepped = (raw / step).rounded() * step
        return max(range.lowerBound, min(range.upperBound, stepped))
    }
}

// MARK: - Température animée

/// Les chiffres roulent d'une valeur à l'autre plutôt que de sauter ; la couleur
/// glisse avec eux quand on franchit un seuil.
private struct TemperatureText: View {
    let celsius: Double
    let font: Font
    var tint: Color?
    var unit = true

    var body: some View {
        Text(unit ? FansPageView.format(celsius) : String(format: "%.1f", celsius))
            .font(font)
            .monospacedDigit()
            .foregroundStyle(tint ?? FansPageView.tint(celsius))
            .lineLimit(1)
            .contentTransition(.numericText(value: celsius))
            .animation(.smooth(duration: 0.7), value: celsius)
    }
}

/// Courbe des derniers relevés : lissée, à échelle adaptée à leur amplitude (au
/// moins 8 °C, pour qu'un dixième de degré ne passe pas pour un pic), et qui glisse
/// d'un relevé à l'autre au lieu de se redessiner d'un coup.
private struct TemperatureTrend: View {
    let history: [Double]
    let tint: Color

    private static let length = 30

    private var normalized: [Double] {
        guard let first = history.first else { return Array(repeating: 0.5, count: Self.length) }
        // Toujours 30 points : l'interpolation se fait point à point.
        let padded = Array(repeating: first, count: max(0, Self.length - history.count)) + history.suffix(Self.length)
        let low = padded.min() ?? 0, high = padded.max() ?? 1
        let middle = (low + high) / 2
        let span = max(high - low + 2, 8)
        return padded.map { 0.5 + ($0 - middle) / span }
    }

    var body: some View {
        let values = AnimatableVector(normalized)
        ZStack {
            TrendShape(values: values, closed: true)
                .fill(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
            TrendShape(values: values, closed: false)
                .stroke(tint.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .animation(.smooth(duration: 1.4), value: values)
    }
}

private struct TrendShape: Shape {
    var values: AnimatableVector
    let closed: Bool

    var animatableData: AnimatableVector {
        get { values }
        set { values = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let items = values.values
        guard items.count > 1 else { return Path() }
        let step = rect.width / CGFloat(items.count - 1)
        let points = items.enumerated().map { index, value in
            CGPoint(x: rect.minX + CGFloat(index) * step,
                    y: rect.maxY - CGFloat(max(0, min(1, value))) * (rect.height - 3) - 1.5)
        }

        var path = Path()
        path.move(to: points[0])
        // Catmull-Rom converti en Bézier : la courbe passe par chaque relevé, sans angle.
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)], p1 = points[index]
            let p2 = points[index + 1], p3 = points[min(index + 2, points.count - 1)]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        if closed {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

/// Tableau de valeurs interpolable par SwiftUI, élément par élément.
private struct AnimatableVector: VectorArithmetic {
    var values: [Double]

    init(_ values: [Double]) { self.values = values }

    static var zero: AnimatableVector { AnimatableVector([]) }

    private static func combine(_ a: AnimatableVector, _ b: AnimatableVector, _ op: (Double, Double) -> Double) -> AnimatableVector {
        let count = max(a.values.count, b.values.count)
        return AnimatableVector((0..<count).map { index in
            op(index < a.values.count ? a.values[index] : 0, index < b.values.count ? b.values[index] : 0)
        })
    }

    static func + (a: AnimatableVector, b: AnimatableVector) -> AnimatableVector { combine(a, b, +) }
    static func - (a: AnimatableVector, b: AnimatableVector) -> AnimatableVector { combine(a, b, -) }

    mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
}
