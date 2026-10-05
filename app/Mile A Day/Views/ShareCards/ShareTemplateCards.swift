import SwiftUI
import UIKit
import CoreLocation

// MARK: - Share template cards
//
// Every card here is baked by `ImageRenderer`, which drives NO view lifecycle,
// so the same rules hold on every one of them (ios.md, the sharing bullet):
//   * explicit sizes — a story is 360×640, a sticker 320×400, nothing flexes;
//   * no AsyncImage, no onAppear-driven state, no TimelineView, no `.blur()`:
//     anything asynchronous (the avatar, the photo wash, the map snapshot) is
//     resolved by the STUDIO and arrives on `MADStoryContent`;
//   * every animated figure takes `still: true` — Flamey mid-blink baked into
//     a picture somebody posts is the failure this prevents;
//   * ONE brand lockup, bottom-left, carrying mileaday.run (`ShareLockup`);
//   * distances through `DistanceUnits`, pace through `pacePerDisplayUnit`,
//     colours from `MADTheme` tokens.

// MARK: Shared parts

/// The card's only brand lockup — the download driver. A story link isn't
/// tappable for most accounts, so the URL in the picture is the route back.
struct ShareLockup: View {
    var format: MADStoryFormat = .story
    /// Extra words after the wordmark ("DAY 41") — used by the see-through
    /// stats sticker, which has no rail to carry the streak.
    var suffix: String? = nil
    var showsURL: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            MADLogoMark(size: format == .story ? 22 : 19, shadow: false)
            Text(suffix.map { "MILE A DAY · \($0)" } ?? "MILE A DAY")
                .font(.system(size: format == .story ? 11.5 : 10, weight: .black, design: .rounded))
                .tracking(2)
                .foregroundColor(.white)
                .padding(.leading, 8)
            if showsURL {
                Spacer(minLength: 8)
                Text("mileaday.run")
                    .font(.system(size: format == .story ? 12 : 10.5, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .lineLimit(1)
        .padding(.top, format == .story ? 20 : 16)
    }
}

/// Equal columns under one hairline, split by hairlines (the card rule: an
/// `HStack` with fixed spacing lets columns drift with their content).
struct ShareStatRail: View {
    let stats: [MADStoryStat]
    var format: MADStoryFormat = .story

    var body: some View {
        if stats.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 0) {
                ForEach(Array(stats.enumerated()), id: \.element.label) { index, stat in
                    if index > 0 {
                        // Explicit height: a width-only Rectangle has no ideal
                        // height for the `fixedSize(vertical:)` below to measure.
                        Rectangle()
                            .fill(Color.white.opacity(0.13))
                            .frame(width: 1, height: format == .story ? 36 : 31)
                            .padding(.trailing, 14)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(stat.value)
                            .font(.system(size: format == .story ? 21 : 18, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(stat.tint)
                        Text(stat.label)
                            .font(.system(size: format == .story ? 10 : 9, weight: .black, design: .rounded))
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
                Rectangle().fill(Color.white.opacity(0.13)).frame(height: 1)
            }
        }
    }
}

/// The flame the user's OWN dashboard draws: Modern ⇒ `ProfessionalFlameView`
/// (no face, ungrounded), Fun ⇒ `FlameBuddyView` (Flamey). Used by the
/// Streak family, which is about the number and so wears the app's own look.
/// The Flamey family always draws Flamey — he IS that card.
///
/// On Fun he wears his look, so he is FITTED (`ShareDressedFigure`): `size`
/// is the bare figure, and a look that reaches past it (wings, a companion,
/// a trail, a banner) shrinks him until the WHOLE outfit keeps inside
/// `maxWidth` × `maxHeight`. `hugsArt` makes the layout frame the outfit's
/// own width (a corner placement); otherwise it stays `size` wide, centred.
struct ShareStyleFlame: View {
    let size: CGFloat
    var maxWidth: CGFloat? = nil
    var maxHeight: CGFloat? = nil
    var hugsArt: Bool = false
    var headroom: CGFloat = ShareFlameyEnvelope.bareGlowAbove

    var body: some View {
        switch DashboardStylePreference.current {
        case .fun:
            // No `mood`: the hero's props and bubble are live-dashboard
            // dressing, and a bubble baked into a picture reads as a
            // caption nobody wrote.
            // His look (gear + today's outfit) — the SAME description the
            // hero draws, still-rendered.
            let look = FlameyFacts.look()
            ShareDressedFigure(envelope: ShareFlameyEnvelope(look: look), size: size,
                               maxWidth: maxWidth ?? size * 2, maxHeight: maxHeight ?? size * 1.3,
                               hugsArt: hugsArt, headroom: headroom) { d in
                FlameBuddyView(health: .blazing, size: d,
                               phase: .blazing, coalWarmth: 1, still: true,
                               look: look)
            }
            .accessibilityHidden(true)
        case .modern:
            ProfessionalFlameView(phase: .blazing, health: .blazing,
                                  size: size, coalWarmth: 1, still: true)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

/// Flamey, the character. The REAL `FlameBuddyView`, blazing and still, in a
/// mood that renders as a still — shades once the mile is banked, the party
/// hat on a milestone — and never with his speech bubble. FITTED to his
/// outfit like `ShareStyleFlame` (`ShareDressedFigure`).
///
/// `streakTag` hangs the day count on him as a tilted tag. It sits at his
/// lower right — unless a companion stands there, when it moves to his
/// lower left, and under his feet when both sides are taken.
struct ShareFlamey: View {
    let size: CGFloat
    var mood: FlameMood.Kind? = .done
    var streak: Int = 0
    /// Total drawn width the outfit may take, centred on the card.
    var maxWidth: CGFloat = 332
    /// Layout height the figure (headroom included) may take.
    var maxHeight: CGFloat? = nil
    var streakTag: Int? = nil

    var body: some View {
        // Wearing what he wears on the dashboard today; the look carries the
        // mood's shades / party hat.
        let look = FlameyFacts.look(mood: mood)
        let side = Self.tagSide(ShareFlameyEnvelope(look: look, mood: mood))
        ShareDressedFigure(envelope: envelope(look: look, tagSide: side), size: size, maxWidth: maxWidth,
                           maxHeight: maxHeight ?? size * 1.3,
                           accessory: streakTag.map { tag in
                               { (fit: ShareDressedFigure<FlameBuddyView>.Fit) in
                                   AnyView(Self.tag(tag, fit: fit, side: side))
                               }
                           }) { d in
            FlameBuddyView(health: .blazing, size: d,
                           phase: .blazing, coalWarmth: 1,
                           mood: mood.map { FlameMood(kind: $0, streak: streak) },
                           still: true, showsMoodBubble: false,
                           look: look)
        }
        // A tag under his feet takes room the headline would otherwise sit in.
        .padding(.bottom, streakTag != nil && side == 0 ? Self.tagDrop + 30 : 0)
        .accessibilityHidden(true)
    }

    /// The outfit's reach, plus a side tag's: the tag is part of the
    /// picture, so it is fitted inside the card with him rather than hung
    /// off an edge a shifted outfit has already reached.
    private func envelope(look: FlameyLook?, tagSide side: CGFloat) -> ShareFlameyEnvelope {
        var e = ShareFlameyEnvelope(look: look, mood: mood)
        guard streakTag != nil, side != 0 else { return e }
        let reach = 0.48 + Self.tagHalfWidth / size
        if side > 0 { e.right = max(e.right, reach) } else { e.left = min(e.left, -reach) }
        return e
    }

    /// Half the tag's drawn width (two digits, tilted), in points.
    private static let tagHalfWidth: CGFloat = 46

    private static func tag(_ value: Int, fit: ShareDressedFigure<FlameBuddyView>.Fit,
                            side: CGFloat) -> some View {
        let d = fit.figureSize
        return Text("\(value)")
            .font(.system(size: 40, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundColor(Color(red: 0.10, green: 0.05, blue: 0.06))
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(MADTheme.Colors.warning))
            .rotationEffect(.degrees(side == 0 ? -4 : 6 * side))
            .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 8)
            // Bare, this is where the tag always hung (34pt past the frame's
            // bottom corner, overlapping his hip); centred under his feet
            // when both sides are dressed.
            .position(x: fit.center.x + side * 0.48 * d,
                      y: fit.center.y + (side == 0 ? 0.5 * d + tagDrop : 0.34 * d))
    }

    /// +1 his lower right (where it always hung), −1 his lower left, 0 under
    /// his feet — in that order of preference, by which sides the outfit
    /// fills (a companion right, a trail or a held prop left, wings both).
    /// Read off the measured envelope, so a new item needs no list here.
    private static func tagSide(_ e: ShareFlameyEnvelope) -> CGFloat {
        let rightBusy = e.right > 0.62
        let leftBusy = e.left < -0.62
        return rightBusy ? (leftBusy ? 0 : -1) : 1
    }

    /// How far a tag under his feet hangs below his size square (its centre),
    /// and so how much room the card must leave under him for it.
    private static let tagDrop: CGFloat = 16
}

/// How far a dressed Flamey actually reaches, in units of his `size` from
/// the centre of his size square (y down) — MEASURED per item off the real
/// drawings at full reach (alpha > 25%, `FlameBuddyView` blazing + still),
/// not guessed. A look's reach is the union of its items'. Bare, his glow
/// already runs a little past the square; everything else is the outfit:
/// wings to ±0.92, a companion to +1.07 at his right foot, trails and held
/// props to −1.17 on his left, a banner or the paparazzi flashes to −1.07
/// above. An item missing here draws within the bare envelope — a NEW item
/// that reaches further needs a row, or a share card can clip it.
struct ShareFlameyEnvelope: Equatable {
    var left: CGFloat
    var right: CGFloat
    var top: CGFloat
    var bottom: CGFloat

    static let bare = Self(left: -0.45, right: 0.46, top: -0.69, bottom: 0.52)

    /// The bare glow's reach above the size square, in units of size: the
    /// part of the art that always overflowed the frame and still may.
    static var bareGlowAbove: CGFloat { -0.5 - bare.top }

    init(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) {
        self.left = left; self.right = right; self.top = top; self.bottom = bottom
    }

    /// `mood` is the mood his `FlameBuddyView` draws (its props rise
    /// above him even when a costume keeps the party hat off).
    init(look: FlameyLook?, mood: FlameMood.Kind? = nil) {
        self = .bare
        guard let look else { return }
        // Tops are kept apart from the shoes' own row: a hover lifts every
        // OTHER piece with his body, which the per-item rows can't see.
        var topAbove = Self.bare.top
        for item in look.items {
            guard let r = Self.reach(item) else { continue }
            left = min(left, r.left); right = max(right, r.right)
            bottom = max(bottom, r.bottom)
            if item.slot == .feet { top = min(top, r.top) } else { topAbove = min(topAbove, r.top) }
        }
        // The rest was measured on combinations: the party mood's props
        // crest like the party hat whatever he wears, and a companion mirrors
        // him (arms up); a cape steps the companion out and lays the trail
        // low and longer.
        let cape = look[.back].map(FlameyArt.isCape) ?? false
        if mood == .party {
            topAbove = min(topAbove, -0.85)
            if look[.companion] != nil { right += 0.08 }
        }
        if cape, look[.companion] != nil { right += 0.07 }
        if cape, look[.trail] != nil { left -= 0.03 }
        if look.hoverLift > 0, topAbove < Self.bare.top - 0.01 { topAbove -= look.hoverLift + 0.03 }
        top = min(top, topAbove)
    }

    // Generated from the measure pass (union per look, rounded outward).
    static func reach(_ item: FlameyItem) -> Self? {
        switch item {
        case .paparazzi:
            return Self(left: -0.83, right: 0.83, top: -1.07, bottom: 0.52)
        case .victoryBanner:
            return Self(left: -0.45, right: 0.64, top: -1.06, bottom: 0.52)
        case .partyHat, .headlampHelmet, .crown, .vikingHelmet, .bunnyEars, .countdownHat:
            return Self(left: -0.45, right: 0.46, top: -0.84, bottom: 0.52)
        case .ghostSheet:
            return Self(left: -0.47, right: 0.47, top: -0.83, bottom: 0.52)
        case .leprechaunHat, .starHat:
            return Self(left: -0.45, right: 0.46, top: -0.82, bottom: 0.52)
        case .rocketBoots:
            return Self(left: -0.45, right: 0.46, top: -0.82, bottom: 0.53)
        case .beanie:
            return Self(left: -0.45, right: 0.46, top: -0.81, bottom: 0.52)
        case .meteorShower:
            return Self(left: -1.05, right: 0.46, top: -0.80, bottom: 0.52)
        case .spectralGlow:
            return Self(left: -0.52, right: 0.52, top: -0.80, bottom: 0.52)
        case .santaHat, .heartBopper:
            return Self(left: -0.45, right: 0.46, top: -0.79, bottom: 0.52)
        case .wingedSandals:
            return Self(left: -0.45, right: 0.46, top: -0.78, bottom: 0.52)
        case .prism:
            return Self(left: -0.58, right: 0.58, top: -0.77, bottom: 0.53)
        case .eternal:
            return Self(left: -0.63, right: 0.70, top: -0.76, bottom: 0.52)
        case .cosmic:
            return Self(left: -0.58, right: 0.58, top: -0.76, bottom: 0.52)
        case .pumpkinSuit:
            return Self(left: -0.45, right: 0.46, top: -0.76, bottom: 0.52)
        case .nightcap, .cowboyHat:
            return Self(left: -0.45, right: 0.46, top: -0.75, bottom: 0.52)
        case .aviatorCap:
            return Self(left: -0.45, right: 0.46, top: -0.74, bottom: 0.52)
        case .safariHat, .directorsBeret:
            return Self(left: -0.45, right: 0.46, top: -0.73, bottom: 0.52)
        case .astronautHelmet:
            return Self(left: -0.52, right: 0.52, top: -0.72, bottom: 0.52)
        case .ballCap, .bucketHat:
            return Self(left: -0.45, right: 0.46, top: -0.72, bottom: 0.52)
        case .laurelWreath:
            return Self(left: -0.45, right: 0.46, top: -0.71, bottom: 0.52)
        case .megaphone:
            return Self(left: -1.17, right: 0.46, top: -0.69, bottom: 0.52)
        case .dustPuffs:
            return Self(left: -1.09, right: 0.46, top: -0.69, bottom: 0.53)
        case .checkeredFlag:
            return Self(left: -1.08, right: 0.46, top: -0.69, bottom: 0.52)
        case .confettiCannon, .smokeRings, .phoenixFeathers:
            return Self(left: -1.07, right: 0.46, top: -0.69, bottom: 0.52)
        case .rainbowStreak:
            return Self(left: -1.06, right: 0.46, top: -0.69, bottom: 0.52)
        case .lightningTrail, .fireworks:
            return Self(left: -1.05, right: 0.46, top: -0.69, bottom: 0.52)
        case .starTrail:
            return Self(left: -1.04, right: 0.46, top: -0.69, bottom: 0.52)
        case .auroraRibbon:
            return Self(left: -1.00, right: 0.46, top: -0.69, bottom: 0.52)
        case .emberSparks:
            return Self(left: -0.95, right: 0.46, top: -0.69, bottom: 0.52)
        case .goldenWings:
            return Self(left: -0.92, right: 0.92, top: -0.69, bottom: 0.52)
        case .speedLines:
            return Self(left: -0.92, right: 0.46, top: -0.69, bottom: 0.52)
        case .cometTail:
            return Self(left: -0.91, right: 0.46, top: -0.69, bottom: 0.52)
        case .spotlight:
            return Self(left: -0.74, right: 0.69, top: -0.69, bottom: 0.60)
        case .gold:
            return Self(left: -0.63, right: 0.70, top: -0.69, bottom: 0.52)
        case .stopwatch:
            return Self(left: -0.61, right: 0.46, top: -0.69, bottom: 0.52)
        case .pomPoms:
            return Self(left: -0.61, right: 0.61, top: -0.69, bottom: 0.52)
        case .foamFinger:
            return Self(left: -0.58, right: 0.46, top: -0.69, bottom: 0.52)
        case .flicker:
            return Self(left: -0.55, right: 0.46, top: -0.69, bottom: 0.52)
        case .redCape, .blueCape, .royalCape, .championCape:
            return Self(left: -0.53, right: 0.57, top: -0.69, bottom: 0.52)
        case .turkeyFeathers:
            return Self(left: -0.53, right: 0.53, top: -0.69, bottom: 0.52)
        case .lavaLamp:
            return Self(left: -0.48, right: 0.47, top: -0.69, bottom: 0.52)
        case .candy:
            return Self(left: -0.46, right: 0.46, top: -0.69, bottom: 0.52)
        case .neonSoles, .lightningKicks:
            return Self(left: -0.45, right: 0.46, top: -0.69, bottom: 0.56)
        case .spark, .lantern:
            return Self(left: -0.45, right: 0.93, top: -0.69, bottom: 0.52)
        case .firefly:
            return Self(left: -0.45, right: 0.95, top: -0.69, bottom: 0.52)
        case .flameyJr:
            return Self(left: -0.45, right: 0.93, top: -0.69, bottom: 0.53)
        case .sparkTrio:
            return Self(left: -0.45, right: 0.98, top: -0.69, bottom: 0.52)
        case .phoenixChick, .cometPup:
            return Self(left: -0.45, right: 1.07, top: -0.69, bottom: 0.52)
        case .friendlyGhost:
            return Self(left: -0.45, right: 1.00, top: -0.69, bottom: 0.52)
        default:
            return nil
        }
    }
}

/// A dressed figure fitted to a card. `size` is the BARE figure; the look's
/// measured reach (`ShareFlameyEnvelope`) decides how much he shrinks so the
/// whole outfit keeps inside `maxWidth` (drawn width) and `maxHeight`
/// (layout height), and the layout frame grows ABOVE the size square for
/// anything taller than his bare glow — so a crown pushes the headline down
/// instead of sliding into the kicker. He is centred on the OUTFIT, not on
/// his body: a companion on his right moves him left, a flag on his left
/// moves him right, so the group sits in the middle of the card. A bare
/// Flamey lays out exactly as `size × size` did before.
struct ShareDressedFigure<Figure: View>: View {
    let envelope: ShareFlameyEnvelope
    let size: CGFloat
    var maxWidth: CGFloat
    var maxHeight: CGFloat
    var hugsArt: Bool = false
    /// How far above his size square solid outfit art (a hat, a flag) may
    /// rise, in units of the fitted size, before he shrinks for it. Defaults
    /// to the bare glow's own reach; a tight frame (the milestone ring,
    /// whose stroke sits just above his glow) passes less.
    var headroom: CGFloat = ShareFlameyEnvelope.bareGlowAbove
    var accessory: ((Fit) -> AnyView)? = nil
    @ViewBuilder let figure: (CGFloat) -> Figure

    struct Fit {
        /// The size the figure is drawn at.
        let figureSize: CGFloat
        /// Its size square's centre, in the layout frame's coordinates.
        let center: CGPoint
        let frame: CGSize
    }

    static func fit(envelope e: ShareFlameyEnvelope, size: CGFloat, maxWidth: CGFloat,
                    maxHeight: CGFloat, hugsArt: Bool,
                    headroom: CGFloat = ShareFlameyEnvelope.bareGlowAbove) -> Fit {
        // Nothing taller than bare: his glow overflows the square as it
        // always did. Anything taller is solid art, held to `headroom`.
        let top = e.top >= ShareFlameyEnvelope.bare.top ? -0.5 : min(-0.5, e.top + headroom)
        let bottom = max(0.5, e.bottom - 0.02)
        let s = min(1,
                    maxWidth / ((e.right - e.left) * size),
                    maxHeight / ((bottom - top) * size))
        let d = size * s
        let height = (bottom - top) * d
        if hugsArt {
            let width = (e.right - e.left) * d
            return Fit(figureSize: d, center: CGPoint(x: -e.left * d, y: -top * d),
                       frame: CGSize(width: width, height: height))
        }
        return Fit(figureSize: d,
                   center: CGPoint(x: d / 2 - (e.left + e.right) / 2 * d, y: -top * d),
                   frame: CGSize(width: d, height: height))
    }

    var body: some View {
        let fit = Self.fit(envelope: envelope, size: size,
                           maxWidth: maxWidth, maxHeight: maxHeight, hugsArt: hugsArt,
                           headroom: headroom)
        let d = fit.figureSize
        Color.clear
            .frame(width: fit.frame.width, height: fit.frame.height)
            .overlay(alignment: .topLeading) {
                figure(d)
                    .frame(width: d, height: d)
                    .offset(x: fit.center.x - d / 2, y: fit.center.y - d / 2)
            }
            .overlay(alignment: .topLeading) {
                if let accessory {
                    accessory(fit)
                        .frame(width: fit.frame.width, height: fit.frame.height)
                }
            }
    }
}

/// The app's own ground plus one soft glow in the card's accent.
struct ShareGround: View {
    var glow: Color
    var center: UnitPoint = UnitPoint(x: 0.82, y: 0.08)
    var strength: Double = 0.36
    var radius: CGFloat = 352

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
            RadialGradient(
                colors: [glow.opacity(strength), glow.opacity(strength * 0.22), .clear],
                center: center, startRadius: 8, endRadius: radius
            )
        }
    }
}

/// The photo's own colours washed across the card behind a framed photo —
/// a tiny image drawn back up, never `.blur()` (ImageRenderer may drop it).
struct SharePhotoBackdrop: View {
    let content: MADStoryContent
    var size: CGSize = MADStoryFormat.story.size

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
            if let wash = content.photoWash ?? content.photo {
                Image(uiImage: wash)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .opacity(0.55)
            }
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.34), location: 0.00),
                    .init(color: .black.opacity(0.44), location: 0.45),
                    .init(color: .black.opacity(0.78), location: 1.00),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .frame(width: size.width, height: size.height)
    }
}

/// "🔥 41 day streak" as a warm chip — the number Strava can't show.
struct ShareStreakChip: View {
    let streak: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12, weight: .black))
            Text("\(streak) day streak")
                .font(.system(size: 13, weight: .black, design: .rounded))
        }
        .foregroundColor(MADTheme.Colors.warning)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(MADTheme.Colors.warning.opacity(0.16)))
        .lineLimit(1)
    }
}

/// Words every card shares, so no two cards phrase the same fact differently.
enum ShareCopy {
    static func kicker(_ content: MADStoryContent) -> String? {
        let parts = [date(content), content.activityName?.uppercased()].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func date(_ content: MADStoryContent) -> String? {
        if let text = content.dateText, !text.isEmpty { return text.uppercased() }
        if let date = content.date { return monthDay.string(from: date).uppercased() }
        return nil
    }

    static func distance(_ miles: Double?) -> String? {
        guard let miles, miles > 0 else { return nil }
        return "\(miles.distanceText) \(DistanceUnits.current.abbreviation)"
    }

    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f
    }()

    /// A photo's own aspect, fitted to `bounds` — computed rather than left to
    /// `.aspectRatio(.fit)` inside a `.frame`, which letterboxes INSIDE the
    /// border (ios.md: the photo frame ADOPTS THE PHOTO'S ASPECT).
    static func fit(_ image: UIImage?, in bounds: CGSize) -> CGSize {
        guard let image, image.size.width > 0, image.size.height > 0 else { return bounds }
        let aspect = image.size.width / image.size.height
        var width = bounds.width
        var height = width / aspect
        if height > bounds.height {
            height = bounds.height
            width = height * aspect
        }
        return CGSize(width: width, height: height)
    }

    static func kickerText(_ text: String, color: Color = .white.opacity(0.45), size: CGFloat = 11.5) -> some View {
        Text(text)
            .font(.system(size: size, weight: .black, design: .rounded))
            .tracking(2.4)
            .foregroundColor(color)
            .lineLimit(1)
    }

    static func hero(_ value: String, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(.system(size: size, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
            Text(DistanceUnits.current.abbreviation.uppercased())
                .font(.system(size: max(16, size * 0.24), weight: .black, design: .rounded))
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.5))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

// MARK: - Picture

/// The photo in a white instant-print frame, tilted a few degrees, with the
/// distance written in the bottom margin where a pen would go.
struct PolaroidShareCard: View {
    let content: MADStoryContent

    private let ink = Color(red: 0.16, green: 0.10, blue: 0.11)
    private let paper = Color(red: 0.97, green: 0.95, blue: 0.92)
    private var box: CGSize { ShareCopy.fit(content.photo, in: CGSize(width: 268, height: 330)) }

    var body: some View {
        ZStack {
            SharePhotoBackdrop(content: content)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                print
                    .rotationEffect(.degrees(-3))
                if let streak = content.streak, streak > 0 {
                    ShareStreakChip(streak: streak)
                        .padding(.top, 34)
                }
                Spacer(minLength: 0)
                ShareLockup()
            }
            .padding(28)
        }
        .frame(width: 360, height: 640)
        .clipped()
    }

    private var print: some View {
        VStack(spacing: 0) {
            if let photo = content.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: box.width, height: box.height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(ShareCopy.distance(content.distanceMiles) ?? (content.activityName ?? "Mile a day"))
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(ink)
                    .monospacedDigit()
                Spacer(minLength: 8)
                if let date = ShareCopy.date(content) {
                    Text(date.capitalized)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(ink.opacity(0.55))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 4)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
        .frame(width: box.width)
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(paper))
        .shadow(color: .black.opacity(0.55), radius: 22, x: 0, y: 14)
    }
}

/// A tall framed photo with the distance set huge across its bottom edge —
/// the magazine-cover layout.
struct BigNumberPhotoShareCard: View {
    let content: MADStoryContent
    let stats: [ShareStatKind]

    private var box: CGSize { ShareCopy.fit(content.photo, in: CGSize(width: 320, height: 400)) }

    var body: some View {
        ZStack {
            SharePhotoBackdrop(content: content)
            VStack(alignment: .leading, spacing: 0) {
                photo
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    .padding(.horizontal, -8)
                if let d = content.distanceMiles, d > 0 {
                    ShareCopy.hero(d.distanceText, size: 112)
                        .shadow(color: .black.opacity(0.6), radius: 18, x: 0, y: 8)
                        .padding(.top, -60)
                }
                if let kicker = ShareCopy.kicker(content) {
                    ShareCopy.kickerText(kicker)
                        .padding(.top, 8)
                }
                Spacer(minLength: 0)
                ShareStatRail(stats: ShareStatKind.rail(stats, content: content, hero: .distance, limit: 3))
                ShareLockup()
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .frame(width: 360, height: 640)
        .clipped()
    }

    @ViewBuilder
    private var photo: some View {
        if let image = content.photo {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: box.width, height: box.height)
                .clipped()
                .overlay(
                    // The number sits over the photo's lower edge, so the
                    // photo carries its own floor for the type to stand on.
                    LinearGradient(colors: [.clear, .black.opacity(0.55)],
                                   startPoint: UnitPoint(x: 0.5, y: 0.6), endPoint: .bottom)
                )
                .modifier(ArtFrame(cornerRadius: 20))
        }
    }
}

// MARK: - Route

/// The route drawn over its own streets, dark and washed (`GhostMapUnderlay`),
/// in a tall frame, with the numbers in a rail beneath.
struct MapRouteShareCard: View {
    let content: MADStoryContent
    let stats: [ShareStatKind]

    /// The underlay is generated at EXACTLY this size — `RouteArtLayout`
    /// projects through the snapshot, so a snapshot of another size would put
    /// the line off its streets.
    static let artSize = CGSize(width: 320, height: 430)

    var body: some View {
        ZStack {
            ShareGround(glow: content.routeColor, center: UnitPoint(x: 0.5, y: 0.35), strength: 0.22)
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    RouteArtView.still(
                        coordinates: content.coordinates,
                        routeColor: content.routeColor,
                        authorAvatar: content.avatar,
                        avatarImages: avatarImages,
                        showsMileMarkers: true,
                        underlay: content.mapUnderlay,
                        paletteDate: content.date,
                        size: Self.artSize
                    )
                    .frame(width: Self.artSize.width, height: Self.artSize.height)
                    if let kicker = ShareCopy.kicker(content) {
                        Text(kicker)
                            .font(.system(size: 10.5, weight: .black, design: .rounded))
                            .tracking(1.8)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .padding(14)
                    }
                }
                .modifier(ArtFrame(cornerRadius: 20))
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 0) {
                    ShareStatRail(stats: ShareStatKind.rail(stats, content: content, hero: nil, limit: 3))
                    ShareLockup()
                }
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .frame(width: 360, height: 640)
        .clipped()
    }

    private var avatarImages: [String: UIImage] {
        guard let key = content.avatar?.imageURL, !key.isEmpty,
              let image = content.avatarImage else { return [:] }
        return [key: image]
    }
}

/// The number first, the line under it, the rail at the foot.
struct RouteRailShareCard: View {
    let content: MADStoryContent
    let stats: [ShareStatKind]

    private let art = CGSize(width: 304, height: 304)

    var body: some View {
        ZStack {
            ShareGround(glow: content.routeColor, center: UnitPoint(x: 0.2, y: 0.3), strength: 0.28)
            VStack(alignment: .leading, spacing: 0) {
                if let kicker = ShareCopy.kicker(content) {
                    ShareCopy.kickerText(kicker)
                }
                if let d = content.distanceMiles, d > 0 {
                    ShareCopy.hero(d.distanceText, size: 96)
                        .padding(.top, 6)
                }
                Spacer(minLength: 0)
                RouteArtView.still(
                    coordinates: content.coordinates,
                    routeColor: content.routeColor,
                    authorAvatar: content.avatar,
                    avatarImages: avatarImages,
                    showsMileMarkers: false,
                    paletteDate: content.date,
                    size: art
                )
                .frame(width: art.width, height: art.height)
                .modifier(ArtFrame(cornerRadius: 20))
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
                ShareStatRail(stats: ShareStatKind.rail(stats, content: content, hero: .distance, limit: 3))
                ShareLockup()
            }
            .padding(28)
        }
        .frame(width: 360, height: 640)
        .clipped()
    }

    private var avatarImages: [String: UIImage] {
        guard let key = content.avatar?.imageURL, !key.isEmpty,
              let image = content.avatarImage else { return [:] }
        return [key: image]
    }
}

// MARK: - Streak

/// Typographic: the day count as big as the card will hold.
struct BoldStreakShareCard: View {
    let content: MADStoryContent

    private var streak: Int { content.streak ?? 0 }
    private var numberSize: CGFloat {
        switch String(streak).count {
        case ...2: return 210
        case 3: return 150
        default: return 116
        }
    }

    var body: some View {
        ZStack {
            ShareGround(glow: MADTheme.Colors.warning, center: UnitPoint(x: 0.9, y: 0.95), strength: 0.4)
            VStack(alignment: .leading, spacing: 0) {
                ShareCopy.kickerText("A MILE A DAY FOR", color: MADTheme.Colors.warning)
                Text("\(streak)")
                    .font(.system(size: numberSize, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .tracking(-6)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.top, 10)
                Text(streak == 1 ? "day.\nDay one." : "days\nstraight.")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineSpacing(-4)
                    .padding(.top, 2)
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    if let d = ShareCopy.distance(content.distanceMiles) {
                        ShareCopy.kickerText("TODAY · \(d.uppercased())")
                            .padding(.bottom, 8)
                    }
                    Spacer(minLength: 0)
                    ShareStyleFlame(size: 92, maxWidth: 170, maxHeight: 132, hugsArt: true)
                }
                ShareLockup()
            }
            .padding(28)
        }
        .frame(width: 360, height: 640)
        .clipped()
    }
}

/// A milestone day (7, 30, 100, 365…) — a medal-like ring with the day count
/// in it. Offered only on a day the app itself celebrates.
struct MilestoneShareCard: View {
    let content: MADStoryContent

    private var streak: Int { content.streak ?? 0 }

    var body: some View {
        ZStack {
            ShareGround(glow: MADTheme.Colors.warning, center: UnitPoint(x: 0.5, y: 0.4), strength: 0.45)
            VStack(spacing: 0) {
                ShareCopy.kickerText("STREAK MILESTONE", color: MADTheme.Colors.warning)
                    .padding(.top, 10)
                Spacer(minLength: 0)
                ring
                Text(ShareMilestone.headline(streak))
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 26)
                Text("\(streak) days, one mile at a time")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.top, 6)
                Spacer(minLength: 0)
                ShareLockup()
            }
            .padding(28)
        }
        .frame(width: 360, height: 640)
        .clipped()
    }

    private var ring: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(
                    colors: [MADTheme.Colors.warning, MADTheme.Colors.madRed, MADTheme.Colors.warning],
                    center: .center))
            Circle()
                .fill(Color(red: 0.10, green: 0.05, blue: 0.06))
                .padding(6)
            VStack(spacing: 0) {
                ShareStyleFlame(size: 70, maxWidth: 118, maxHeight: 70,
                                // The ring's stroke sits just above his
                                // glow: a hat may not climb into it.
                                headroom: 0.04)
                Text("DAY")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .tracking(4)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, 4)
                Text("\(streak)")
                    .font(.system(size: 84, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 24)
            }
        }
        .frame(width: 250, height: 250)
        .shadow(color: MADTheme.Colors.warning.opacity(0.35), radius: 24, x: 0, y: 0)
    }
}

// MARK: - Flamey

/// Flamey in his shades: the mile, celebrated by the character.
struct FlameyMileShareCard: View {
    let content: MADStoryContent
    let stats: [ShareStatKind]

    private var streak: Int { content.streak ?? 0 }

    /// The caller's answer, else the distance's: a card with no verdict is
    /// a single walk, and it did the mile when it covered one (the app's
    /// 0.95 tolerance, `ProgressCalculator`).
    private var mileDone: Bool {
        if let met = content.goalMet { return met }
        guard let d = content.distanceMiles else { return true }
        return ProgressCalculator.isGoalCompleted(current: d, goal: 1)
    }

    private var headline: String {
        if mileDone { return "Mile done." }
        if (content.distanceMiles ?? 0) > 0 { return "Got moving." }
        return streak > 0 ? "Still lit." : "Let's walk."
    }

    private var subline: String? {
        var parts: [String] = []
        if let d = ShareCopy.distance(content.distanceMiles) { parts.append(d) }
        if streak > 0 { parts.append("Day \(streak)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        ZStack {
            ShareGround(glow: MADTheme.Colors.warning, center: UnitPoint(x: 0.5, y: 0.42), strength: 0.42)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ShareFlamey(size: 220, mood: mileDone ? .done : nil, streak: streak, maxHeight: 286)
                Text(headline)
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 12)
                if let subline {
                    Text(subline)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.top, 10)
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 0) {
                    ShareStatRail(stats: ShareStatKind.rail(stats, content: content, hero: nil, limit: 3))
                    ShareLockup()
                }
            }
            .padding(28)
        }
        .frame(width: 360, height: 640)
        .clipped()
    }
}

/// Flamey with the day count on a tag — party hat on a milestone.
struct FlameyStreakShareCard: View {
    let content: MADStoryContent

    private var streak: Int { content.streak ?? 0 }
    private var milestone: Bool { ShareMilestone.isMilestone(streak) }

    var body: some View {
        ZStack {
            ShareGround(glow: MADTheme.Colors.warning, center: UnitPoint(x: 0.5, y: 0.35), strength: 0.45)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ShareFlamey(size: 210, mood: milestone ? .party : .done, streak: streak,
                            maxHeight: 280, streakTag: streak)
                Text(streak == 1 ? "Day one.\nLit." : "\(streak) days.\nStill lit.")
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 24)
                Text(streak == 1 ? "The first mile of the streak" : "A mile every day, \(streak) days running")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.top, 10)
                Spacer(minLength: 0)
                ShareLockup()
            }
            .padding(28)
        }
        .frame(width: 360, height: 640)
        .clipped()
    }
}

// MARK: - Stats sticker

/// Strava's see-through stats sticker: white numbers with a soft shadow and
/// the route's shape, on NOTHING — it lands on a story the walker was already
/// making, over their own photo.
struct StatsStickerShareCard: View {
    let content: MADStoryContent
    let stats: [ShareStatKind]

    private var rows: [(String, String)] {
        let chosen = Set(stats)
        return ShareStatKind.allCases
            .filter { chosen.contains($0) && $0 != .streak }
            .compactMap { kind -> (String, String)? in
                switch kind {
                case .distance:
                    return ShareCopy.distance(content.distanceMiles).map { (kind.title, $0) }
                case .pace:
                    guard let p = content.paceSecondsPerMile, p > 0 else { return nil }
                    return (kind.title, RunStatsStickerView.paceText(p.pacePerDisplayUnit) + " " + DistanceUnits.current.paceSuffix)
                case .time:
                    guard let t = content.durationSeconds, t > 0 else { return nil }
                    return (kind.title, RunStatsStickerView.durationText(t))
                case .calories:
                    guard let c = content.calories, c >= 1 else { return nil }
                    return (kind.title, "\(Int(c.rounded())) kcal")
                case .streak:
                    return nil
                }
            }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(rows, id: \.0) { row in
                VStack(spacing: 1) {
                    Text(row.0)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(0.92))
                    Text(row.1)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            if content.hasRoute {
                ShareRouteGlyph(coordinates: content.coordinates)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    .frame(width: 96, height: 96)
                    .padding(.top, 4)
            }
            let streak = content.streak ?? 0
            ShareLockup(format: .sticker,
                        suffix: (stats.contains(.streak) && streak > 0) ? "DAY \(streak)" : nil,
                        showsURL: false)
                .fixedSize()
                .padding(.top, -8)
        }
        .shadow(color: .black.opacity(0.55), radius: 8, x: 0, y: 2)
        .padding(22)
        .frame(width: 320, height: 400)
    }
}

/// A route's SHAPE with no canvas under it — for the see-through sticker,
/// where `RouteArtView`'s ground would defeat the transparency. Breaks at the
/// same gaps every other route surface does (`RouteGaps`), so a paused-and-
/// moved walk never draws a line across ground nobody walked.
struct ShareRouteGlyph: Shape {
    let coordinates: [CLLocationCoordinate2D]

    func path(in rect: CGRect) -> Path {
        guard coordinates.count >= 2 else { return Path() }
        let midLat = coordinates.map(\.latitude).reduce(0, +) / Double(coordinates.count)
        let k = cos(midLat * .pi / 180)
        let xs = coordinates.map { $0.longitude * k }
        let ys = coordinates.map { -$0.latitude }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return Path() }
        let spanX = max(maxX - minX, 1e-9)
        let spanY = max(maxY - minY, 1e-9)
        let scale = min(rect.width / spanX, rect.height / spanY)
        let offX = rect.minX + (rect.width - spanX * scale) / 2
        let offY = rect.minY + (rect.height - spanY * scale) / 2
        func point(_ i: Int) -> CGPoint {
            CGPoint(x: offX + (xs[i] - minX) * scale, y: offY + (ys[i] - minY) * scale)
        }
        let breaks = RouteGaps.breakIndices(coordinates: coordinates, times: nil)
        var path = Path()
        for piece in RouteGaps.pieces(count: coordinates.count, breaks: breaks) where piece.count >= 2 {
            path.move(to: point(piece.lowerBound))
            for i in (piece.lowerBound + 1)...piece.upperBound { path.addLine(to: point(i)) }
        }
        return path
    }
}

// MARK: - Week

/// Seven days from the week's Sunday, in the app's day-state language: green = goal
/// met, blue (`SavedDayStyle`) = a token carried it, an orange arc = some
/// miles short of the goal, an empty ring = nothing, dotted = still to come.
struct ShareWeekStrip: View {
    let recap: WeeklyRecap
    var dot: CGFloat = 34

    private static let letter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEE")
        return f
    }()

    var body: some View {
        HStack(spacing: 0) {
            ForEach(recap.sevenDays) { day in
                VStack(spacing: 6) {
                    badge(day)
                        .frame(width: dot, height: dot)
                    Text(day.localDate.map { Self.letter.string(from: $0) } ?? "")
                        .font(.system(size: max(9, dot * 0.29), weight: .black, design: .rounded))
                        .tracking(1)
                        .foregroundColor(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func badge(_ day: WeeklyRecap.Day) -> some View {
        let future = (day.localDate ?? .distantPast) > Date()
        if day.goalMet {
            ZStack {
                Circle().fill(MADTheme.Colors.success)
                Image(systemName: "checkmark")
                    .font(.system(size: dot * 0.4, weight: .black))
                    .foregroundColor(.white)
            }
        } else if day.covered {
            ZStack {
                Circle().fill(SavedDayStyle.tint)
                Image(systemName: "shield.fill")
                    .font(.system(size: dot * 0.36, weight: .black))
                    .foregroundColor(.white)
            }
        } else if day.miles > 0 {
            let goal = max(recap.goalMiles ?? 1, 0.01)
            ZStack {
                Circle().stroke(Color.white.opacity(0.14), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: min(1, day.miles / goal))
                    .stroke(MADTheme.Colors.warning, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .padding(1.5)
        } else if future {
            Circle()
                .stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 2, dash: [3, 4]))
                .padding(1)
        } else {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 2)
                .padding(1)
        }
    }
}

/// The week as a story (or, in sticker shape, a card to drop on one).
struct WeekShareCard: View {
    let content: MADStoryContent
    var format: MADStoryFormat = .story

    private var recap: WeeklyRecap? { content.week }

    var body: some View {
        if let recap {
            if format == .story { story(recap) } else { sticker(recap) }
        }
    }

    private func story(_ recap: WeeklyRecap) -> some View {
        ZStack {
            ShareGround(glow: MADTheme.Colors.madRed, center: UnitPoint(x: 0.85, y: 0.05), strength: 0.4)
            VStack(alignment: .leading, spacing: 0) {
                ShareCopy.kickerText("YOUR WEEK · \(recap.rangeText.uppercased())")
                ShareCopy.hero((recap.totalMiles ?? 0).distanceText, size: 104)
                    .padding(.top, 10)
                // Only a week UP on the last is worth printing on a card
                // somebody chose to post — "↘ 12%" under their total read as
                // the card arguing with them. (The recap screen keeps both.)
                if let delta = recap.deltaFraction, delta >= 0.01 {
                    WeekDeltaChip(delta: delta)
                        .padding(.top, 10)
                }
                // The total owns the top; the story of the week sits as ONE
                // block at the bottom (headline over the days over the rail).
                // Two spacers left the headline floating in the middle with
                // a hole on each side.
                Spacer(minLength: 24)
                headline(recap)
                ShareWeekStrip(recap: recap)
                    .padding(.top, 26)
                ShareStatRail(stats: WeekShareCard.rail(recap, limit: 3))
                    .padding(.top, 20)
                ShareLockup()
            }
            .padding(28)
        }
        .frame(width: 360, height: 640)
        .clipped()
    }

    private func sticker(_ recap: WeeklyRecap) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ShareCopy.kickerText("MY WEEK · \(recap.rangeText.uppercased())", size: 10)
            ShareCopy.hero((recap.totalMiles ?? 0).distanceText, size: 72)
                .padding(.top, 8)
            Spacer(minLength: 0)
            ShareWeekStrip(recap: recap, dot: 30)
            ShareStatRail(stats: WeekShareCard.rail(recap, limit: 2), format: .sticker)
                .padding(.top, 14)
            ShareLockup(format: .sticker)
        }
        .padding(22)
        .frame(width: 320, height: 400)
        .background(MADTheme.Colors.appBackgroundGradient)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private func headline(_ recap: WeeklyRecap) -> some View {
        let lines = WeekShareCard.headlines(recap)
        VStack(alignment: .leading, spacing: 2) {
            if let first = lines.first {
                Text(first).foregroundColor(.white)
            }
            if lines.count > 1 {
                Text(lines[1]).foregroundColor(.white.opacity(0.55))
            }
        }
        .font(.system(size: 30, weight: .black, design: .rounded))
        .lineLimit(2)
        .minimumScaleFactor(0.6)
    }

    /// The server's highlights, else the goal-day count — never empty.
    static func headlines(_ recap: WeeklyRecap) -> [String] {
        let fromServer = recap.highlights.prefix(2).map { $0.hasSuffix(".") || $0.hasSuffix("!") ? $0 : $0 + "." }
        if !fromServer.isEmpty { return Array(fromServer) }
        let days = recap.goalDays
        return [days == 7 ? "7 for 7." : "\(days) of 7 goal days."]
    }

    /// Goal days are already the row of seven right above the rail (and often
    /// the headline too), so the rail leads with what the card doesn't say
    /// yet; goal days only fill a slot nothing else can.
    static func rail(_ recap: WeeklyRecap, limit: Int) -> [MADStoryStat] {
        var out: [MADStoryStat] = []
        if let streak = recap.currentStreak, streak > 0 {
            out.append(MADStoryStat(value: "\(streak)", label: "STREAK", tint: MADTheme.Colors.warning))
        }
        if let friends = recap.friends, let rank = friends.rank, let of = friends.of, of > 1 {
            out.append(MADStoryStat(value: "#\(rank)", label: "OF \(of) FRIENDS"))
        } else if let workouts = recap.workouts, workouts > 0 {
            out.append(MADStoryStat(value: "\(workouts)", label: workouts == 1 ? "WORKOUT" : "WORKOUTS"))
        }
        if let seconds = recap.totalDurationSeconds, seconds >= 60 {
            out.append(MADStoryStat(value: WeeklyRecapView.durationText(seconds), label: "MOVING"))
        }
        if out.count < limit {
            out.insert(MADStoryStat(value: "\(recap.goalDays)/7", label: "GOAL DAYS"), at: 0)
        }
        return Array(out.prefix(limit))
    }
}

/// "▲ 33% vs last week" — green up, muted down (a slower week is not a
/// failure worth colouring red on a card somebody chose to post).
struct WeekDeltaChip: View {
    let delta: Double

    var body: some View {
        let up = delta >= 0
        HStack(spacing: 5) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 11, weight: .black))
            Text("\(Int((abs(delta) * 100).rounded()))% vs last week")
                .font(.system(size: 13, weight: .black, design: .rounded))
        }
        .foregroundColor(up ? MADTheme.Colors.success : .white.opacity(0.6))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill((up ? MADTheme.Colors.success : Color.white).opacity(0.16)))
        .lineLimit(1)
    }
}

/// Flamey presenting the week.
struct FlameyWeekShareCard: View {
    let content: MADStoryContent

    var body: some View {
        if let recap = content.week {
            ZStack {
                ShareGround(glow: MADTheme.Colors.warning, center: UnitPoint(x: 0.5, y: 0.3), strength: 0.42)
                VStack(spacing: 0) {
                    ShareCopy.kickerText("YOUR WEEK · \(recap.rangeText.uppercased())")
                    Spacer(minLength: 0)
                    ShareFlamey(size: 180,
                                mood: recap.goalDays == 7 ? .party : (recap.goalDays >= 4 ? .done : nil),
                                streak: recap.currentStreak ?? 0, maxHeight: 232)
                    Text(ShareCopy.distance(recap.totalMiles) ?? "0.00 \(DistanceUnits.current.abbreviation)")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.top, 12)
                    Text(subline(recap))
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 8)
                    ShareWeekStrip(recap: recap, dot: 32)
                        .padding(.top, 26)
                    Spacer(minLength: 0)
                    ShareLockup()
                }
                .padding(28)
            }
            .frame(width: 360, height: 640)
            .clipped()
        }
    }

    private func subline(_ recap: WeeklyRecap) -> String {
        var parts = ["\(recap.goalDays) of 7 goal days"]
        if let streak = recap.currentStreak, streak > 0 { parts.append("\(streak) day streak") }
        return parts.joined(separator: " · ")
    }
}
