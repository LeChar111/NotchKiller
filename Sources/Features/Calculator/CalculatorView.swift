import SwiftUI

/// Calculatrice de coin de table : une bande de saisie et un pavé.
/// Elle évalue l'expression complète, pas touche à touche — c'est ce qu'on
/// attend quand on tape « 1920/3 » en passant.
@MainActor
@Observable
final class CalculatorModel {
    static let shared = CalculatorModel()

    var expression = ""
    private(set) var result = ""
    private(set) var history: [(expression: String, result: String)] = []

    private init() {}

    func input(_ token: String) {
        expression += token
        evaluate()
    }

    func clear() {
        expression = ""
        result = ""
    }

    func backspace() {
        guard !expression.isEmpty else { return }
        expression.removeLast()
        evaluate()
    }

    func commit() {
        guard !result.isEmpty, result != "—" else { return }
        history.insert((expression, result), at: 0)
        while history.count > 4 { history.removeLast() }
        expression = result
        evaluate()
    }

    func copyResult() {
        guard !result.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
    }

    /// Analyseur maison plutôt que NSExpression : celui-ci lève une exception
    /// Objective-C sur une expression incomplète (« 12+ »), que Swift ne peut
    /// pas rattraper — une frappe en cours ferait tomber tout le widget.
    private func evaluate() {
        let cleaned = expression
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: ",", with: ".")

        guard let value = Self.compute(cleaned), value.isFinite else {
            result = ""
            return
        }
        result = value == value.rounded()
            ? String(format: "%.0f", value)
            : String(format: "%g", value)
    }

    /// Descente récursive : expression → terme → facteur.
    /// Retourne nil sur toute entrée incomplète ou invalide.
    nonisolated static func compute(_ text: String) -> Double? {
        let chars = Array(text.filter { !$0.isWhitespace })
        var index = 0

        func peek() -> Character? { index < chars.count ? chars[index] : nil }

        func factor() -> Double? {
            guard let c = peek() else { return nil }
            if c == "-" { index += 1; return factor().map { -$0 } }
            if c == "+" { index += 1; return factor() }
            if c == "(" {
                index += 1
                guard let inner = expressionValue() else { return nil }
                guard peek() == ")" else { return nil }
                index += 1
                return applyPercent(inner)
            }
            var digits = ""
            while let d = peek(), d.isNumber || d == "." {
                digits.append(d)
                index += 1
            }
            guard let number = Double(digits) else { return nil }
            return applyPercent(number)
        }

        func applyPercent(_ value: Double) -> Double {
            guard peek() == "%" else { return value }
            index += 1
            return value / 100
        }

        func term() -> Double? {
            guard var left = factor() else { return nil }
            while let op = peek(), op == "*" || op == "/" {
                index += 1
                guard let right = factor() else { return nil }
                if op == "/" {
                    guard right != 0 else { return nil }
                    left /= right
                } else {
                    left *= right
                }
            }
            return left
        }

        func expressionValue() -> Double? {
            guard var left = term() else { return nil }
            while let op = peek(), op == "+" || op == "-" {
                index += 1
                guard let right = term() else { return nil }
                left = op == "+" ? left + right : left - right
            }
            return left
        }

        guard let value = expressionValue(), index == chars.count else { return nil }
        return value
    }
}

struct CalculatorView: View {
    var model: CalculatorModel = .shared

    private let rows: [[String]] = [
        ["7", "8", "9", "÷"],
        ["4", "5", "6", "×"],
        ["1", "2", "3", "-"],
        ["0", ".", "%", "+"],
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                display
                keypad
            }
            .frame(width: 300)

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Précédents")
                if model.history.isEmpty {
                    Text("Entrée valide l'opération et l'empile ici.")
                        .font(NK.ui(10.5, .medium))
                        .foregroundStyle(NK.t3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(model.history.enumerated()), id: \.offset) { _, entry in
                        VStack(spacing: 0) {
                            HStack {
                                Text(entry.expression)
                                    .font(NK.mono(10))
                                    .foregroundStyle(NK.t3)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(entry.result)
                                    .font(NK.mono(11.5))
                                    .foregroundStyle(NK.t1)
                            }
                            .padding(.vertical, 7)
                            Hairline()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private var display: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(model.expression.isEmpty ? "0" : model.expression)
                .font(NK.mono(15))
                .foregroundStyle(model.expression.isEmpty ? NK.t4 : NK.t2)
                .lineLimit(1)
                .truncationMode(.head)
            Text(model.result.isEmpty ? " " : model.result)
                .font(.system(size: 26, weight: .semibold, design: .monospaced))
                .kerning(-1)
                .foregroundStyle(NK.t1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: NK.radiusCard, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NK.radiusCard, style: .continuous)
                .stroke(NK.line, lineWidth: 1)
        )
        .onTapGesture { model.copyResult() }
        .help("Cliquer copie le résultat")
    }

    private var keypad: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                key("C", tint: NK.bad) { model.clear() }
                key("⌫", tint: NK.t2) { model.backspace() }
                key("(", tint: NK.t2) { model.input("(") }
                key(")", tint: NK.t2) { model.input(")") }
            }
            ForEach(rows, id: \.first) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { token in
                        key(token, tint: "÷×-+".contains(token) ? NK.accent : NK.t1) {
                            model.input(token)
                        }
                    }
                }
            }
            key("=", tint: .black, filled: true) { model.commit() }
        }
    }

    private func key(_ label: String, tint: Color, filled: Bool = false,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(NK.ui(13, .semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(filled ? Color.white : Color.white.opacity(0.05))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
