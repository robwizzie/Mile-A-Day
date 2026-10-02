import SwiftUI

/// The feed card's action row: hype · comment · share leading, and the media
/// controls (FLYOVER · SPLITS, and a post's PHOTO | MAP toggle) trailing on
/// the SAME row whenever they fit — they used to take a row of their own
/// under the media, which on most cards was ~40pt spent on two chips.
///
/// The row must fit the card, and a squeezed `HStack` doesn't re-arrange — it
/// wraps the innermost `Text` ("FLYOVE / R"). Every constant label refuses to
/// wrap, so fitting is this view's job, through candidates that differ in
/// ARRANGEMENT only — never in which controls exist:
/// 1. one row, every chip labelled;
/// 2. one row, SPLITS as its glyph alone (FLYOVER keeps its word — it's the
///    one people have to discover);
/// 3. the controls on their own row above the actions (the old layout);
/// 4. the trailing toggle on a row of its own as well.
struct FeedActionRow<Actions: View, Controls: View, Trailing: View>: View {
    /// Whether there's anything to put trailing — without it the row is
    /// just the actions and none of the fitting runs.
    let hasControls: Bool
    @ViewBuilder let actions: () -> Actions
    /// The chips; `compact` asks for the glyph-only SPLITS.
    @ViewBuilder let controls: (_ compact: Bool) -> Controls
    @ViewBuilder let trailing: () -> Trailing

    init(hasControls: Bool,
         @ViewBuilder actions: @escaping () -> Actions,
         @ViewBuilder controls: @escaping (_ compact: Bool) -> Controls,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.hasControls = hasControls
        self.actions = actions
        self.controls = controls
        self.trailing = trailing
    }

    var body: some View {
        if hasControls {
            ViewThatFits(in: .horizontal) {
                oneRow(compact: false)
                oneRow(compact: true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        controls(false)
                        Spacer(minLength: 8)
                        trailing()
                    }
                    actionsRow
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        controls(false)
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        trailing()
                    }
                    actionsRow
                }
            }
        } else {
            actionsRow
        }
    }

    private func oneRow(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 2) {
            actions()
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                controls(compact)
                trailing()
            }
        }
    }

    private var actionsRow: some View {
        HStack(alignment: .center, spacing: 2) {
            actions()
            Spacer(minLength: 0)
        }
    }
}

/// "🔥 74-day streak · 🏆 Fall Clash ›          OCT 1 · 1:25 PM" — the
/// streak, an optional middle (a post's competition link) and the exact time
/// on ONE quiet line under the actions. They were up to three lines.
///
/// The middle is user-typed DATA, so it is the one thing allowed to give: it
/// truncates and yields priority. The streak and the time are bounded and
/// never do. At accessibility sizes the time drops to a line of its own
/// rather than squeezing either.
struct FeedMetaLine<Middle: View>: View {
    let streak: Int?
    let timestamp: String?
    let hasMiddle: Bool
    @ViewBuilder let middle: () -> Middle

    init(streak: Int?, timestamp: String?, hasMiddle: Bool,
         @ViewBuilder middle: @escaping () -> Middle) {
        self.streak = (streak ?? 0) > 0 ? streak : nil
        self.timestamp = timestamp
        self.hasMiddle = hasMiddle
        self.middle = middle
    }

    var body: some View {
        if streak != nil || hasMiddle || timestamp != nil {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    leading
                    Spacer(minLength: 8)
                    if streak != nil || hasMiddle { time }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        leading
                        Spacer(minLength: 0)
                    }
                    if streak != nil || hasMiddle { time }
                }
            }
            .frame(minHeight: 22)
        }
    }

    /// Streak · middle — or, on a card with neither, the time itself, so a
    /// lone timestamp sits where the eye starts rather than out at the edge.
    @ViewBuilder
    private var leading: some View {
        if let streak {
            HStack(spacing: 3) {
                Image(systemName: "flame.fill")
                    .madFont(size: 10, weight: .semibold)
                Text("\(streak)-day streak")
                    .madFont(size: 12, weight: .semibold, design: .rounded)
                    .monospacedDigit()
            }
            .foregroundColor(.orange.opacity(0.85))
            .lineLimit(1)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(streak) day streak")
        }
        if streak != nil, hasMiddle {
            Text("·")
                .madFont(size: 12, weight: .bold, design: .rounded)
                .foregroundColor(.white.opacity(0.3))
                .accessibilityHidden(true)
        }
        if hasMiddle {
            middle()
                .layoutPriority(-1)
        }
        if streak == nil, !hasMiddle { time }
    }

    @ViewBuilder
    private var time: some View {
        if let timestamp {
            Text(timestamp)
                .madFont(size: 11, weight: .medium, design: .rounded)
                .foregroundColor(.white.opacity(0.46))
                .textCase(.uppercase)
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel(timestamp)
        }
    }
}

extension FeedMetaLine where Middle == EmptyView {
    init(streak: Int?, timestamp: String?) {
        self.init(streak: streak, timestamp: timestamp, hasMiddle: false) { EmptyView() }
    }
}

/// The feed's exact-time format, shared by both card kinds.
enum FeedTimestamp {
    /// "Oct 1 · 1:25 PM" this year, "Oct 1, 2025 · 1:25 PM" otherwise.
    static func timestamp(for date: Date) -> String {
        let thisYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        return (thisYear ? timestampFormatter : timestampWithYearFormatter).string(from: date)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d · h:mm a"
        return formatter
    }()

    private static let timestampWithYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy · h:mm a"
        return formatter
    }()
}
