import SwiftUI
import UIKit

// MARK: - Achievement share cards (Medal · Record)
//
// A medal or a race PR is not a walk, but it IS a share — and it used to be the
// one share in the app with no preview: Share rendered a 4:5 card off-screen and
// threw the system sheet up over it, so nobody knew what they were about to
// post. These cards put both through the Share Studio like everything else:
// a 9:16 story and a see-through sticker, previewed before anything leaves the
// phone, with the same Instagram handoff and destinations.
//
// Same card rules as ShareTemplateCards (ios.md, the sharing bullet): explicit
// sizes, nothing asynchronous, no TimelineView/.blur(), ONE `ShareLockup`
// bottom-left. The medal is the shelf's own drawing (`HangingMedal` /
// `MedalView`, `showShimmer: false`, never the tilting hero — a sensor-driven
// view bakes at whatever angle it happened to be at), and its colours are the
// medal's own rarity palette rather than anything picked here.

/// A medal to share. Built by `ShareMedal.forOwnBadge` from the viewer's own
/// shelf — the "how earned" line is this account's, never a friend's.
struct ShareMedal {
    let badge: Badge
    var earnedDate: Date
    /// The server's "how earned" sentence, already re-voiced for a card the
    /// owner posts ("Ran a 7:42 mile"), else nil and the card falls back to
    /// the medal's description.
    var howEarned: String? = nil

    var palette: MedalPalette { .forRarity(badge.rarity, locked: false) }

    /// The medal as it hangs on the card — never locked, whatever the copy
    /// says, because only an earned medal reaches the studio.
    var earnedBadge: Badge {
        var b = badge
        b.isLocked = false
        return b
    }

    var rarityTitle: String { badge.rarity.rawValue.uppercased() }

    var dateText: String { ShareMedal.longDate.string(from: earnedDate).uppercased() }

    /// The line under the name: how it was earned, else what it's for.
    var line: String? {
        if let howEarned, !howEarned.isEmpty { return howEarned }
        let d = badge.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return d.isEmpty ? nil : d
    }

    /// The viewer's own medal, with this account's earned detail (the same
    /// source `MedalHowEarnedCard` reads) and its derived day.
    static func forOwnBadge(_ badge: Badge) -> ShareMedal {
        let detail = BadgeEarnedDetails.entry(for: badge.id)
        return ShareMedal(badge: badge,
                          earnedDate: FlameyClosetCopy.parseDay(detail?.date) ?? badge.dateAwarded,
                          howEarned: cardVoice(detail?.summary))
    }

    /// The server writes summaries TO the owner ("You ran a 7:42 mile"). On a
    /// card the owner posts, "You" reads as addressing whoever is looking at
    /// the story, so the subject is dropped: "Ran a 7:42 mile".
    static func cardVoice(_ summary: String?) -> String? {
        guard var s = summary?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.hasPrefix("You "), s.count > 4 {
            let rest = s.dropFirst(4)
            s = rest.prefix(1).uppercased() + rest.dropFirst()
        }
        s = s.replacingOccurrences(of: " your ", with: " my ")
        return s
    }

    static let longDate: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("yMMMd")
        return f
    }()
}

/// A race PR to share: the best time over one standard distance.
struct ShareRecord {
    /// "5K", "Half Marathon" — the race IS the distance, so no mileage figure
    /// is printed (a floored 3.10 under a "5K" reads as the app arguing).
    let distanceName: String
    let durationSeconds: Double
    let distanceMiles: Double
    var date: Date? = nil

    var timeText: String { RaceCatalog.formatTime(durationSeconds) }

    var paceText: String? {
        guard distanceMiles > 0, durationSeconds > 0 else { return nil }
        let perMile = durationSeconds / distanceMiles
        return RunStatsStickerView.paceText(perMile.pacePerDisplayUnit)
    }

    var dateText: String? { date.map { ShareMedal.longDate.string(from: $0).uppercased() } }
}

// MARK: - Medal

/// The medal as a story (hanging on its ribbon, in its own light) or as a
/// see-through sticker to drop on a story the walker is already making.
struct MedalShareCard: View {
    let content: MADStoryContent
    var format: MADStoryFormat = .story

    var body: some View {
        if let medal = content.medal {
            if format == .story { story(medal) } else { sticker(medal) }
        }
    }

    private func story(_ medal: ShareMedal) -> some View {
        let palette = medal.palette
        return ZStack {
            ShareGround(glow: palette.glow, center: UnitPoint(x: 0.5, y: 0.34), strength: 0.42, radius: 320)
            VStack(spacing: 0) {
                ShareCopy.kickerText("MEDAL EARNED", color: palette.rimHi.opacity(0.85))
                    .padding(.top, 6)
                Spacer(minLength: 0)
                HangingMedal(badge: medal.earnedBadge, size: 164, showShimmer: false)
                rarityPill(medal, size: 11)
                    .padding(.top, 24)
                Text(medal.badge.name)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 14)
                if let line = medal.line {
                    Text(line)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .padding(.top, 8)
                        .padding(.horizontal, 8)
                }
                ShareCopy.kickerText(medal.dateText, color: .white.opacity(0.4), size: 11)
                    .padding(.top, 16)
                Spacer(minLength: 0)
                ShareLockup()
            }
            .padding(28)
        }
        .frame(width: 360, height: 640)
        .clipped()
    }

    /// See-through: the medal and its words on NOTHING, shadowed so they read
    /// over whatever photo they land on (the stats sticker's recipe).
    private func sticker(_ medal: ShareMedal) -> some View {
        VStack(spacing: 0) {
            HangingMedal(badge: medal.earnedBadge, size: 128, showShimmer: false)
            VStack(spacing: 0) {
                Text(medal.badge.name)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 14)
                Text("\(medal.rarityTitle) · \(medal.dateText)")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(1.8)
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 6)
                ShareLockup(format: .sticker, showsURL: false)
                    .fixedSize()
                    .padding(.top, -2)
            }
            .shadow(color: .black.opacity(0.55), radius: 8, x: 0, y: 2)
        }
        .padding(22)
        .frame(width: 320, height: 400)
    }

    private func rarityPill(_ medal: ShareMedal, size: CGFloat) -> some View {
        let palette = medal.palette
        return Text(medal.rarityTitle)
            .font(.system(size: size, weight: .black, design: .rounded))
            .tracking(2.4)
            .foregroundColor(palette.rimHi)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(palette.glow.opacity(0.16)))
            .overlay(Capsule().strokeBorder(palette.glow.opacity(0.5), lineWidth: 1))
            .lineLimit(1)
    }
}

// MARK: - Record

/// A race PR: the time as big as the card will hold, the race over it.
struct RecordShareCard: View {
    let content: MADStoryContent
    var format: MADStoryFormat = .story

    var body: some View {
        if let record = content.record {
            if format == .story { story(record) } else { sticker(record) }
        }
    }

    private var paceLabel: String { "PACE " + DistanceUnits.current.paceSuffix.uppercased() }

    private func rail(_ record: ShareRecord) -> [MADStoryStat] {
        var out: [MADStoryStat] = []
        if let pace = record.paceText { out.append(MADStoryStat(value: pace, label: paceLabel)) }
        if let date = record.date {
            out.append(MADStoryStat(value: ShareMedal.longDate.string(from: date), label: "SET ON"))
        }
        return out
    }

    private func story(_ record: ShareRecord) -> some View {
        ZStack {
            ShareGround(glow: MADTheme.Colors.madRed, center: UnitPoint(x: 0.85, y: 0.08), strength: 0.42)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    ShareCopy.kickerText("PERSONAL RECORD", color: MADTheme.Colors.madRed)
                    Spacer(minLength: 0)
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [MADTheme.Colors.warning, MADTheme.Colors.madRed],
                                                        startPoint: .top, endPoint: .bottom))
                        .accessibilityHidden(true)
                }
                Text(record.distanceName)
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 4)
                Spacer(minLength: 0)
                Text(record.timeText)
                    .font(.system(size: 112, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .tracking(-3)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text("My fastest \(record.distanceName) yet.")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 2)
                Spacer(minLength: 0)
                ShareStatRail(stats: rail(record))
                ShareLockup()
            }
            .padding(28)
        }
        .frame(width: 360, height: 640)
        .clipped()
    }

    private func sticker(_ record: ShareRecord) -> some View {
        VStack(spacing: 2) {
            Text("\(record.distanceName.uppercased()) PR")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .tracking(2)
                .foregroundColor(.white.opacity(0.92))
                .lineLimit(1)
            Text(record.timeText)
                .font(.system(size: 64, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let pace = record.paceText {
                Text("\(pace) \(DistanceUnits.current.paceSuffix)")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
            }
            if let date = record.dateText {
                Text(date)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(1.8)
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
                    .padding(.top, 4)
            }
            ShareLockup(format: .sticker, showsURL: false)
                .fixedSize()
                .padding(.top, -4)
        }
        .shadow(color: .black.opacity(0.55), radius: 8, x: 0, y: 2)
        .padding(22)
        .frame(width: 320, height: 400)
    }
}
