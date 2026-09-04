import SwiftUI

struct InlineHUD: View {
    var volumeManager: VolumeManager
    var brightnessManager: BrightnessManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                hudRow(
                    icon: volumeManager.isMuted ? "speaker.slash.fill" : volumeIcon,
                    label: "Volume",
                    value: volumeManager.isMuted ? 0 : volumeManager.volume,
                    tint: NK.accent,
                    onChanged: { volumeManager.setVolume($0) }
                )
                hudRow(
                    icon: brightnessIcon,
                    label: "Luminosité",
                    value: brightnessManager.brightness,
                    tint: NK.warn,
                    onChanged: { brightnessManager.setBrightness($0) }
                )
            }
            .padding(.top, 10)

            outputSection
                .padding(.top, NK.sectionGap)
                .padding(.bottom, 12)
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionLabel("Sortie")
            Button { volumeManager.toggleMute() } label: {
                HStack(spacing: 7) {
                    Image(systemName: volumeManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(volumeManager.isMuted ? "Réactiver le son" : "Couper le son")
                        .font(NK.ui(11, .semibold))
                }
                .foregroundStyle(volumeManager.isMuted ? NK.t1 : NK.t2)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: NK.radiusControl, style: .continuous)
                        .fill(Color.white.opacity(volumeManager.isMuted ? 0.12 : 0.045))
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// Curseur avec poignée visible : la barre seule ne dit pas où saisir.
    private func hudRow(
        icon: String,
        label: String,
        value: Float,
        tint: Color,
        onChanged: @escaping (Float) -> Void
    ) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(tint)
                        .frame(width: 18)
                    Text(label)
                        .font(NK.ui(11.5, .semibold))
                        .foregroundStyle(NK.t2)
                    Spacer()
                    Text("\(Int(value * 100)) %")
                        .font(NK.mono(12))
                        .foregroundStyle(NK.t1)
                }

                GeometryReader { proxy in
                    let width = proxy.size.width
                    let clamped = CGFloat(max(0, min(1, value)))
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.09))
                            .frame(height: 6)
                        Capsule()
                            .fill(tint)
                            .frame(width: max(6, width * clamped), height: 6)
                        Circle()
                            .fill(.white)
                            .frame(width: 14, height: 14)
                            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                            .offset(x: max(0, min(width - 14, width * clamped - 7)))
                    }
                    .frame(height: 14)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                onChanged(Float(max(0, min(1, drag.location.x / width))))
                            }
                    )
                }
                .frame(height: 14)
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var volumeIcon: String {
        if volumeManager.volume == 0 { return "speaker.fill" }
        if volumeManager.volume < 0.33 { return "speaker.wave.1.fill" }
        if volumeManager.volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private var brightnessIcon: String {
        brightnessManager.brightness < 0.5 ? "sun.min.fill" : "sun.max.fill"
    }
}
