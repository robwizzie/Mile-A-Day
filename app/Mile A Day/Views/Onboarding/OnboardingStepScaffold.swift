import SwiftUI

/// The shared look of every setup screen after the intro (sign in, Health,
/// notifications): the intro's colour hero with live art, the curved sheet
/// with the app icon on its crest, an optional step chip, one headline, one
/// line of copy, and the screen's actions pinned to the bottom.
///
/// Same geometry as `OnboardingIntroView` so moving from the tour into setup
/// reads as one flow. Art gets its height and should size from it.
struct OnboardingStepScaffold<Art: View, Actions: View>: View {
    let colors: [Color]
    var chip: String? = nil
    let headline: String
    let message: String
    @ViewBuilder let art: (CGFloat) -> Art
    @ViewBuilder let actions: () -> Actions

    @State private var shown = false

    private let curve: CGFloat = 26
    private let iconSize: CGFloat = 64

    var body: some View {
        GeometryReader { geo in
            let topInset = geo.safeAreaInsets.top
            let bottomInset = geo.safeAreaInsets.bottom
            let fullHeight = geo.size.height + topInset + bottomInset
            // ~56%, always leaving 420pt for copy + actions (taller than the
            // intro's: setup copy runs longer and the actions stack).
            let heroHeight = max(240, min(fullHeight * 0.56, fullHeight - 420))
            let artHeight = max(160, heroHeight - topInset - curve - iconSize / 2 - 24)

            ZStack(alignment: .top) {
                ZStack {
                    LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    RadialGradient(colors: [.white.opacity(0.18), .clear], center: .top,
                                   startRadius: 0, endRadius: 360)
                }
                .frame(height: heroHeight + curve)

                art(artHeight)
                    .frame(maxWidth: .infinity)
                    .frame(height: artHeight)
                    .padding(.top, topInset + 8)
                    .environment(\.introShown, shown)
                    .environment(\.introArtWidth, geo.size.width)

                IntroSheetShape(curve: curve)
                    .fill(OnboardingIntroView.sheetColor)
                    .padding(.top, heroHeight - curve)

                Image("mad-logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.24, style: .continuous))
                    // No frame ring: the icon sits straight on the crest.
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                    .padding(.top, heroHeight - curve - iconSize / 2)
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let chip {
                            Text(chip)
                                .madFont(size: 13, weight: .bold, design: .rounded, maxScale: 1.3)
                                .foregroundColor(colors[0])
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(colors[0].opacity(0.16)))
                        }
                        Text(headline)
                            .madFont(size: 32, weight: .heavy, design: .rounded, maxScale: 1.25)
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(message)
                            .madFont(size: 16, weight: .medium, design: .rounded, maxScale: 1.25)
                            .foregroundColor(.white.opacity(0.62))
                            .lineLimit(4)
                            // Not fixedSize: on a 320pt phone it shrinks a
                            // little rather than pushing the actions off screen.
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, heroHeight + iconSize / 2 + 18)

                    Spacer(minLength: 16)

                    actions()
                        .padding(.horizontal, 24)
                        .padding(.bottom, bottomInset + 14)
                }
            }
            .ignoresSafeArea()
        }
        .background(OnboardingIntroView.sheetColor.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .onAppear {
            guard !shown else { return }
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { shown = true }
            }
        }
    }
}

/// The intro's look for steps that ask something: the same gradient hero, sheet
/// and icon, with a shorter hero so the question has room, content that scrolls
/// under the keyboard, and the action pinned to the bottom.
struct OnboardingFormScaffold<Art: View, Content: View, Actions: View>: View {
    let colors: [Color]
    /// Zero-based step and count, for the dots. Nil hides them.
    var step: (index: Int, total: Int)? = nil
    let headline: String
    let message: String
    @ViewBuilder let art: (CGFloat) -> Art
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions

    @State private var shown = false

    private let curve: CGFloat = 26
    private let iconSize: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            let topInset = geo.safeAreaInsets.top
            let fullHeight = geo.size.height + topInset + geo.safeAreaInsets.bottom
            // The keyboard is the only thing that raises the bottom inset this
            // far. The hero makes way for it, or the question has nowhere to go.
            let keyboardUp = geo.safeAreaInsets.bottom > 120
            let heroHeight = keyboardUp ? topInset + curve + 8 : max(170, min(fullHeight * 0.29, 270))
            // Stops above the icon, so it never sits on Flamey's feet.
            let artHeight = max(70, heroHeight - topInset - curve - iconSize / 2 - 6)

            ZStack(alignment: .top) {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(height: heroHeight + curve)

                if !keyboardUp {
                    art(artHeight)
                        .frame(maxWidth: .infinity)
                        .frame(height: artHeight)
                        .padding(.top, topInset + 4)
                        .environment(\.introShown, shown)
                        .environment(\.introArtWidth, geo.size.width)
                }

                IntroSheetShape(curve: curve)
                    .fill(OnboardingIntroView.sheetColor)
                    .padding(.top, heroHeight - curve)

                if !keyboardUp {
                    Image("mad-logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize, height: iconSize)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                        .padding(.top, heroHeight - curve - iconSize / 2)
                        .accessibilityHidden(true)
                }

                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(headline)
                                    .madFont(size: 28, weight: .heavy, design: .rounded, maxScale: 1.25)
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.75)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(message)
                                    .madFont(size: 15, weight: .medium, design: .rounded, maxScale: 1.25)
                                    .foregroundColor(.white.opacity(0.62))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            content()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .padding(.top, keyboardUp ? heroHeight : heroHeight + iconSize / 2 - curve + 12)

                    if !keyboardUp {
                        VStack(spacing: 10) {
                            if let step { dots(step) }
                            actions()
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, max(geo.safeAreaInsets.bottom, 14))
                    }
                }
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .background(OnboardingIntroView.sheetColor.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .onAppear {
            guard !shown else { return }
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { shown = true }
            }
        }
    }

    private func dots(_ step: (index: Int, total: Int)) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<step.total, id: \.self) { i in
                Capsule()
                    .fill(i == step.index ? Color.white : Color.white.opacity(0.25))
                    .frame(width: i == step.index ? 22 : 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(step.index + 1) of \(step.total)")
    }
}

/// The setup screens' primary button: a full-width madRed pill.
struct OnboardingPrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView().tint(.white) }
            }
            .madFont(size: 18, weight: .bold, design: .rounded, maxScale: 1.3)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(Capsule().fill(MADTheme.Colors.madRed.opacity(isEnabled ? 1 : 0.35)))
        }
        .disabled(isLoading || !isEnabled)
    }
}

/// A quiet text button under the primary one ("Not now").
struct OnboardingSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .madFont(size: 16, weight: .semibold, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
    }
}
