import SwiftUI

/// The Feed tab's spacing, in one place. Every edge on the tab — header,
/// stories, post headers, media, captions — sits on ONE gutter, and every
/// vertical gap is one of three steps, instead of the per-view guesses
/// (`sm + 2`, `10`, `4`, a 2pt nudge) that put the same content at three
/// different x-positions down one screen.
enum FeedLayout {
    /// The tab's single horizontal edge. Matches `MADTabHeader`'s inset, so
    /// the title, the first story and every post's avatar line up.
    static let gutter: CGFloat = MADTheme.Spacing.md            // 16
    /// Between posts (either side of the hairline) and between the feed's
    /// stacked blocks.
    static let postGap: CGFloat = MADTheme.Spacing.md           // 16
    /// Inside a post: header → media → actions.
    static let rowGap: CGFloat = MADTheme.Spacing.sm            // 8
    /// Avatar → name in a post header.
    static let avatarGap: CGFloat = 10
    /// The boxed (`.card`) surface's inset, for the screens that still box a post.
    static let cardInset: CGFloat = 10
    /// Story rail: cell width and the gap between cells.
    static let storyCell: CGFloat = 72
    static let storyGap: CGFloat = 12
    /// Extra space under each stacked post, on top of `postGap`, so posts
    /// separate by space alone (no rule, no panel).
    static let postSpacing: CGFloat = 12
}

/// How a feed card draws its surface.
///
/// `.card` is the boxed look (a 4%-white rounded panel with its own inset),
/// kept for screens where a post sits alone among other content — post
/// detail, a profile, a workout. `.stacked` is the Feed tab: no panel, no
/// inset, posts separated by a hairline, so the media spans the full gutter
/// instead of being boxed twice (page → panel → media).
enum FeedCardChrome {
    case card
    case stacked
}

private struct FeedCardChromeKey: EnvironmentKey {
    static let defaultValue: FeedCardChrome = .card
}

extension EnvironmentValues {
    var feedCardChrome: FeedCardChrome {
        get { self[FeedCardChromeKey.self] }
        set { self[FeedCardChromeKey.self] = newValue }
    }
}

private struct FeedMediaCornerRadiusKey: EnvironmentKey {
    static let defaultValue: CGFloat = MADTheme.CornerRadius.medium
}

extension EnvironmentValues {
    /// The corner radius every feed media face clips to (photos, route art,
    /// the routeless card, the locked card, and the pinch-zoom copy). 0 on
    /// the Feed tab, where media runs edge to edge; rounded everywhere else.
    var feedMediaCornerRadius: CGFloat {
        get { self[FeedMediaCornerRadiusKey.self] }
        set { self[FeedMediaCornerRadiusKey.self] = newValue }
    }
}

/// The surface `PostCardView` and `ActivityCardView` share, so the two card
/// kinds can't drift into different insets again.
struct FeedCardSurface: ViewModifier {
    let chrome: FeedCardChrome

    @ViewBuilder
    func body(content: Content) -> some View {
        switch chrome {
        case .card:
            content
                .padding(FeedLayout.cardInset)
                .background(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
        case .stacked:
            content
        }
    }
}

/// The 1px rule between stacked posts.
struct FeedHairline: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1 / max(displayScale, 1))
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}
