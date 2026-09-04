import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    var shelf: ShelfModel = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dropZone
                .padding(.top, 12)
                .padding(.bottom, 10)
        }
    }

    private var dropZone: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 13)
                .padding(.bottom, shelf.isEmpty ? 0 : 4)

            if shelf.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            } else {
                itemsList
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: NK.radiusCard + 2, style: .continuous)
                .fill(Color.white.opacity(shelf.isDropTargeted ? 0.045 : 0.015))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NK.radiusCard + 2, style: .continuous)
                .stroke(
                    shelf.isDropTargeted ? NK.accent.opacity(0.8) : NK.line2,
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                )
        )
        .onDrop(
            of: [.fileURL, .url, .utf8PlainText],
            isTargeted: Binding(
                get: { shelf.isDropTargeted },
                set: { shelf.isDropTargeted = $0 }
            )
        ) { providers in
            shelf.handleDrop(providers: providers)
            return true
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NK.t4)
            SectionLabel(shelf.isEmpty
                ? "Déposer ici"
                : "Déposer ici · \(shelf.items.count) élément\(shelf.items.count > 1 ? "s" : "")")
            Spacer()
            if !shelf.isEmpty {
                Button("Vider") { shelf.removeAll() }
                    .font(NK.ui(10, .semibold))
                    .foregroundStyle(NK.t3)
                    .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 22))
                .foregroundStyle(NK.t4)
            Text("Glissez fichiers, textes ou liens")
                .font(NK.ui(12, .medium))
                .foregroundStyle(NK.t3)
        }
    }

    private var itemsList: some View {
        AdaptiveScrollView(maxHeight: NotchConstants.maxExpandedContentHeight - 110) {
            VStack(spacing: 0) {
                ForEach(shelf.items) { item in
                    shelfItemRow(item)
                }
            }
        }
    }

    private func shelfItemRow(_ item: ShelfItem) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(nsImage: item.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .padding(1)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.05)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayName)
                        .font(NK.ui(11.5, .medium))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .lineLimit(1)
                    SectionLabel(kindLabel(item.kind))
                }

                Spacer(minLength: 0)

                HStack(spacing: 2) {
                    if case .file = item.kind {
                        miniAction(icon: "eye") { shelf.quickLook(item) }
                        miniAction(icon: "doc.zipper") { shelf.compress(item) }
                        miniAction(icon: "folder") { item.revealInFinder() }
                    }
                    ShareAnchor { view in shelf.share(item, from: view) }
                    miniAction(icon: "arrow.up.right") { item.open() }
                    miniAction(icon: "xmark") { shelf.remove(item) }
                }
                .frame(height: 22)
            }
            .padding(.vertical, 8)

            Hairline()
        }
    }

    private func kindLabel(_ kind: ShelfItemKind) -> String {
        switch kind {
        case .file: "Fichier"
        case .text: "Texte"
        case .link: "Lien"
        }
    }

    /// Le sélecteur de partage doit s'ancrer à une vue AppKit réelle : sans
    /// ancre, la palette AirDrop s'ouvre au coin de l'écran.
    private struct ShareAnchor: NSViewRepresentable {
        let present: (NSView) -> Void

        func makeNSView(context: Context) -> NSButton {
            let button = NSButton(image: NSImage(systemSymbolName: "square.and.arrow.up",
                                                 accessibilityDescription: "Partager") ?? NSImage(),
                                  target: context.coordinator, action: #selector(Coordinator.fire))
            button.isBordered = false
            button.contentTintColor = NSColor.white.withAlphaComponent(0.34)
            button.toolTip = "Partager, AirDrop"
            context.coordinator.present = present
            context.coordinator.button = button
            return button
        }

        func updateNSView(_ nsView: NSButton, context: Context) {
            context.coordinator.present = present
        }

        func makeCoordinator() -> Coordinator { Coordinator() }

        final class Coordinator: NSObject {
            var present: ((NSView) -> Void)?
            weak var button: NSButton?
            @objc func fire() {
                guard let button else { return }
                present?(button)
            }
        }
    }

    private func miniAction(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NK.t3)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }
}
