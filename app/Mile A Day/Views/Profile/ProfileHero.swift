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

/// The round glass buttons that ride the banner (QR, edit, settings). Same
/// 38pt circle as `MADTabHeader`'s standard style, on a darker fill so they
/// hold up over a photo.
struct ProfileBannerButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// The small tracked wordmark in the banner's top-left corner.
struct ProfileWordmark: View {
    var body: some View {
        Text("MILE A DAY")
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(2.2)
            .foregroundColor(.white.opacity(0.85))
            .accessibilityHidden(true)
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
    /// Avatar diameter; the ring sits outside it.
    let size: CGFloat
    var ringWidth: CGFloat = 5
    var gap: CGFloat = 4
    @ViewBuilder let avatar: () -> Avatar

    static func ringDiameter(size: CGFloat, ringWidth: CGFloat = 5, gap: CGFloat = 4) -> CGFloat {
        size + 2 * gap + 2 * ringWidth
    }

    private var clamped: Double { isComplete ? 1 : max(0, min(1, progress ?? 0)) }

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
                    isComplete
                        ? AnyShapeStyle(Color.green)
                        : AnyShapeStyle(
                            AngularGradient(
                                colors: [Color.orange.opacity(0.55), .orange, Color.orange.opacity(0.85)],
                                center: .center,
                                startAngle: .degrees(0),
                                endAngle: .degrees(360)
                            )
                        ),
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
}

/// "88% TO GOAL" / "GOAL DONE" — the chip tucked under the ring. Nothing when
/// progress is unknown.
struct GoalRingLabel: View {
    let progress: Double?
    let isComplete: Bool

    var body: some View {
        if isComplete {
            chip("GOAL DONE", icon: "checkmark", color: .green)
        } else if let progress {
            let percent = Int((max(0, min(1, progress)) * 100).rounded(.down))
            chip("\(percent)% TO GOAL", icon: nil, color: .orange)
        }
    }

    private func chip(_ text: String, icon: String?, color: Color) -> some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .black))
            }
            Text(text)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(0.6)
                .monospacedDigit()
        }
        .foregroundColor(.black.opacity(0.88))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color))
        .overlay(Capsule().strokeBorder(Color.black.opacity(0.5), lineWidth: 1.5))
        .fixedSize()
    }
}

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

/// "NEXT TOTAL MILES MILESTONE · 1,000 mi · 192 to go", right-aligned in the banner.
struct NextMilestoneChip: View {
    let totalMiles: Double
    /// The catalog's mile rungs when loaded; empty falls back to the seed ladder.
    var thresholds: [Double] = []
    var alignment: HorizontalAlignment = .trailing

    private var target: Double { MileMilestones.next(after: totalMiles, thresholds: thresholds) }
    private var toGo: Int { max(1, Int((target - totalMiles).rounded(.up))) }

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            // Says MILES and MEDAL so it can't be read as the dashboard's
            // streak milestone — the two are different ladders on purpose.
            HStack(spacing: 4) {
                Image(systemName: "medal.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("NEXT TOTAL MILES MILESTONE")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(.white.opacity(0.7))
            HStack(spacing: 4) {
                Text("\(Int(target).formatted(.number.grouping(.automatic))) mi")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("·")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                Text("\(toGo.formatted(.number.grouping(.automatic))) to go")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.82))
            }
            .monospacedDigit()
        }
        .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Hero layout

/// Banner + top bar + milestone, with the avatar (in its goal ring) hanging
/// off the banner's bottom edge. The space the hanging ring needs is RESERVED
/// with padding rather than drawn with an offset, so whatever the caller puts
/// underneath lays out against the real bounds.
struct ProfileHero<Avatar: View, TopBar: View>: View {
    let bannerURL: String?
    let bannerStyle: ProfileBannerStyle
    var bannerLocalImage: UIImage? = nil
    /// nil = unknown (a profile whose stats aren't loaded or shared) → no chip.
    let totalMiles: Double?
    /// Mile-medal rungs from the badge catalog (see `MileMilestones`).
    var milestoneThresholds: [Double] = []
    let goalProgress: Double?
    let goalComplete: Bool
    /// Extra banner height above the top bar — the status bar when the banner
    /// runs under it (own profile). Zero when a navigation bar sits above.
    var topInset: CGFloat = 0
    var bannerHeight: CGFloat = 150
    var avatarSize: CGFloat = 88
    var onTapAvatar: (() -> Void)? = nil
    @ViewBuilder let avatar: () -> Avatar
    @ViewBuilder let topBar: () -> TopBar

    private let gutter = MADTheme.Spacing.screenGutter
    /// Room under the banner for the hanging half of the ring plus the label
    /// chip tucked under it.
    private var hang: CGFloat { GoalRingAvatar<Avatar>.ringDiameter(size: avatarSize) / 2 }
    private let labelReserve: CGFloat = 14

    var body: some View {
        ZStack(alignment: .topLeading) {
            ProfileBannerView(imageURL: bannerURL, style: bannerStyle, localImage: bannerLocalImage)
                .frame(height: bannerHeight + topInset)
                .frame(maxWidth: .infinity)
            topBar()
                .padding(.horizontal, gutter)
                .padding(.top, topInset + 10)
        }
        .overlay(alignment: .bottomTrailing) {
            if let totalMiles {
                NextMilestoneChip(totalMiles: totalMiles, thresholds: milestoneThresholds)
                    .padding(.trailing, gutter)
                    .padding(.bottom, 14)
            }
        }
        .padding(.bottom, hang + labelReserve)
        .overlay(alignment: .bottomLeading) {
            Button {
                onTapAvatar?()
            } label: {
                GoalRingAvatar(progress: goalProgress, isComplete: goalComplete, size: avatarSize) {
                    avatar()
                }
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(onTapAvatar != nil)
            .overlay(alignment: .bottom) {
                GoalRingLabel(progress: goalProgress, isComplete: goalComplete)
                    .offset(y: 8)
            }
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
            HStack(alignment: .center, spacing: 8) {
                if let username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else if let displayName, !displayName.isEmpty {
                    Text(displayName)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if showsPureFlame {
                    Button {
                        onPureFlame?()
                    } label: {
                        PureFlameBadge(size: 20)
                    }
                    .buttonStyle(.plain)
                }
                if let username, !username.isEmpty,
                   let displayName, !displayName.isEmpty, displayName != username {
                    Text(displayName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            if let bio, !bio.isEmpty {
                Text(bio)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Stat tiles

/// Streak · Miles · Friends as three tiles. Streak wears the brand red; the
/// other two stay neutral. Friends is tappable through to the friends list.
struct ProfileStatTiles<FriendsDestination: View>: View {
    let streak: Int
    let totalMiles: Double
    /// nil renders a placeholder dash until the count loads.
    let friendCount: Int?
    /// Today's mile is in: the streak tile turns green (the dashboard's
    /// done-colour) instead of the brand red it wears while the day is open.
    var streakDoneToday: Bool = false
    @ViewBuilder var friendsDestination: () -> FriendsDestination

    var body: some View {
        HStack(spacing: 10) {
            tile(
                label: "STREAK",
                value: "\(streak)",
                accent: streakDoneToday ? .green : MADTheme.Colors.madRed,
                trailingIcon: streakDoneToday ? "checkmark.circle.fill" : nil
            )
            tile(label: "MILES", value: milesText, accent: nil)
            NavigationLink(destination: friendsDestination()) {
                tile(
                    label: friendCount == 1 ? "FRIEND" : "FRIENDS",
                    value: friendCount.map { $0.formatted(.number.grouping(.automatic)) } ?? "—",
                    accent: nil,
                    chevron: true
                )
            }
            .buttonStyle(.plain)
        }
        .animation(.easeInOut(duration: 0.2), value: friendCount)
    }

    private func tile(
        label: String,
        value: String,
        accent: Color?,
        chevron: Bool = false,
        trailingIcon: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                if let trailingIcon {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .foregroundColor(accent ?? .white.opacity(0.55))
            HStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if chevron {
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent?.opacity(0.14) ?? Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(accent?.opacity(0.28) ?? Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
    }

    private var milesText: String {
        if totalMiles >= 100 {
            return String(format: "%.0f", totalMiles)
        }
        return String(format: "%.1f", totalMiles)
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
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundColor(selected ? .white : .white.opacity(0.45))
                            .lineLimit(1)
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

/// The flat card every Activity-tab block sits on — `Last7DaysChart`'s look,
/// shared so the tab reads as one set rather than a mix of glass and flat.
struct ProfileCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

extension View {
    func profileCard() -> some View { modifier(ProfileCardStyle()) }
}

/// The caps label at the top of every Activity-tab card ("LAST 7 DAYS",
/// "HALL OF STREAKS", "RECENT WORKOUTS"…).
struct ProfileCardLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(1.2)
            .foregroundColor(.white.opacity(0.5))
    }
}
