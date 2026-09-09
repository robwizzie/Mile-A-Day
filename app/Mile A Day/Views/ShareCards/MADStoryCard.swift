import SwiftUI
import CoreLocation

// MARK: - Story share canvas
//
// The app's other share images are 4:5 and 2:3. An Instagram Story is 9:16, so
// every one of them lands letterboxed with about a third of the screen as empty
// bar — which is most of why a good share card still doesn't get posted. This is
// the one canvas built for that shape.
//
// TWO AXES, and keeping them apart is the whole point. `MADStoryDesign` is WHAT
// the card shows (the photo, the route, the streak). `MADStoryFormat` is WHAT
// SHAPE it arrives in (a full story frame, or a sticker to drop on one). They
// used to be one four-way picker — Photo | Route | Streak | Sticker — which
// asked two different questions in one control and so could not be learned:
// picking "Sticker" silently threw away the design you had chosen, and picking
// a design silently threw away the sticker. Every design now renders in both
// formats off the same layout, so the two choices are independent and neither
// one destroys the other.
//
// Three rules hold on every card:
//   * ONE brand lockup, bottom-left, and it carries mileaday.run. There used to
//     be a second one at the top of every frame — the same logo and wordmark
//     twice on one card, which is the thing that made these read as unfinished.
//     A story link isn't tappable for most accounts, so the URL baked into the
//     picture is the only route from a screenshot back to the app.
//   * The STREAK rides along wherever we have one. It is the number Strava
//     structurally cannot show, and the one most likely to make a viewer ask
//     what app this is.
//   * Distances go through `DistanceUnits`, never a hardcoded "MI". A card is a
//     surface the user reads, and it was the one place still printing miles at
//     someone who set the app to kilometres.
//   * Colours come from `MADTheme` tokens and the flame is the app's OWN — the
//     Modern dashboard's `ProfessionalFlameView` or Fun's `FlameBuddyView`,
//     picked by `DashboardStylePreference`, so the card looks like the app the
//     user actually opens. Hand-mixed near-copies of either drift, and this
//     file had already drifted: a bespoke orange `flame.fill` belonging to
//     neither style, over a ground a shade darker than the real token.

/// What the card shows.
enum MADStoryDesign: String, CaseIterable, Identifiable {
    case photo, route, streak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: return "Photo"
        case .route: return "Route"
        case .streak: return "Streak"
        }
    }

    var icon: String {
        switch self {
        case .photo: return "photo"
        case .route: return "point.topleft.down.curvedto.point.bottomright.up"
        case .streak: return "flame.fill"
        }
    }
}

/// What shape it arrives in.
enum MADStoryFormat: String, CaseIterable, Identifiable {
    /// The full 9:16 frame. One tap in Instagram and the story is finished.
    case story
    /// A card with transparent surround, dropped draggable onto a story the
    /// walker was already making.
    case sticker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .story: return "Full screen"
        case .sticker: return "Sticker"
        }
    }

    var icon: String {
        switch self {
        case .story: return "rectangle.portrait.fill"
        case .sticker: return "square.on.square"
        }
    }

    /// Rendered at scale 3, so the story frame lands at exactly the 1080×1920
    /// Instagram wants and the sticker at 960×1200.
    var size: CGSize {
        switch self {
        case .story: return CGSize(width: 360, height: 640)
        case .sticker: return CGSize(width: 320, height: 400)
        }
    }

    var isTransparent: Bool { self == .sticker }

    var margin: CGFloat { self == .story ? 28 : 22 }

    var cornerRadius: CGFloat { self == .story ? 0 : 30 }

    /// A sticker is narrow enough that a third column squeezes every value.
    var maxStats: Int { self == .story ? 3 : 2 }
}

/// Everything a card can draw. Built by the caller from whatever it has — every
/// field is optional, and a design simply omits what it wasn't given rather
/// than printing a zero.
struct MADStoryContent: Identifiable {
    let id = UUID()
    var distanceMiles: Double?
    var paceSecondsPerMile: Double?
    var durationSeconds: Double?
    var streak: Int?
    var totalMiles: Double?
    /// "Walk" / "Run", for the kicker line above the distance.
    var activityName: String?
    /// When the walk happened — drives `RouteArtView`'s time-of-day cast.
    var date: Date?
    /// Already-formatted date, for callers holding the server's string rather
    /// than a Date (`PostStats.date`). Preferred over formatting `date`.
    var dateText: String?
    var coordinates: [CLLocationCoordinate2D] = []
    var routeColor: Color = MADTheme.Colors.madRed
    var photo: UIImage?
    var avatar: RouteArtAvatar?

    var hasRoute: Bool { coordinates.count >= 2 }
    var hasPhoto: Bool { photo != nil }

    /// Which designs this walk can actually draw. Never offer Route for an
    /// indoor walk — an empty canvas reads as the feature being broken.
    var availableDesigns: [MADStoryDesign] {
        var out: [MADStoryDesign] = []
        if hasPhoto { out.append(.photo) }
        if hasRoute { out.append(.route) }
        if (streak ?? 0) > 0 { out.append(.streak) }
        // Never empty: a walk with no photo, no route and no streak still has a
        // distance, and the streak design degrades to that rather than leaving
        // the sheet with nothing to select.
        return out.isEmpty ? [.streak] : out
    }

    /// Photo first when there is one: a face gets engagement, a map doesn't,
    /// and the whole point is that this actually gets posted.
    var defaultDesign: MADStoryDesign { availableDesigns.first ?? .streak }
}

// MARK: - The card

struct MADStoryCard: View {
    let content: MADStoryContent
    let design: MADStoryDesign
    var format: MADStoryFormat = .story

    var body: some View {
        ZStack {
            backdrop
            layout
        }
        .frame(width: format.size.width, height: format.size.height)
        .clipShape(RoundedRectangle(cornerRadius: format.cornerRadius, style: .continuous))
        .overlay {
            if format == .sticker {
                RoundedRectangle(cornerRadius: format.cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1.5)
            }
        }
    }

    // MARK: Ground

    private var backdrop: some View {
        ZStack {
            // The app's OWN ground, straight from the token — not a copy of its
            // stops. This was hand-written here and had already drifted a shade
            // darker at the bottom, which is exactly how a share card stops
            // looking like the app it came from.
            MADTheme.Colors.appBackgroundGradient
            RadialGradient(
                colors: [glowColor.opacity(0.36), glowColor.opacity(0.08), .clear],
                center: UnitPoint(x: 0.82, y: 0.08),
                startRadius: 8, endRadius: format.size.height * 0.55
            )
            if design == .photo, let photo = content.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: format.size.width, height: format.size.height)
                    .clipped()
                photoScrim
            }
        }
    }

    /// The stats sit over the lower third, so it has to be readable whatever the
    /// photo is doing down there — and the fade has to start well above them or
    /// the top of a 78pt number lands on daylight.
    private var photoScrim: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.42), location: 0.00),
                .init(color: .black.opacity(0.00), location: 0.26),
                .init(color: .black.opacity(0.10), location: 0.38),
                .init(color: .black.opacity(0.62), location: 0.62),
                .init(color: .black.opacity(0.90), location: 0.82),
                .init(color: .black.opacity(0.96), location: 1.00),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var glowColor: Color {
        design == .streak ? MADTheme.Colors.warning : content.routeColor
    }

    // MARK: Layout
    //
    // One skeleton for all three designs: slack at the top, the art, a CAPPED
    // gap, then the bottom block over the lockup. The cap is what stops the
    // streak design — which has less art than the others — from opening a hole
    // in the middle of the card, which is what a plain pair of Spacers did.

    private var layout: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            artZone
            Spacer(minLength: 0)
                .frame(maxHeight: format == .story ? 34 : 20)
            VStack(alignment: .leading, spacing: 0) {
                bottomBlock
                footer
            }
            .padding(.horizontal, format.margin)
            .padding(.bottom, format.margin)
        }
    }

    @ViewBuilder
    private var artZone: some View {
        switch design {
        case .photo:
            // The photo IS the art; it's full-bleed in the backdrop.
            EmptyView()
        case .route:
            RouteArtView.still(
                coordinates: content.coordinates,
                routeColor: content.routeColor,
                authorAvatar: content.avatar,
                showsMileMarkers: format == .story,
                paletteDate: content.date,
                size: routeArtSize
            )
            .frame(width: routeArtSize.width, height: routeArtSize.height)
        case .streak:
            streakBlock
        }
    }

    private var routeArtSize: CGSize {
        format == .story
            ? CGSize(width: 360, height: 340)
            : CGSize(width: 320, height: 196)
    }

    @ViewBuilder
    private var bottomBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The streak design already carries its headline number up in the
            // art zone, so repeating a distance hero under it would give the
            // card two competing subjects.
            if design != .streak {
                if let kicker {
                    Text(kicker)
                        .font(.system(size: format == .story ? 11.5 : 10,
                                      weight: .black, design: .rounded))
                        .tracking(2.4)
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                        .padding(.bottom, 10)
                }
                heroRow
            }
            if !stats.isEmpty {
                statRail
                    .padding(.top, design == .streak ? 0 : (format == .story ? 18 : 14))
            }
        }
    }

    private var heroRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(heroValue)
                .font(.system(size: format == .story ? 78 : 58,
                              weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
            Text(DistanceUnits.current.abbreviation.uppercased())
                .font(.system(size: format == .story ? 20 : 16,
                              weight: .black, design: .rounded))
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.5))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.55)
    }

    private var streakBlock: some View {
        VStack(spacing: 0) {
            heroFlame
                .frame(width: flameSize, height: flameSize)
                .accessibilityHidden(true)

            Text("\(content.streak ?? 0)")
                .font(.system(size: format == .story ? 116 : 84,
                              weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.top, format == .story ? 4 : 2)

            Text("DAY STREAK")
                .font(.system(size: format == .story ? 13 : 11,
                              weight: .black, design: .rounded))
                .tracking(format == .story ? 4.5 : 3.6)
                .foregroundColor(MADTheme.Colors.warning)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, format.margin)
    }

    private var flameSize: CGFloat { format == .story ? 150 : 106 }

    /// The SAME flame the user's own dashboard draws, so the card they share
    /// looks like the app they opened.
    ///
    /// It was an SF Symbol `flame.fill` under a hand-mixed orange gradient —
    /// which is neither of the app's two flames and belongs to neither style.
    ///
    /// Both get `still: true`. A card is baked by `ImageRenderer`, which drives
    /// no view lifecycle, so the flame's 12 fps flicker/blink would be
    /// snapshotted wherever it happened to land — Flamey mid-blink, baked into
    /// a picture somebody posts. It has to be a parameter: Reduce Motion, which
    /// the flames already branch on, is a READ-ONLY environment value and
    /// cannot be forced from a caller.
    @ViewBuilder
    private var heroFlame: some View {
        switch DashboardStylePreference.current {
        case .fun:
            // Flamey himself, face and all. No `mood`: the hero's props and
            // speech bubble are dressing for a live dashboard, and a bubble
            // baked into a shared picture reads as a caption nobody wrote.
            FlameBuddyView(health: .blazing, size: flameSize,
                           phase: .blazing, coalWarmth: 1, still: true)
        case .modern:
            // The Modern dashboard's own flame: the same figure with no face,
            // ungrounded so it stays framed. `.blazing` also means no countdown
            // ring — a still has no countdown to draw.
            ProfessionalFlameView(phase: .blazing, health: .blazing,
                                  size: flameSize, coalWarmth: 1, still: true)
        }
    }

    /// Equal columns under one hairline, split by hairlines. An `HStack` with
    /// fixed spacing let the columns drift with their content, which is what
    /// made the old stat row read as three loose labels rather than a rail.
    private var statRail: some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.element.label) { index, stat in
                if index > 0 {
                    // An explicit height, not a flexible one: a `Rectangle` with
                    // only a width has no ideal height, and the enclosing
                    // `fixedSize(vertical:)` then has nothing to measure it by.
                    Rectangle()
                        .fill(Color.white.opacity(0.13))
                        .frame(width: 1, height: format == .story ? 36 : 31)
                        .padding(.trailing, 14)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(stat.value)
                        .font(.system(size: format == .story ? 21 : 18,
                                      weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(stat.tint)
                    Text(stat.label)
                        .font(.system(size: format == .story ? 10 : 9,
                                      weight: .black, design: .rounded))
                        .tracking(1.7)
                        .foregroundColor(.white.opacity(0.4))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 14)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.13))
                .frame(height: 1)
        }
    }

    /// The download driver, and the card's only brand lockup.
    private var footer: some View {
        HStack(spacing: 0) {
            MADLogoMark(size: format == .story ? 22 : 19, shadow: false)
            Text("MILE A DAY")
                .font(.system(size: format == .story ? 11.5 : 10,
                              weight: .black, design: .rounded))
                .tracking(2)
                .foregroundColor(.white)
                .padding(.leading, 8)
            Spacer(minLength: 8)
            Text("mileaday.run")
                .font(.system(size: format == .story ? 12 : 10.5,
                              weight: .heavy, design: .rounded))
                .foregroundColor(.white.opacity(0.45))
        }
        .lineLimit(1)
        .padding(.top, format == .story ? 20 : 16)
    }

    // MARK: Values

    private var heroValue: String {
        (content.distanceMiles ?? 0).distanceText
    }

    private var kicker: String? {
        let parts = [displayDate, content.activityName?.uppercased()].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Capped at the format's column count, so a sticker never squeezes three
    /// values into 320pt.
    private var stats: [MADStoryStat] {
        Array(allStats.prefix(format.maxStats))
    }

    private var allStats: [MADStoryStat] {
        var out: [MADStoryStat] = []
        switch design {
        case .photo, .route:
            if let pace = content.paceSecondsPerMile, pace > 0 {
                out.append(MADStoryStat(value: paceText(pace), label: "PACE"))
            }
            if let duration = content.durationSeconds, duration > 0 {
                out.append(MADStoryStat(value: RunStatsStickerView.durationText(duration),
                                        label: "TIME"))
            }
            if let streak = content.streak, streak > 0 {
                out.append(MADStoryStat(value: "\(streak)", label: "STREAK",
                                        tint: MADTheme.Colors.warning))
            }
        case .streak:
            if let distance = content.distanceMiles, distance > 0 {
                out.append(MADStoryStat(value: distance.distanceText, label: "TODAY"))
            }
            if let pace = content.paceSecondsPerMile, pace > 0 {
                out.append(MADStoryStat(value: paceText(pace), label: "PACE"))
            }
            if let total = content.totalMiles, total > 0 {
                // Lifetime totals are whole units — two decimals on a four-digit
                // number is false precision and it blows the column's width.
                out.append(MADStoryStat(value: "\(Int(total.inDisplayUnit))", label: "TOTAL"))
            }
        }
        return out
    }

    /// Pace is stored per MILE and shown per display unit, like everywhere else.
    private func paceText(_ secondsPerMile: Double) -> String {
        RunStatsStickerView.paceText(secondsPerMile.pacePerDisplayUnit)
    }

    private var displayDate: String? {
        if let text = content.dateText, !text.isEmpty { return text.uppercased() }
        if let date = content.date { return Self.dateFormatter.string(from: date).uppercased() }
        return nil
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

/// One column of the stat rail.
struct MADStoryStat {
    let value: String
    let label: String
    var tint: Color = .white
}

// MARK: - Rendering

extension MADStoryCard {
    /// The image handed to Instagram (or the share sheet).
    ///
    /// Scale 3 over the design size. Opaque for the story frame and transparent
    /// for the sticker — a sticker with a black rectangle behind it is not a
    /// sticker.
    @MainActor
    static func render(content: MADStoryContent,
                       design: MADStoryDesign,
                       format: MADStoryFormat) -> UIImage? {
        let renderer = ImageRenderer(
            content: MADStoryCard(content: content, design: design, format: format)
        )
        renderer.scale = 3.0
        renderer.isOpaque = !format.isTransparent
        return renderer.uiImage
    }
}

// MARK: - Goal celebration

extension GoalCompletionStats {
    /// This DAY, as a story card.
    ///
    /// One construction shared by all three goal celebrations (classic, Modern,
    /// Fun) rather than three copies — the two dashboard heroes forked their
    /// stat line exactly this way and drifted.
    ///
    /// Deliberately no route: a goal celebration is about the day, which can be
    /// several walks, and pinning one walk's line under the day's rollup is the
    /// mismatch `dayRollupStats` exists to avoid. That leaves the Streak design,
    /// which is the one this moment wants anyway.
    ///
    /// This extension lives HERE and not in CelebrationManager.swift, which is
    /// a Watch target member: a dependency added there compiles on iPhone and
    /// fails the Watch with "Cannot find 'MADStoryContent' in scope".
    var storyContent: MADStoryContent {
        MADStoryContent(
            distanceMiles: todaysDistance,
            // `todaysAveragePace` is MINUTES per mile; every consumer that
            // wants seconds multiplies by 60 (RunPostService, SocialFeedView).
            paceSecondsPerMile: todaysAveragePace.map { $0 * 60 },
            durationSeconds: todaysTotalDuration > 0 ? todaysTotalDuration : nil,
            streak: currentStreak,
            totalMiles: totalLifetimeMiles,
            date: Date()
        )
    }
}
