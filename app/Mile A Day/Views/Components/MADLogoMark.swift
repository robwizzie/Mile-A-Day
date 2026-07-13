import SwiftUI

/// Reusable app logo mark for branded share/recap cards. Use this instead of
/// rebuilding a flame icon + "Mile A Day" text lockup in visual card art.
struct MADLogoMark: View {
    var size: CGFloat = 44
    var opacity: Double = 0.95
    var shadow: Bool = true

    var body: some View {
        Image("mad-logo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .opacity(opacity)
            .shadow(color: shadow ? .black.opacity(0.35) : .clear, radius: shadow ? 10 : 0, y: shadow ? 4 : 0)
            .accessibilityLabel("Mile A Day")
    }
}
