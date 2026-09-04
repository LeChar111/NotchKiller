import SwiftUI

/// Bloc compact du minuteur, posé sur l'accueil. Le décompte lui-même vit dans
/// le bandeau fermé — c'est précisément à cela qu'une encoche sert.
struct TimerBlock: View {
    var timer: NotchTimer = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                SectionLabel(timer.isActive ? timer.label : "Minuteur")
                if timer.completedRounds > 0 {
                    Text("×\(timer.completedRounds)")
                        .font(NK.mono(9))
                        .foregroundStyle(NK.t4)
                }
                Spacer(minLength: 0)
            }

            if timer.isActive {
                running
            } else {
                presets
            }
        }
    }

    private var running: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(timer.display)
                    .font(.system(size: 26, weight: .semibold, design: .monospaced))
                    .kerning(-1)
                    .foregroundStyle(NK.t1)
                MeterBar(value: timer.progress,
                         tint: timer.phase == .rest ? NK.ok : NK.accent, height: 3)
                    .frame(width: 92)
            }

            VStack(spacing: 6) {
                control(icon: timer.isRunning ? "pause.fill" : "play.fill", filled: true) {
                    timer.toggle()
                }
                control(icon: "stop.fill", filled: false) { timer.reset() }
            }
        }
    }

    private var presets: some View {
        HStack(spacing: 8) {
            preset("25 / 5", highlighted: true) { timer.startPomodoro() }
            preset("15") { timer.start(minutes: 15) }
            preset("45") { timer.start(minutes: 45) }
        }
    }

    private func preset(_ label: String, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(NK.ui(11, .semibold))
                .foregroundStyle(highlighted ? NK.accent : NK.t2)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: NK.radiusControl, style: .continuous)
                        .fill(highlighted ? NK.accent.opacity(0.14) : Color.white.opacity(0.05))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(highlighted ? "Pomodoro : 25 min de travail, 5 min de pause" : "\(label) minutes")
    }

    private func control(icon: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(filled ? .black : NK.t3)
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(filled ? Color.white : Color.white.opacity(0.06))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
