import SwiftUI
import UIKit

// MARK: - Share templates
//
// The Share Studio is a CAROUSEL of finished cards, one page per template, so
// the walker sees exactly what will post before they tap anything — the thing
// Strava's share flow and Duolingo's streak card both get right, and the old
// studio did not (two rows of controls over one preview, and you had to build
// the card in your head from the labels).
//
// A template is a WHOLE card design. It belongs to a FAMILY (Picture / Route /
// Streak / Flamey / Stats / Week) that the chip row above the carousel jumps
// between, and it declares which SHAPES it can arrive in. The shape (full
// story vs transparent sticker) is still its own axis — `MADStoryFormat` —
// but only offered where a template genuinely renders both; asking the
// question on a card that has one answer is how the old four-way picker
// taught nobody anything.
//
// Only templates whose data exists are offered (`ShareTemplate.available`):
// no photo ⇒ no Picture pages, no route (or a stealth walk, whose route never
// reaches this struct) ⇒ no Route pages. A walk always has Flamey and Stats,
// and Streak whenever there is one — never gate a share on a route.

enum ShareTemplateFamily: String, CaseIterable, Identifiable {
    case picture, route, streak, flamey, stats, week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .picture: return "Picture"
        case .route: return "Route"
        case .streak: return "Streak"
        case .flamey: return "Flamey"
        case .stats: return "Sticker"
        case .week: return "Week"
        }
    }

    var icon: String {
        switch self {
        case .picture: return "photo"
        case .route: return "point.topleft.down.curvedto.point.bottomright.up"
        case .streak: return "flame.fill"
        case .flamey: return "face.smiling"
        case .stats: return "square.on.square"
        case .week: return "calendar"
        }
    }

    /// The telemetry key recorded when a card from this family is actually
    /// shared. A FIXED set (backend `TRACKED_FEATURES`) — never a template id
    /// interpolated into a string, which would make the allowlist a free-text
    /// sink one new template at a time.
    var telemetryKey: String {
        switch self {
        case .picture: return ShareTelemetry.familyPicture
        case .route: return ShareTelemetry.familyRoute
        case .streak: return ShareTelemetry.familyStreak
        case .flamey: return ShareTelemetry.familyFlamey
        case .stats: return ShareTelemetry.familyStats
        case .week: return ShareTelemetry.familyWeek
        }
    }
}

enum ShareTemplate: String, CaseIterable, Identifiable {
    // Picture
    case photoFrame, photoPolaroid, photoBigNumber
    // Route
    case routeArt, routeMap, routeRail
    // Streak
    case streakFlame, streakBold, streakMilestone
    // Flamey
    case flameyMile, flameyStreak
    // Stats
    case statsSticker
    // Week
    case weekStory, weekFlamey

    var id: String { rawValue }

    var family: ShareTemplateFamily {
        switch self {
        case .photoFrame, .photoPolaroid, .photoBigNumber: return .picture
        case .routeArt, .routeMap, .routeRail: return .route
        case .streakFlame, .streakBold, .streakMilestone: return .streak
        case .flameyMile, .flameyStreak: return .flamey
        case .statsSticker: return .stats
        case .weekStory, .weekFlamey: return .week
        }
    }

    /// The name under the carousel. Plain words — what the card IS.
    var title: String {
        switch self {
        case .photoFrame: return "Framed photo"
        case .photoPolaroid: return "Polaroid"
        case .photoBigNumber: return "Big number"
        case .routeArt: return "Route art"
        case .routeMap: return "On the map"
        case .routeRail: return "Route & stats"
        case .streakFlame: return "Streak"
        case .streakBold: return "Bold streak"
        case .streakMilestone: return "Milestone"
        case .flameyMile: return "Flamey · Mile done"
        case .flameyStreak: return "Flamey · Still lit"
        case .statsSticker: return "Stats sticker"
        case .weekStory: return "Your week"
        case .weekFlamey: return "Flamey · Your week"
        }
    }

    /// The shapes this card can arrive in, preferred first.
    var formats: [MADStoryFormat] {
        switch self {
        case .photoFrame, .routeArt, .streakFlame, .weekStory: return [.story, .sticker]
        case .statsSticker: return [.sticker]
        default: return [.story]
        }
    }

    /// Does this card draw a stat rail the stat toggle can change?
    var usesStatToggle: Bool {
        switch self {
        case .streakMilestone, .flameyStreak, .weekStory, .weekFlamey, .streakBold, .photoPolaroid:
            return false
        default:
            return true
        }
    }

    /// The number a card leads with, which its rail therefore leaves out — a
    /// rail repeating the hero reads as the card stuttering.
    var heroStat: ShareStatKind? {
        switch self {
        case .photoFrame, .photoBigNumber, .routeArt, .routeRail: return .distance
        case .streakFlame: return .streak
        default: return nil
        }
    }

    /// Every template this content can actually draw, in carousel order.
    static func available(for content: MADStoryContent) -> [ShareTemplate] {
        if content.week != nil {
            return [.weekStory, .weekFlamey]
        }
        var out: [ShareTemplate] = []
        if content.hasPhoto { out += [.photoFrame, .photoPolaroid, .photoBigNumber] }
        if content.hasRoute { out += [.routeArt, .routeMap, .routeRail] }
        let streak = content.streak ?? 0
        if streak > 0 {
            if ShareMilestone.isMilestone(streak) { out.append(.streakMilestone) }
            out += [.streakFlame, .streakBold]
        }
        out.append(.flameyMile)
        if streak > 0 { out.append(.flameyStreak) }
        out.append(.statsSticker)
        return out
    }

    /// Where the carousel opens. The caller's choice wins when it's drawable;
    /// otherwise the photo (a face gets engagement), then the route, then the
    /// streak. A milestone day opens ON the milestone — that is the moment.
    static func preferred(_ requested: ShareTemplate?, in available: [ShareTemplate]) -> ShareTemplate {
        if let requested, available.contains(requested) { return requested }
        if let requested {
            // Same family, if the exact card isn't drawable (e.g. asked for
            // the milestone on a day that isn't one).
            if let sibling = available.first(where: { $0.family == requested.family }) { return sibling }
        }
        return available.first ?? .flameyMile
    }
}

/// A stat the rail can show. Values are always computed from MILES and
/// formatted through `DistanceUnits` / `pacePerDisplayUnit`.
enum ShareStatKind: String, CaseIterable, Identifiable {
    case distance, time, pace, streak, calories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .distance: return "Distance"
        case .time: return "Time"
        case .pace: return "Pace"
        case .streak: return "Streak"
        case .calories: return "Calories"
        }
    }

    /// The default rail, before the walker touches the toggle.
    static let defaultSelection: [ShareStatKind] = [.distance, .pace, .time, .streak]

    func stat(from content: MADStoryContent) -> MADStoryStat? {
        switch self {
        case .distance:
            guard let d = content.distanceMiles, d > 0 else { return nil }
            return MADStoryStat(value: d.distanceText, label: DistanceUnits.current.abbreviation.uppercased())
        case .time:
            guard let t = content.durationSeconds, t > 0 else { return nil }
            return MADStoryStat(value: RunStatsStickerView.durationText(t), label: "TIME")
        case .pace:
            guard let p = content.paceSecondsPerMile, p > 0 else { return nil }
            return MADStoryStat(value: RunStatsStickerView.paceText(p.pacePerDisplayUnit),
                                label: "PACE" + " " + DistanceUnits.current.paceSuffix.uppercased())
        case .streak:
            guard let s = content.streak, s > 0 else { return nil }
            return MADStoryStat(value: "\(s)", label: "STREAK", tint: MADTheme.Colors.warning)
        case .calories:
            guard let c = content.calories, c >= 1 else { return nil }
            return MADStoryStat(value: "\(Int(c.rounded()))", label: "KCAL")
        }
    }

    /// The kinds this content can actually fill — the toggle offers only these.
    static func available(in content: MADStoryContent) -> [ShareStatKind] {
        allCases.filter { $0.stat(from: content) != nil }
    }

    /// The rail for a card: the selection in canonical order, minus the
    /// card's hero, capped at what the shape fits.
    static func rail(_ selection: [ShareStatKind],
                     content: MADStoryContent,
                     hero: ShareStatKind?,
                     limit: Int) -> [MADStoryStat] {
        let chosen = Set(selection)
        return allCases
            .filter { chosen.contains($0) && $0 != hero }
            .compactMap { $0.stat(from: content) }
            .prefix(limit)
            .map { $0 }
    }
}

/// Streak-milestone copy for the share cards. Mirrors the day counts of the
/// app's `StreakMilestone` celebrations (read from it, never restated), so a
/// day the app celebrates is a day the studio opens on the milestone card.
enum ShareMilestone {
    static func isMilestone(_ streak: Int) -> Bool {
        StreakMilestone.allCases.contains { $0.days == streak }
            || (streak >= 100 && streak % 100 == 0)
    }

    static func headline(_ streak: Int) -> String {
        switch streak {
        case 7: return "One full week."
        case 14: return "Two weeks strong."
        case 21: return "Three weeks in."
        case 30: return "A whole month."
        case 100: return "Triple digits."
        case 365: return "One full year."
        case 730: return "Two full years."
        case 1000: return "A thousand days."
        default: return "\(streak) days strong."
        }
    }
}

// MARK: - The card, by template

/// Every template, drawn at its format's design size. What the carousel
/// previews (scaled) and what `ImageRenderer` bakes are the SAME view — the
/// preview is never an approximation of the export.
struct ShareCardView: View {
    let template: ShareTemplate
    let content: MADStoryContent
    var format: MADStoryFormat = .story
    var stats: [ShareStatKind] = ShareStatKind.defaultSelection

    var body: some View {
        Group {
            switch template {
            case .photoFrame:
                MADStoryCard(content: content, design: .photo, format: format, statKinds: stats)
            case .routeArt:
                MADStoryCard(content: content, design: .route, format: format, statKinds: stats)
            case .streakFlame:
                MADStoryCard(content: content, design: .streak, format: format, statKinds: stats)
            case .photoPolaroid:
                PolaroidShareCard(content: content)
            case .photoBigNumber:
                BigNumberPhotoShareCard(content: content, stats: stats)
            case .routeMap:
                MapRouteShareCard(content: content, stats: stats)
            case .routeRail:
                RouteRailShareCard(content: content, stats: stats)
            case .streakBold:
                BoldStreakShareCard(content: content)
            case .streakMilestone:
                MilestoneShareCard(content: content)
            case .flameyMile:
                FlameyMileShareCard(content: content, stats: stats)
            case .flameyStreak:
                FlameyStreakShareCard(content: content)
            case .statsSticker:
                StatsStickerShareCard(content: content, stats: stats)
            case .weekStory:
                WeekShareCard(content: content, format: format)
            case .weekFlamey:
                FlameyWeekShareCard(content: content)
            }
        }
        // A baked image must not change with the phone's text size — the
        // user's Dynamic Type setting would otherwise resize the card's type
        // inside a fixed 360×640 frame and push the lockup off the bottom.
        .dynamicTypeSize(.large)
        .environment(\.colorScheme, .dark)
    }

    /// The image handed to Instagram, Messages, Photos or the share sheet.
    /// Scale 3 over the design size: 1080×1920 for a story, 960×1200 for a
    /// sticker. Opaque for a story; transparent for a sticker, or it isn't one.
    @MainActor
    static func render(template: ShareTemplate,
                       content: MADStoryContent,
                       format: MADStoryFormat,
                       stats: [ShareStatKind]) -> UIImage? {
        let renderer = ImageRenderer(
            content: ShareCardView(template: template, content: content, format: format, stats: stats)
                .frame(width: format.size.width, height: format.size.height)
        )
        renderer.scale = 3.0
        renderer.isOpaque = !format.isTransparent
        return renderer.uiImage
    }
}
