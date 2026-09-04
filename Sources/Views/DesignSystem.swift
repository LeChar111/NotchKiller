import SwiftUI

/// Jetons visuels de NotchKiller. Une seule source pour les couleurs, la typo
/// et les rythmes verticaux : les pages ne réinventent plus leur propre padding.
enum NK {
    // MARK: Couleurs
    /// Accent réglable. Stocké à plat plutôt que calculé depuis AppSettings :
    /// il est lu à chaque rendu, dans des vues qui n'ont pas à connaître les
    /// réglages.
    nonisolated(unsafe) private static var accentStorage = NKAccent.bleu.color
    static var accent: Color { accentStorage }
    static func setAccent(_ theme: NKAccent) { accentStorage = theme.color }
    static let ok      = Color(red: 0.196, green: 0.843, blue: 0.294) // #32D74B
    static let warn    = Color(red: 1.00, green: 0.839, blue: 0.039)  // #FFD60A
    static let hot     = Color(red: 1.00, green: 0.624, blue: 0.039)  // #FF9F0A
    static let bad     = Color(red: 1.00, green: 0.271, blue: 0.227)  // #FF453A
    static let violet  = Color(red: 0.749, green: 0.353, blue: 0.949) // #BF5AF2

    static let t1 = Color.white
    static let t2 = Color.white.opacity(0.62)
    static let t3 = Color.white.opacity(0.34)
    static let t4 = Color.white.opacity(0.20)

    static let surface        = Color.white.opacity(0.045)
    static let surfaceRaised  = Color.white.opacity(0.08)
    static let line           = Color.white.opacity(0.09)
    static let line2          = Color.white.opacity(0.16)

    // MARK: Typographie
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: Rythme
    static let gutter: CGFloat = 12
    static let sectionGap: CGFloat = 14
    static let radiusCard: CGFloat = 12
    static let radiusControl: CGFloat = 9
}

enum NKAccent: String, CaseIterable, Identifiable {
    case bleu, violet, vert, orange, rose

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .bleu:   Color(red: 0.16, green: 0.62, blue: 1.00)
        case .violet: Color(red: 0.749, green: 0.353, blue: 0.949)
        case .vert:   Color(red: 0.196, green: 0.843, blue: 0.294)
        case .orange: Color(red: 1.00, green: 0.624, blue: 0.039)
        case .rose:   Color(red: 0.98, green: 0.16, blue: 0.42)
        }
    }
}

/// Libellé de section : petites capitales, interlettrage ouvert, 34 % d'opacité.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(NK.ui(9, .semibold))
            .tracking(1.3)
            .textCase(.uppercase)
            .foregroundStyle(NK.t3)
    }
}

/// Filet de 1 px — remplace les fonds de carte pour séparer les données.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(NK.line)
            .frame(height: 1)
    }
}

/// Jauge fine de 4 pt, la seule forme de barre de progression de l'app.
struct MeterBar: View {
    var value: Double
    var tint: Color = NK.accent
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.white.opacity(0.10))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * max(0, min(1, value)))
                }
        }
        .frame(height: height)
    }
}

/// Courbe de tendance : 9 relevés suffisent à distinguer un pic d'un plateau.
struct Sparkline: View {
    var values: [Double]
    var tint: Color = NK.accent

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            Path { path in
                guard values.count > 1 else { return }
                let step = w / CGFloat(values.count - 1)
                for (index, value) in values.enumerated() {
                    let point = CGPoint(
                        x: CGFloat(index) * step,
                        y: h - CGFloat(max(0, min(1, value))) * (h - 2) - 1
                    )
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(tint.opacity(0.85), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
    }
}

/// Interrupteur dessiné plutôt que celui du système : à taille `mini` sur du
/// noir pur, le rail éteint de macOS est presque invisible et l'allumé perd sa
/// teinte. Ici l'éteint garde un contour, l'allumé prend l'accent.
struct NKToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? NK.accent : Color.white.opacity(0.09))
                    .overlay(
                        Capsule()
                            .stroke(isOn ? Color.clear : Color.white.opacity(0.22), lineWidth: 1)
                    )

                Circle()
                    .fill(.white)
                    .frame(width: 17, height: 17)
                    .shadow(color: .black.opacity(0.45), radius: 1.5, y: 0.5)
                    .padding(2)
            }
            .frame(width: 36, height: 21)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isOn)
    }
}

/// Pastille d'état — fond teinté à 15 %, texte à la couleur pleine.
struct StatusPill: View {
    let text: String
    var tint: Color = NK.accent

    var body: some View {
        Text(text)
            .font(NK.ui(9.5, .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(tint.opacity(0.15)))
    }
}
