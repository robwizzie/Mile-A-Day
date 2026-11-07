import SwiftUI

/// A tab's two pages on the Duo's inner display, either side of the fold. Each
/// scrolls on its own, and tells `lockedToScrollWidth()` its width, because
/// that helper otherwise measures the whole navigation column.
struct DuoTwoPages<Left: View, Right: View>: View {
    var leftTitle: LocalizedStringKey? = nil
    var rightTitle: LocalizedStringKey? = nil
    @ViewBuilder let left: () -> Left
    @ViewBuilder let right: () -> Right

    var body: some View {
        GeometryReader { geo in
            let pageWidth = geo.size.width / 2
            HStack(spacing: 0) {
                page(title: leftTitle, width: pageWidth, content: left)
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 1)
                page(title: rightTitle, width: pageWidth - 1, content: right)
            }
        }
    }

    private func page<Content: View>(title: LocalizedStringKey?, width: CGFloat,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .madFont(size: 20, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }
            content()
                .environment(\.duoColumnWidth, width)
                .frame(maxHeight: .infinity)
        }
        .frame(width: width)
    }
}
