import SwiftUI

/// ScrollView qui épouse la hauteur de son contenu jusqu'à un plafond,
/// puis devient scrollable. Indispensable pour que le panneau se dimensionne
/// sur le contenu : un ScrollView nu absorbe toute la hauteur proposée.
struct AdaptiveScrollView<Content: View>: View {
    var maxHeight: CGFloat = NotchConstants.maxExpandedContentHeight
    var minHeight: CGFloat = 0
    @ViewBuilder var content: Content

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    contentHeight = height
                }
        }
        .frame(height: min(max(contentHeight, minHeight), maxHeight))
        .scrollDisabled(contentHeight <= maxHeight)
    }
}
