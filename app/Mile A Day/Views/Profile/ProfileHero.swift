import SwiftUI

// The profile header, shared by your own profile and everyone else's: a
// full-width banner (uploaded photo or a gradient preset), the avatar hanging
// off its bottom edge inside today's goal ring, the next-mile milestone, the
// identity block, three stat tiles and an underline tab bar. Each piece is
// its own view so the two profile screens compose them with their own
// buttons and data sources without forking the look.

// MARK: - Banner presets

/// Gradient presets for the profile banner — the header behind the avatar
/// whenever the user hasn't uploaded a photo. Every stop is a colour the app
/// already uses (the theme's red/blue/green/orange/black and the ghost chip's
/// violet); the darker ends are those same colours over black, never new
/// ones. Raw values are what the server stores in `users.profile_banner_style`
/// (validated against the same list in usersController).
enum ProfileBannerStyle: String, CaseIterable, Identifiable {
    case ember, sunrise, sky, trail, ghost, night

    static let `default`: ProfileBannerStyle = .ember

    var id: String { rawValue }

    /// Server value → preset. Unknown or absent draws the default, so a build
    /// that predates a preset still renders a correct profile.
    static func resolve(_ raw: String?) -> ProfileBannerStyle {
        raw.flatMap(ProfileBannerStyle.init(rawValue:)) ?? .default
    }

    var title: String {
        switch self {
        case .ember: return "Ember"
        case .sunrise: return "Sunrise"
        case .sky: return "Sky"
        case .trail: return "Trail"
        case .ghost: return "Ghost"
        case .night: return "Night"
        }
    }

    /// The two live stops, all app colours.
    private var stops: (Color, Color) {
        switch self {
        case .ember:
            // MADTheme.Colors.redGradient's two stops.
            return (Color(red: 0.9, green: 0.3, blue: 0.4), MADTheme.Colors.madRed)
        case .sunrise:
            return (MADTheme.Colors.warning, MADTheme.Colors.madRed)
        case .sky:
            return (MADTheme.Colors.walkBlue, MADTheme.Colors.walkBlue)
        case .trail:
            return (MADTheme.Colors.success, MADTheme.Colors.success)
        case .ghost:
            // The "beat the ghost" chip's gradient.
            return (Color(red: 0.42, green: 0.31, blue: 0.85), Color(red: 0.24, green: 0.18, blue: 0.55))
        case .night:
            // MADTheme.Colors.blackGradient's two stops.
            return (Color(red: 0.15, green: 0.15, blue: 0.15), Color(red: 0.05, green: 0.05, blue: 0.05))
        }
    }

    /// Drawn over black (see `ProfileBannerView`), so the trailing stops fade
    /// into the page rather than into a new colour.
    var gradient: LinearGradient {
        let (a, b) = stops
        return LinearGradient(
            colors: [a, b.opacity(0.9), b.opacity(0.32)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Banner

/// The banner itself: the uploaded photo when there is one, else the preset
/// gradient. Scrims top and bottom keep the buttons over it and the page
/// under it legible on any photo.
struct ProfileBannerView: View {
    let imageURL: String?
    let style: ProfileBannerStyle
    /// A just-picked photo (Edit Profile preview) — wins over `imageURL`.
    var localImage: UIImage? = nil
    var scrims: Bool = true

    @State private var loaded: UIImage?

    var body: some View {
        ZStack {
            Color.black
            style.gradient
            // Overlay on a clear base so a `scaledToFill` photo can't grow the
            // banner past the frame the caller gave it.
            Color.clear
                .overlay {
                    if let image = localImage ?? loaded {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .clipped()
            if scrims {
                LinearGradient(colors: [.black.opacity(0.42), .clear], startPoint: .top, endPoint: .center)
                LinearGradient(colors: [.clear, .black.opacity(0.62)], startPoint: .center, endPoint: .bottom)
            }
        }
        .clipped()
        .task(id: imageURL) { await load() }
    }

    private func load() async {
        guard let url = ProfileImageService.fullImageURL(for: imageURL) else {
            loaded = nil
            return
        }
        if let cached = FeedImageCache.image(for: url) {
            loaded = cached
            return
        }
        loaded = nil
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return }
        FeedImageCache.store(image, for: url)
        loaded = image
    }
}

/// The round glass buttons that ride the banner (share, edit). Same 38pt
/// circle as `MADTabHeader`'s standard style, on a darker fill so they hold
/// up over a photo.
struct ProfileBannerButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ProfileBannerGlyph(systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// A banner button that opens a menu instead of acting — the same circle, so
/// the Share menu sits beside Edit as one set.
struct ProfileBannerMenu<Content: View>: View {
    let systemImage: String
    let accessibilityLabel: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu(content: content) {
            ProfileBannerGlyph(systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// The glyph-in-a-glass-circle both banner controls draw.
private struct ProfileBannerGlyph: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 38, height: 38)
            .background(
                Circle()
                    .fill(Color.black.opacity(0.35))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            )
            .contentShape(Circle())
    }
}

// MARK: - Goal ring

/// Avatar inside today's goal ring — the same colour language as the
/// dashboard and every friend row: orange while the mile is in progress,
/// green once it's done. `progress` nil = unknown (stats not loaded, or not
/// shared with the viewer) → the track alone, no claim.
struct GoalRingAvatar<Avatar: View>: View {
    let progress: Double?
    let isComplete: Bool
    /// A streak token is carrying today. The ring fills in SavedDayStyle's
    /// blue rather than reading as an unfinished orange arc — the day IS
    /// safe, and the one thing this ring must never do is contradict the
    /// streak number sitting under it.
    var savedToday: Bool = false
    /// Avatar diameter; the ring sits outside it.
    let size: CGFloat
    var ringWidth: CGFloat = 5
    var gap: CGFloat = 4
    @ViewBuilder let avatar: () -> Avatar

    static func ringDiameter(size: CGFloat, ringWidth: CGFloat = 5, gap: CGFloat = 4) -> CGFloat {
        size + 2 * gap + 2 * ringWidth
    }

    private var clamped: Double {
        (isComplete || savedToday) ? 1 : max(0, min(1, progress ?? 0))
    }

    var body: some View {
        let diameter = Self.ringDiameter(size: size, ringWidth: ringWidth, gap: gap)
        ZStack {
            // A dark disc fills the gap so the ring reads as a ring wherever
            // the avatar lands — over the banner's edge or the page.
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: size + 2 * gap, height: size + 2 * gap)
            Circle()
                .inset(by: ringWidth / 2)
                .stroke(Color.white.opacity(0.1), lineWidth: ringWidth)
            Circle()
                .inset(by: ringWidth / 2)
                .trim(from: 0, to: clamped)
                .stroke(
                    ringStyle,
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: clamped)
            avatar()
                .frame(width: size, height: size)
                .clipShape(Circle())
        }
        .frame(width: diameter, height: diameter)
    }

    /// Done → green. Saved → the token blue. Otherwise the in-progress
    /// orange sweep. Saved is checked FIRST only when the day isn't actually
    /// complete: a covered day the user then ran is a green day.
    private var ringStyle: AnyShapeStyle {
        if isComplete { return AnyShapeStyle(Color.green) }
        if savedToday { return AnyShapeStyle(SavedDayStyle.tint) }
        return AnyShapeStyle(
            AngularGradient(
                colors: [Color.orange.opacity(0.55), .orange, Color.orange.opacity(0.85)],
                center: .center,
                startAngle: .degrees(0),
                endAngle: .degrees(360)
            )
        )
    }
}

// The ring is the ONE place a profile says how today is going. A chip under
// it ("88% TO GOAL" / "GOAL DONE") and a green check on the Streak tile said
// the same thing again; both are gone. VoiceOver reads the state off the
// avatar button (`ProfileHero.goalAccessibilityValue`).

// MARK: - Next milestone

/// Total-mile milestones = the total-miles MEDALS. The rungs are the badge
/// catalog's `miles_*` thresholds (backend/scripts/badges-seed.sql), so the
/// chip names exactly the medal the Total Miles screen calls "Next Medal".
/// Callers pass the live catalog when they have it (the server can add
/// rungs); the seed ladder is the fallback. Past the last medal the chip
/// keeps counting in 500s so it never runs out of a target.
enum MileMilestones {
    static let seedLadder: [Double] = [25, 50, 100, 150, 200, 250, 500, 750, 1000, 1500, 2000, 2500]

    /// Mile thresholds out of a badge list (earned or locked, either is fine —
    /// only the `miles_N` ids are read). Empty when the list has none.
    static func thresholds(from badges: [Badge]) -> [Double] {
        badges
            .filter { $0.id.hasPrefix("miles_") }
            .map { Double($0.numericValue) }
            .filter { $0 > 0 }
            .sorted()
    }

    static func next(after miles: Double, thresholds: [Double] = []) -> Double {
        let ladder = thresholds.isEmpty ? seedLadder : thresholds
        if let rung = ladder.first(where: { $0 > miles }) { return rung }
        let top = ladder.last ?? 0
        let step: Double = 500
        return max(top, floor(miles / step) * step) + step
    }
}

// MARK: - Hero layout

/// Banner + top bar, with the avatar (in its goal ring) hanging
/// off the banner's bottom edge. The space the hanging ring needs is RESERVED
/// with padding rather than drawn with an offset, so whatever the caller puts
/// underneath lays out against the real bounds.
struct ProfileHero<Avatar: View, TopBar: View>: View {
    let bannerURL: String?
    let bannerStyle: ProfileBannerStyle
    var bannerLocalImage: UIImage? = nil
    /// Retained for API compatibility; the banner no longer draws a chip.
    let totalMiles: Double?
    /// Retained for API compatibility (see `MileMilestones`).
    var milestoneThresholds: [Double] = []
    let goalProgress: Double?
    let goalComplete: Bool
    /// A streak token is carrying today — the ring and its chip say so
    /// instead of drawing an untouched day beside a streak that just grew.
    var goalSavedToday: CoveredDate? = nil
    /// Extra banner height above the top bar — the status bar when the banner
    /// runs under it (own profile). Zero when a navigation bar sits above.
    var topInset: CGFloat = 0
    var bannerHeight: CGFloat = 150
    var avatarSize: CGFloat = 88
    var onTapAvatar: (() -> Void)? = nil
    @ViewBuilder let avatar: () -> Avatar
    @ViewBuilder let topBar: () -> TopBar

    private let gutter = MADTheme.Spacing.screenGutter
    /// Room under the banner for the hanging half of the ring, plus a little
    /// air before the identity block.
    private var hang: CGFloat { GoalRingAvatar<Avatar>.ringDiameter(size: avatarSize) / 2 }
    private let labelReserve: CGFloat = 6

    /// What the ring shows, for VoiceOver (the ring has no text of its own).
    private var goalAccessibilityValue: String {
        if goalComplete { return "Today's goal done" }
        if goalSavedToday != nil { return "Today is saved by a streak token" }
        if let goalProgress {
            let percent = Int((max(0, min(1, goalProgress)) * 100).rounded(.down))
            return "\(percent) percent of today's goal"
        }
        return ""
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ProfileBannerView(imageURL: bannerURL, style: bannerStyle, localImage: bannerLocalImage)
                .frame(height: bannerHeight + topInset)
                .frame(maxWidth: .infinity)
            topBar()
                .padding(.horizontal, gutter)
                .padding(.top, topInset + 10)
        }
        // No milestone chip on the banner: lifetime miles reads on the Miles
        // tile and the Total Miles screen's Next Medal. `totalMiles` /
        // `milestoneThresholds` stay in the API so callers keep compiling.
        .padding(.bottom, hang + labelReserve)
        .overlay(alignment: .bottomLeading) {
            Button {
                onTapAvatar?()
            } label: {
                GoalRingAvatar(
                    progress: goalProgress,
                    isComplete: goalComplete,
                    savedToday: goalSavedToday != nil,
                    size: avatarSize
                ) {
                    avatar()
                }
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile photo")
            .accessibilityValue(goalAccessibilityValue)
            .allowsHitTesting(onTapAvatar != nil)
            .padding(.leading, gutter)
            .padding(.bottom, labelReserve)
        }
    }
}

// MARK: - Identity

/// "@rob  Rob Wiscount" with the Pure Flame seal, then the bio.
struct ProfileIdentityBlock: View {
    let username: String?
    let displayName: String?
    let bio: String?
    var showsPureFlame: Bool = false
    var onPureFlame: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            MADInlineStack(spacing: 8) {
                if let username, !username.isEmpty {
                    Text("@\(username)")
                        .madFont(size: 22, weight: .black, design: .rounded)
                        .foregroundColor(.white)
                        .madNameLines()
                } else if let displayName, !displayName.isEmpty {
                    Text(displayName)
                        .madFont(size: 22, weight: .black, design: .rounded)
                        .foregroundColor(.white)
                        .madNameLines()
                }
                if showsPureFlame {
                    Button {
                        onPureFlame?()
                    } label: {
                        PureFlameBadge(size: 20)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Pure Flame badge")
                }
                if let username, !username.isEmpty,
                   let displayName, !displayName.isEmpty, displayName != username {
                    Text(displayName)
                        .madFont(size: 13, weight: .semibold, design: .rounded)
                        .foregroundColor(.white.opacity(0.55))
                        .madNameLines()
                }
            }
            if let bio, !bio.isEmpty {
                Text(bio)
                    .madFont(size: 14, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Stat tiles

/// Streak · Miles · Friends as three flat tiles. They don't restate today:
/// the goal ring above owns "done today" (a green tile with a check, and a
/// blue saved tile, used to say it again). Friends opens an A–Z list.
struct ProfileStatTiles<FriendsDestination: View>: View {
    let streak: Int
    let totalMiles: Double
    /// nil renders a placeholder dash until the count loads.
    let friendCount: Int?
    /// When set, the Miles tile is a button (own profile → Total Miles
    /// detail). Nil keeps it a plain tile, as on a friend's profile.
    var onTapMiles: (() -> Void)? = nil
    @ViewBuilder var friendsDestination: () -> FriendsDestination

    var body: some View {
        HStack(spacing: 10) {
            tile(label: "Streak", value: "\(streak)", labelColor: MADTheme.Colors.madRed)
            if let onTapMiles {
                Button {
                    MADHaptics.tap()
                    onTapMiles()
                } label: {
                    tile(label: DistanceUnits.current.plural.capitalized, value: milesText, chevron: true)
                }
                .buttonStyle(.plain)
            } else {
                tile(label: DistanceUnits.current.plural.capitalized, value: milesText)
            }
            NavigationLink(destination: friendsDestination()) {
                tile(
                    label: friendCount == 1 ? "Friend" : "Friends",
                    value: friendCount.map { $0.formatted(.number.grouping(.automatic)) } ?? "—",
                    chevron: true
                )
            }
            .buttonStyle(.plain)
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeInOut(duration: 0.2), value: friendCount)
    }

    private func tile(
        label: String,
        value: String,
        labelColor: Color = .white.opacity(0.55),
        chevron: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .madFont(size: 12, weight: .semibold, design: .rounded)
                .foregroundColor(labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 4) {
                Text(value)
                    .madFont(size: 24, weight: .black, design: .rounded)
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if chevron {
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .madFont(size: 10, weight: .bold, maxScale: 1.5)
                        .foregroundColor(.white.opacity(0.35))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DashboardCardSurface(style: .fun))
        .contentShape(Rectangle())
    }

    private var milesText: String {
        let shown = totalMiles.inDisplayUnit
        if shown >= 100 {
            return String(format: "%.0f", shown)
        }
        return String(format: "%.1f", shown)
    }
}

// MARK: - Tab bar

/// Underline tabs for the profile sections. Replaces the pill picker on the
/// two profile screens only — the rest of the app keeps `MADPillPicker`.
struct ProfileTabBar<Tag: Hashable>: View {
    struct Item: Identifiable {
        let id: Tag
        let title: String

        init(id: Tag, title: String) {
            self.id = id
            self.title = title
        }
    }

    @Binding var selection: Tag
    let items: [Item]
    /// Shares the width between the tabs, each a full-height target, when the
    /// bar is a page's own header (the Duo's right page), not a row in a list.
    var fillsWidth = false

    @Namespace private var underline

    var body: some View {
        HStack(alignment: .bottom, spacing: 22) {
            ForEach(items) { item in
                let selected = selection == item.id
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selection = item.id
                    }
                } label: {
                    VStack(spacing: 8) {
                        Text(item.title)
                            .madFont(size: 15, weight: .heavy, design: .rounded, maxScale: 1.35)
                            .foregroundColor(selected ? .white : .white.opacity(0.45))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        ZStack {
                            Capsule()
                                .fill(Color.clear)
                                .frame(height: 3)
                            if selected {
                                Capsule()
                                    .fill(MADTheme.Colors.madRed)
                                    .frame(height: 3)
                                    .matchedGeometryEffect(id: "underline", in: underline)
                            }
                        }
                    }
                    .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: fillsWidth ? 48 : nil, alignment: .bottom)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }
}

// MARK: - Activity-tab card chrome

/// The flat card every profile block sits on: the Dashboard's one surface
/// (`DashboardCardSurface`, rimless, one radius), so a profile and the home
/// screen read as one app. Colour lives in the content, never the chrome.
struct ProfileCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.background(DashboardCardSurface(style: .fun))
    }
}

extension View {
    func profileCard() -> some View { modifier(ProfileCardStyle()) }
}

/// The sentence-case label at the top of every profile card ("Last 7 days",
/// "Hall of Streaks", "Recent workouts"…). Callers pass sentence case; no
/// tracked capitals.
struct ProfileCardLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .madFont(size: 13, weight: .semibold, design: .rounded)
            .foregroundColor(.white.opacity(0.6))
    }
}

// MARK: - Stats tab

/// One number on the Stats tab's performance card.
struct ProfileStat: Identifiable {
    let label: String
    let value: String
    var unit: String? = nil
    /// Opens the detail screen behind this number (own profile only).
    var action: (() -> Void)? = nil

    var id: String { label }

    // The SAME three numbers on both profiles, built the same way, so your
    // own Stats tab and a friend's can't drift apart again.

    /// Fastest mile, `pace` in minutes per mile (0 = none yet).
    static func bestPace(_ pace: TimeInterval, action: (() -> Void)? = nil) -> ProfileStat {
        guard pace > 0 else { return ProfileStat(label: "Best pace", value: "—", action: action) }
        let shown = pace / DistanceUnits.current.perMile
        let minutes = Int(shown)
        let seconds = min(59, Int(((shown - Double(minutes)) * 60).rounded()))
        return ProfileStat(
            label: "Best pace",
            value: String(format: "%d:%02d", minutes, seconds),
            unit: DistanceUnits.current.paceSuffix,
            action: action
        )
    }

    /// Most miles in one day.
    static func bestDay(_ miles: Double, action: (() -> Void)? = nil) -> ProfileStat {
        ProfileStat(
            label: "Best day",
            value: String(format: "%.1f", miles.inDisplayUnit),
            unit: DistanceUnits.current.abbreviation,
            action: action
        )
    }

    /// Mean over the last seven days, zero days included (`nil` = not known).
    static func sevenDayAverage(_ days: [FriendDayMiles]?) -> ProfileStat {
        guard let days, !days.isEmpty else { return ProfileStat(label: "7-day avg", value: "—") }
        let average = days.reduce(0) { $0 + $1.miles } / Double(days.count)
        return ProfileStat(
            label: "7-day avg",
            value: String(format: "%.1f", average.inDisplayUnit),
            unit: DistanceUnits.current.abbreviation
        )
    }
}

/// The Stats tab's performance card, shared by your own profile and a
/// friend's so both show the same numbers the same way: plain values on the
/// one flat profile card, no icons, no tinted tiles.
struct ProfileStatsCard: View {
    let stats: [ProfileStat]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileCardLabel(text: "Performance")
            HStack(alignment: .top, spacing: 12) {
                ForEach(stats) { stat in
                    if let action = stat.action {
                        Button {
                            MADHaptics.tap()
                            action()
                        } label: {
                            cell(stat, tappable: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        cell(stat, tappable: false)
                    }
                }
            }
        }
        .padding(DashboardCardSurface.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .profileCard()
    }

    private func cell(_ stat: ProfileStat, tappable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(stat.value)
                    .madFont(size: 22, weight: .black, design: .rounded)
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .layoutPriority(1)
                if let unit = stat.unit {
                    Text(unit)
                        .madFont(size: 12, weight: .semibold, design: .rounded)
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            HStack(spacing: 3) {
                Text(stat.label)
                    .madFont(size: 12, weight: .semibold, design: .rounded)
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if tappable {
                    Image(systemName: "chevron.right")
                        .madFont(size: 9, weight: .bold, maxScale: 1.5)
                        .foregroundColor(.white.opacity(0.35))
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
