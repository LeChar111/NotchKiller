import SwiftUI

struct NotesView: View {
    @State private var noteText = ""
    @State private var formatBold = false
    @State private var formatItalic = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            editor
                .padding(.top, 12)
                .padding(.bottom, 10)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if noteText.isEmpty {
                    Text("Note rapide…")
                        .font(NK.ui(12.5, .medium))
                        .foregroundStyle(NK.t4)
                        .padding(.horizontal, 5)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $noteText)
                    .font(.system(size: 12.5, weight: formatBold ? .bold : .regular, design: .rounded))
                    .italic(formatItalic)
                    .foregroundStyle(Color.white.opacity(0.88))
                    .scrollContentBackground(.hidden)
                    .frame(height: 156)
            }

            HStack(spacing: 6) {
                Text("\(noteText.count) signes")
                    .font(NK.ui(10, .semibold))
                    .foregroundStyle(NK.t3)
                Spacer()
                miniButton("B", active: formatBold) { formatBold.toggle() }
                miniButton("I", active: formatItalic) { formatItalic.toggle() }
                miniButton("✕", active: false) { noteText = "" }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: NK.radiusCard, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NK.radiusCard, style: .continuous)
                .stroke(NK.line, lineWidth: 1)
        )
    }

    private func miniButton(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(NK.ui(10.5, .bold))
                .foregroundStyle(active ? NK.t1 : NK.t3)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }
}
