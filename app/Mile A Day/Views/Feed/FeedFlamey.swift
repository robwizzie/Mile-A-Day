import SwiftUI

/// Whose look a walk/run card wears: the AUTHOR's dashboard style, never the
/// viewer's. A friend on Fun gets Flamey on their cards, a friend on Modern
/// gets the plain card, and a viewer's own setting decides nothing about
/// somebody else's walk.
///
/// The server's signal is `author_flamey` — non-null ONLY when the author's
/// `users.dashboard_style` is 'fun' (reported by their app on every launch
/// via `DashboardStyleReporter`). So nil means Modern, a pre-field build that
/// never reported, or an older server, and every one of those draws the
/// plain card. On your own posts the local preference is fresher than the
/// copy the post carries, so it wins.
@MainActor
enum FeedCardFlamey {
    /// The Flamey to draw on this card, or nil for the Modern card.
    static func look(authorFlamey: AuthorFlamey?, isOwn: Bool) -> FlameyLook? {
        if isOwn {
            // `FlameyFacts.look` is nil on Modern — exactly the rule.
            return FlameyFacts.look(detail: .compact)
        }
        return authorFlamey?.resolved()
    }

    /// His name for the cheer ("GO SPARKY!"), nil = unnamed.
    static func name(authorFlamey: AuthorFlamey?, isOwn: Bool) -> String? {
        isOwn ? FlameyFacts.name : authorFlamey?.displayName
    }

    /// The cheer, sized for a card: his name when it fits, else the plain one.
    static func cheer(name: String?) -> String {
        if let name, name.count <= 8 { return "GO \(name.uppercased())!" }
        return "GO GO GO!"
    }
}

/// Flamey running a route beside the author's badge on a Fun author's map
/// card: rides the line's tip as it draws (the caller applies the same
/// `RouteRiderEffect` + animation as the badge, so he can't drift off it)
/// and throws both arms up when the walk lands.
///
/// Motion is transform-only under `repeatForever` (the feed-cell rule — no
/// TimelineView, no per-frame redraw of the figure), started on the next
/// turn rather than inside `onAppear` (ios.md: an animation begun in the
/// initial commit leaks into every later layout change of the subtree).
struct RouteFlameyRunner: View {
    let look: FlameyLook
    /// The draw has landed — arms go up.
    let finished: Bool
    /// A baked frame (zoom composite) or Reduce Motion: no bob.
    let still: Bool
    var size: CGFloat = 30

    @State private var striding = false

    var body: some View {
        ZStack {
            // A soft dark puddle under him so he reads over a busy map
            // without a `.shadow`/`.blur` (both cost per frame under a
            // moving transform, and blur bakes badly in ImageRenderer).
            Ellipse()
                .fill(RadialGradient(colors: [Color.black.opacity(0.55), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.5))
                .frame(width: size * 0.9, height: size * 0.32)
                .offset(y: size * 0.42)
            FlameyDressedFigure(look: look, health: .healthy, size: size,
                                scale: FlameHealth.healthy.bodyScale,
                                arms: finished ? .cheer : .rest)
                .rotationEffect(.degrees(still ? 0 : (striding ? 6 : -6)), anchor: .bottom)
                .offset(y: still ? 0 : (striding ? -2.5 : 0))
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !still else { return }
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.22).repeatForever(autoreverses: true)) {
                    striding = true
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The Fun author's warm layer over the card canvas: an ember glow rising
/// from the bottom and a few sparks drifting up. Every spark is ONE view
/// moved by offset/opacity under `repeatForever` — no clock, no redraw.
struct FunEmberLayer: View {
    let still: Bool
    @State private var rise = false

    /// (x as a fraction of width, start y fraction, size, duration, delay)
    private static let sparks: [(CGFloat, CGFloat, CGFloat, Double, Double)] = [
        (0.12, 0.92, 4, 3.4, 0.0),
        (0.27, 0.98, 3, 4.1, 0.9),
        (0.46, 0.95, 5, 3.8, 0.4),
        (0.63, 0.99, 3, 4.4, 1.6),
        (0.78, 0.93, 4, 3.6, 1.1),
        (0.90, 0.97, 3, 4.0, 2.0),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RadialGradient(
                    colors: [MADTheme.Colors.warning.opacity(0.30),
                             MADTheme.Colors.madRed.opacity(0.14),
                             .clear],
                    center: .bottom,
                    startRadius: 0,
                    endRadius: geo.size.height * 0.75
                )
                if !still {
                    ForEach(Array(Self.sparks.enumerated()), id: \.offset) { _, spark in
                        Circle()
                            .fill(MADTheme.Colors.warning)
                            .frame(width: spark.2, height: spark.2)
                            .position(x: geo.size.width * spark.0, y: geo.size.height * spark.1)
                            .offset(y: rise ? -geo.size.height * 0.55 : 0)
                            .opacity(rise ? 0 : 0.85)
                            .animation(.easeOut(duration: spark.3)
                                .repeatForever(autoreverses: false)
                                .delay(spark.4), value: rise)
                    }
                }
            }
        }
        .onAppear {
            guard !still else { return }
            // Set OUTSIDE withAnimation: each spark's own `.animation` carries
            // its duration and delay (an enclosing transaction would weld
            // them into one).
            DispatchQueue.main.async { rise = true }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
