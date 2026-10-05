import SwiftUI

// MARK: - Compete design language
//
// ONE flat, editorial vocabulary for every competition surface: the list, the
// detail screen's tabs, the standings, the finished screen, the lobby and the
// trophy case. Every atom a competition screen draws is defined here, so
// "make a card" is a call and not a judgement call.
//
// What changed and why: the old screens were built from `.ultraThinMaterial`
// under a gradient stroke, with medal gradients, glowing pedestals and a
// different set of paddings per file. Layered, that reads as DATED — not
// because it is plain but because it is decorated in three directions at once,
// and the decoration competes with the only thing a leaderboard exists to say:
// who is ahead, by how much. So:
//
//   * ONE surface (`CompeteSurface`) — a flat lifted fill under a hairline.
//     No material, no gradient border. Blur costs a frame on a long scroll and
//     buys nothing over a black ground.
//   * ONE accent, the competition's own, used for the leader and the bars and
//     nothing else. Medal colour appears on the top three rank chips only.
//   * NUMBERS ARE THE DESIGN. Scores are heavy, monospaced-digit and right
//     aligned, so a column of them reads as a column. `.monospacedDigit()` is
//     not cosmetic here: proportional digits make "5 pts" and "2 pts" sit at
//     different widths and the column visibly ripples as scores tick over.
//   * Hierarchy by TYPE AND SPACE, not by more chrome: an uppercase tracked
//     eyebrow, a big title, hairline rules between rows.
//
// Rules of the road for anything added later:
//   * Never `.fixedSize` a label whose text is DATA (a username, a team name).
//     It publishes a minimum width no ancestor can shrink and overflows the
//     card off-screen — see `WorkoutSourceChip` in .claude/rules/ios.md.
//   * A number beside a name needs `lineLimit(1)`, or SwiftUI wraps its digits.
//   * Every `repeatForever` is guarded by Reduce Motion.

enum CompeteDesign {

    // MARK: Surface

    /// The one card fill. Flat, not a material.
    static let surface = Color.white.opacity(0.045)
    /// The one hairline. Every border on a competition screen is this.
    static let hairline = Color.white.opacity(0.09)
    /// The rule BETWEEN rows inside a card — lighter than the card's own edge,
    /// so a list reads as one object rather than a stack of them.
    static let rowRule = Color.white.opacity(0.06)
    /// Empty track behind a progress bar.
    static let track = Color.white.opacity(0.07)

    static let radius: CGFloat = 18
    static let innerRadius: CGFloat = 12

    // MARK: Ink

    /// Primary — names, headline numbers.
    static let ink = Color.white
    /// Secondary — a score that isn't the leader's, a supporting label.
    static let inkMuted = Color.white.opacity(0.62)
    /// Tertiary — eyebrows, units, counts, the rank number outside the top 3.
    static let inkFaint = Color.white.opacity(0.38)
    /// Quaternary — the rule-adjacent, the disabled, the eliminated.
    static let inkGhost = Color.white.opacity(0.22)

    // MARK: Type

    /// The uppercase tracked label above a group. Small, wide, quiet — it is a
    /// signpost, not a headline.
    static let eyebrow = Font.system(size: 11, weight: .bold, design: .rounded)
    static let eyebrowTracking: CGFloat = 1.4

    static let title = Font.system(size: 22, weight: .bold, design: .rounded)
    static let name = Font.system(size: 16, weight: .semibold, design: .rounded)
    static let nameSmall = Font.system(size: 14, weight: .semibold, design: .rounded)
    /// A competitor's score on a row.
    static let score = Font.system(size: 17, weight: .heavy, design: .rounded)
    /// The supporting figure under a name (miles covered, contribution).
    static let detail = Font.system(size: 12, weight: .medium, design: .rounded)
    static let caption = Font.system(size: 11, weight: .medium, design: .rounded)

    // MARK: Medals

    /// Solid medal colours — ONE colour each, not a gradient. A gradient on a
    /// 26pt chip is invisible as a gradient and only muddies the hue.
    static func medal(_ place: Int) -> Color? {
        switch place {
        case 1: return Color(red: 1.00, green: 0.78, blue: 0.24)
        case 2: return Color(red: 0.78, green: 0.81, blue: 0.86)
        case 3: return Color(red: 0.83, green: 0.55, blue: 0.33)
        default: return nil
        }
    }

    /// The competition's own accent — the bars, the leader's numbers, the
    /// focus states. Taken from the type's first gradient stop so a Clash and
    /// an Apex still feel like different competitions.
    static func accent(_ type: CompetitionType) -> Color {
        type.gradient.first.map { Color(hex: $0) } ?? MADTheme.Colors.madRed
    }
}

// MARK: - Surface

/// The flat card every competition group sits on.
struct CompeteSurface<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: CompeteDesign.radius, style: .continuous)
                    .fill(CompeteDesign.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CompeteDesign.radius, style: .continuous)
                    .strokeBorder(CompeteDesign.hairline, lineWidth: 1)
            )
    }
}

/// Eyebrow + title + optional trailing control, above a group.
///
/// The title column wraps on CONTENT: `actions` is `shrink-0`-shaped (a pill
/// row that refuses to compress), so the title needs `min-w-0` behaviour —
/// `layoutPriority` plus a real `lineLimit` — or a long competition name
/// pushes the control off the card. Same failure the admin dashboard hit.
struct CompeteHeader<Actions: View>: View {
    let eyebrow: String
    var title: String?
    var trailingText: String?
    @ViewBuilder var actions: Actions

    init(
        eyebrow: String,
        title: String? = nil,
        trailingText: String? = nil,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.trailingText = trailingText
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MADTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow.uppercased())
                    .font(CompeteDesign.eyebrow)
                    .tracking(CompeteDesign.eyebrowTracking)
                    .foregroundColor(CompeteDesign.inkFaint)
                    .lineLimit(1)

                if let title {
                    Text(title)
                        .font(CompeteDesign.title)
                        .foregroundColor(CompeteDesign.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let trailingText {
                Text(trailingText)
                    .font(CompeteDesign.caption)
                    .foregroundColor(CompeteDesign.inkFaint)
                    .lineLimit(1)
                    .fixedSize()
            }

            actions
        }
    }
}

// MARK: - Rank

/// The number beside a competitor. Top three wear their medal as a solid tint;
/// everyone else is a plain numeral, because a chip around every row turns a
/// leaderboard into a grid of chips and the medals stop meaning anything.
struct CompeteRankBadge: View {
    let place: Int
    /// Drawn when two competitors are genuinely level — same score, same
    /// distance — so a repeated number reads as a tie and not as a bug.
    var isTied: Bool = false
    var size: CGFloat = 26

    var body: some View {
        Group {
            if let medal = CompeteDesign.medal(place) {
                ZStack {
                    Circle().fill(medal.opacity(0.18))
                    Circle().strokeBorder(medal.opacity(0.55), lineWidth: 1)
                    // The tie marker belongs on a medal too: two competitors
                    // level for 1st otherwise drew two identical gold chips
                    // and the board looked like it had two winners by mistake.
                    Text(isTied ? "T\(place)" : "\(place)")
                        .font(.system(size: size * (isTied ? 0.40 : 0.48), weight: .heavy, design: .rounded))
                        .foregroundColor(medal)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: size, height: size)
            } else {
                Text(isTied ? "T\(place)" : "\(place)")
                    .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                    .foregroundColor(CompeteDesign.inkFaint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: size, height: size)
            }
        }
        .accessibilityLabel(isTied ? "Tied for place \(place)" : "Place \(place)")
    }
}

// MARK: - Bar

/// The relative-progress bar under a competitor's name. Value is already
/// normalised 0...1 by the caller, which is deliberate: what a bar is relative
/// TO (the leader, the goal, the field's total) differs per surface and is a
/// decision the surface has to make out loud.
struct CompeteBar: View {
    let fraction: Double
    var color: Color
    var height: CGFloat = 4
    /// Draws the track only. A zero-score row still gets its lane, so the list
    /// keeps its rhythm instead of the bars disappearing halfway down.
    var isEmpty: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(CompeteDesign.track)
                if !isEmpty, fraction > 0 {
                    Capsule()
                        .fill(color)
                        .frame(width: max(height, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Divider

/// The hairline between rows inside a card.
struct CompeteRowRule: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(CompeteDesign.rowRule)
            .frame(height: 1)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}

// MARK: - Chips

/// A small label carrying a fact about a row (YOU, OUT, MANUAL, a team name).
///
/// Never `.fixedSize()` — `text` can be a team name, which is user-typed data.
struct CompeteTag: View {
    let text: String
    var color: Color = MADTheme.Colors.madRed
    var filled: Bool = true

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .tracking(0.4)
            .foregroundColor(filled ? .white : color)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(filled ? color : color.opacity(0.16))
            )
    }
}

/// The segmented control the standings and the finished screen switch modes
/// with. One nowrap line of pills — the host is responsible for giving it room
/// (see `CompeteHeader`).
struct CompeteSegmented<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var accent: Color = .white

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isOn = option.value == selection
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.label)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(isOn ? .black : CompeteDesign.inkMuted)
                        .lineLimit(1)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(isOn ? Color.white.opacity(0.92) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(CompeteDesign.hairline, lineWidth: 1))
    }
}

// MARK: - Stat

/// One figure in a row of figures (the recap, the header summary). Label under
/// value, left aligned, no icon — an icon per stat was six colours competing
/// with the leaderboard above them.
struct CompeteStat: View {
    let value: String
    let label: String
    var tint: Color = CompeteDesign.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundColor(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundColor(CompeteDesign.inkFaint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A row of `CompeteStat`s divided by hairlines. Equal columns under one rule,
/// like the share card's stat rail — an `HStack` with fixed spacing lets the
/// columns drift with their content.
struct CompeteStatRail: View {
    let stats: [(value: String, label: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                if index > 0 {
                    Rectangle()
                        .fill(CompeteDesign.rowRule)
                        .frame(width: 1, height: 26)
                        .padding(.horizontal, 10)
                        .accessibilityHidden(true)
                }
                CompeteStat(value: stat.value, label: stat.label)
            }
        }
    }
}
