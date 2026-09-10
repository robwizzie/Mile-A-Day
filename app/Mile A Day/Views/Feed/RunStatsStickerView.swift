import SwiftUI

// MARK: - Stat kinds, styles, accents

/// A single run statistic the user can choose to show on their post.
enum RunStatKind: String, CaseIterable, Identifiable, Codable {
    case distance, pace, duration, streak, calories, steps, date
    /// The competition the poster CHOSE to show: name, their place, and the
    /// podium they're on (`RunStatsInput.competition`). Offered only while
    /// they're in a live competition, and never on by default — nothing puts a
    /// competition on a post unless the poster puts it there.
    ///
    /// Unlike every other kind this one doesn't render as a chip: it's a block
    /// of its own under the stats (`competitionBlock`), so it never lands in
    /// the hero slot and never gets squeezed into a chip row.
    case competition
    var id: String { rawValue }

    var label: String {
        switch self {
        case .distance: return "Distance"
        case .pace: return "Pace"
        case .duration: return "Time"
        case .streak: return "Streak"
        case .calories: return "Calories"
        case .steps: return "Steps"
        case .date: return "Date"
        case .competition: return "Competition"
        }
    }

    var icon: String {
        switch self {
        case .distance: return "figure.run"
        case .pace: return "speedometer"
        case .duration: return "clock.fill"
        case .streak: return "flame.fill"
        case .calories: return "bolt.fill"
        case .steps: return "shoeprints.fill"
        case .date: return "calendar"
        case .competition: return "trophy.fill"
        }
    }
}

/// Visual templates for the overlay. The user can flip between them live.
///
/// These deliberately have no `icon`: the picker used to be text chips with
/// abstract SF Symbols (`rectangle.fill`, `minus.rectangle.fill`, …), which told
/// you nothing about what a style actually looked like. `StickerTrayView` renders
/// a live miniature of each style instead, so the name is the only label needed.
enum StickerStyle: String, CaseIterable, Identifiable, Codable {
    case card, minimal, stacked, streak
    var id: String { rawValue }
    var title: String {
        switch self {
        case .card: return "Card"
        case .minimal: return "Minimal"
        case .stacked: return "Stacked"
        case .streak: return "Streak"
        }
    }
}

/// Accent color applied to icons / highlights on the sticker.
enum StickerAccent: String, CaseIterable, Identifiable, Codable {
    case orange, red, blue, green, mono
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .orange: return .orange
        case .red: return MADTheme.Colors.madRed
        case .blue: return Color(red: 0.25, green: 0.6, blue: 0.95)
        case .green: return MADTheme.Colors.success
        case .mono: return .white
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// User-controlled overlay configuration. Persisted between sessions so the
/// composer remembers how someone likes to show their run.
struct StickerConfig: Equatable, Codable {
    /// Transform bounds, owned HERE so every consumer of a persisted config
    /// (composer gestures, decode-time sanitizing, any future render path)
    /// enforces the same invariant.
    static let scaleRange: ClosedRange<CGFloat> = 0.6...1.9
    static let posXRange: ClosedRange<CGFloat> = 0.12...0.88
    static let posYRange: ClosedRange<CGFloat> = 0.1...0.9

    var style: StickerStyle = .card
    var accent: StickerAccent = .orange
    var enabled: [RunStatKind] = [.distance, .streak]
    /// Remembered overlay transform — pinch scale and normalized center — so
    /// the sticker comes back exactly the size and spot it was last posted at
    /// instead of resetting to a full-size default every time.
    var scale: CGFloat = 1.0
    var posX: CGFloat = 0.5
    var posY: CGFloat = 0.82
    /// Remembered rotation in degrees. Added after v1 — absent from older
    /// configs, which decode to 0 (no tilt). Not clamped: rotation can't push
    /// the sticker off-canvas (the position clamp handles bounds).
    var rotation: CGFloat = 0

    init() {}

    /// The transform keys shipped after v1 — decode every field against the
    /// declared defaults so configs saved by older builds keep their
    /// style/stats choices instead of failing wholesale and resetting, and
    /// clamp the transform so a stale/corrupt value can't render off-canvas.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = StickerConfig()
        style = (try? c.decode(StickerStyle.self, forKey: .style)) ?? defaults.style
        accent = (try? c.decode(StickerAccent.self, forKey: .accent)) ?? defaults.accent
        enabled = (try? c.decode([RunStatKind].self, forKey: .enabled)) ?? defaults.enabled
        scale = ((try? c.decode(CGFloat.self, forKey: .scale)) ?? defaults.scale)
            .clamped(to: Self.scaleRange)
        posX = ((try? c.decode(CGFloat.self, forKey: .posX)) ?? defaults.posX)
            .clamped(to: Self.posXRange)
        posY = ((try? c.decode(CGFloat.self, forKey: .posY)) ?? defaults.posY)
            .clamped(to: Self.posYRange)
        rotation = (try? c.decode(CGFloat.self, forKey: .rotation)) ?? defaults.rotation
    }

    func isOn(_ kind: RunStatKind) -> Bool { enabled.contains(kind) }

    mutating func toggle(_ kind: RunStatKind) {
        if let idx = enabled.firstIndex(of: kind) {
            // Keep at least one stat visible.
            if enabled.count > 1 { enabled.remove(at: idx) }
        } else {
            enabled.append(kind)
        }
    }

    private static let key = "post.sticker.config.v1"
    static func load() -> StickerConfig {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cfg = try? JSONDecoder().decode(StickerConfig.self, from: data) else {
            return StickerConfig()
        }
        return cfg
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: StickerConfig.key)
        }
    }
}

/// A formatted stat ready to render.
struct RunStatDatum: Identifiable {
    let kind: RunStatKind
    let value: String
    var id: String { kind.rawValue }
    var icon: String { kind.icon }
    var label: String { kind.label }
}

// MARK: - Sticker view

/// Config-driven run-stats overlay. Renders only the stats the user enabled, in
/// the chosen style + accent. Used live in the composer (draggable/scalable) and
/// baked into the photo via ImageRenderer.
struct RunStatsStickerView: View, Equatable {
    let input: RunStatsInput
    let config: StickerConfig

    /// The chip/hero stats. `.competition` is deliberately absent — it draws
    /// as its own block below, so a poster who turns it on doesn't lose their
    /// distance to the hero slot.
    private var data: [RunStatDatum] {
        config.enabled.filter { $0 != .competition }.compactMap { input.datum(for: $0) }
    }
    private var accent: Color { config.accent.color }

    /// The competition block's data, or nil when the poster hasn't asked for
    /// one (or is in none today).
    private var competition: CompetitionStickerData? {
        config.isOn(.competition) ? input.competition : nil
    }

    var body: some View {
        Group {
            switch config.style {
            case .card: cardStyle
            case .minimal: minimalStyle
            case .stacked: stackedStyle
            case .streak: streakStyle
            }
        }
        .fixedSize()
    }

    // MARK: Card — brand line, big hero, chip row

    private var cardStyle: some View {
        let hero = data.first
        let rest = Array(data.dropFirst())
        // Chips wrap into rows of 3 so enabling every stat can't grow the
        // sticker wider than the photo canvas.
        let rows = stride(from: 0, to: rest.count, by: 3).map { Array(rest[$0..<min($0 + 3, rest.count)]) }
        return VStack(alignment: .leading, spacing: 8) {
            brandLine
            if let hero { heroValue(hero) }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 14) {
                    ForEach(row) { chip($0) }
                }
            }
            competitionBlock
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(stickerBackground)
    }

    // MARK: Minimal — single inline pill

    private var minimalStyle: some View {
        HStack(spacing: 8) {
            // Every other style carries `brandLine`; without this one, Minimal was
            // just a generic stats pill and didn't read as a Mile A Day sticker.
            MADLogoMark(size: 15, opacity: 0.85, shadow: false)
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 1, height: 12)
            ForEach(Array(data.enumerated()), id: \.element.id) { idx, datum in
                if idx > 0 {
                    Circle().fill(Color.white.opacity(0.4)).frame(width: 3, height: 3)
                }
                HStack(spacing: 4) {
                    Image(systemName: datum.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(accent)
                    Text(datum.value)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                }
            }
            // No room for a podium in a one-line pill, so Minimal states the
            // race instead of drawing it — the same fact, at pill scale.
            if let competition {
                if !data.isEmpty {
                    Circle().fill(Color.white.opacity(0.4)).frame(width: 3, height: 3)
                }
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(trophyGold)
                        .accessibilityHidden(true)
                    Text(competition.standingText ?? competition.name)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
    }

    // MARK: Stacked — vertical label/value list

    private var stackedStyle: some View {
        VStack(alignment: .leading, spacing: 10) {
            brandLine
            ForEach(data) { datum in
                HStack(spacing: 10) {
                    Image(systemName: datum.icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(accent)
                        .frame(width: 20)
                    Text(datum.value)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                    Spacer(minLength: 8)
                    Text(datum.label.uppercased())
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            competitionBlock
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minWidth: 180)
        .background(stickerBackground)
    }

    // MARK: Streak — big flame focus

    private var streakStyle: some View {
        let streakDatum = input.datum(for: .streak)
        let others = data.filter { $0.kind != .streak }
        return VStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(
                    LinearGradient(colors: [accent, accent.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                )
            Text(streakDatum?.value ?? input.datum(for: .distance)?.value ?? "")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
            Text(streakDatum != nil ? "DAY STREAK" : "TODAY")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.6)
                .foregroundColor(.white.opacity(0.6))
            if !others.isEmpty {
                HStack(spacing: 12) {
                    ForEach(others.prefix(3)) { datum in
                        HStack(spacing: 4) {
                            Image(systemName: datum.icon)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(accent)
                            Text(datum.value)
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(.top, 2)
            }
            competitionBlock
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(stickerBackground)
    }

    // MARK: Shared pieces

    /// The app's trophy gold — the same amber every medal and streak-milestone
    /// surface uses for "achievement", so a race on a photo reads like one.
    private var trophyGold: Color { MADTheme.Colors.warning }

    /// The race, drawn: the competition's name, the poster's standing, and the
    /// podium they're on with their own row lit. Three rows, because a sticker
    /// sits on a photo — the poster is always one of them, spliced over the
    /// third when they're further down (`Competition.podium`), so this can
    /// never show a leaderboard the poster isn't on.
    @ViewBuilder
    private var competitionBlock: some View {
        if let competition {
            VStack(alignment: .leading, spacing: 6) {
                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: 1)
                    .padding(.bottom, 1)
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(trophyGold)
                        .accessibilityHidden(true)
                    Text(competition.name.uppercased())
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let standing = competition.standingText {
                        Text(standing.uppercased())
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(0.6)
                            .foregroundColor(trophyGold)
                            .layoutPriority(1)
                    }
                }
                if let subtitle = competition.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
                ForEach(competition.rows) { row in
                    standingRow(row)
                    if !row.members.isEmpty {
                        memberStrip(row.members)
                    }
                }
            }
            .padding(.top, 2)
            // The block carries the sticker's width when it's shown: its rows
            // spread a name against a score, which needs a definite one, and
            // `streakStyle` centres its children with no minWidth of its own.
            .frame(minWidth: 190, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(competition.inlineText)
        }
    }

    private func standingRow(_ row: CompetitionStickerData.Row) -> some View {
        HStack(spacing: 8) {
            Text("\(row.place)")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundColor(row.isMe ? trophyGold : .white.opacity(0.45))
                .monospacedDigit()
                .frame(width: 14, alignment: .leading)
            if row.avatarURL != nil {
                stickerFace(row.avatarURL, row.name, size: 17)
            }
            Text(row.name)
                .font(.system(size: 13, weight: row.isMe ? .heavy : .semibold, design: .rounded))
                .foregroundColor(.white.opacity(row.isMe ? 1 : 0.72))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 10)
            Text(row.score)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(.white.opacity(row.isMe ? 1 : 0.72))
                .monospacedDigit()
                .layoutPriority(1)
        }
        // The poster's own row, when it jumped a gap to get here, is drawn as
        // a lit pill: without it "1, 2, 9" reads as a broken leaderboard
        // rather than as the poster's real place.
        .padding(.horizontal, row.isMe ? 6 : 0)
        .padding(.vertical, row.isMe ? 3 : 0)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(trophyGold.opacity(row.isMe ? 0.18 : 0))
        )
        .padding(.leading, row.isMe ? -6 : 0)
    }

    /// Who is in this team and what they put in.
    ///
    /// A team row's score is the TEAM's — derived server-side from combined
    /// miles — so on its own it names nobody and explains nothing about who
    /// carried it. These are the numbers that actually add up.
    private func memberStrip(_ members: [CompetitionStickerData.Member]) -> some View {
        HStack(spacing: 9) {
            ForEach(members) { member in
                HStack(spacing: 4) {
                    stickerFace(member.avatarURL, member.name, size: 15)
                    Text(member.name)
                        .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(0.62))
                    Text(member.value)
                        .font(.system(size: 9.5, weight: .black, design: .rounded))
                        .foregroundColor(.white.opacity(0.92))
                        .monospacedDigit()
                }
            }
        }
        .lineLimit(1)
        .padding(.leading, 22)
        .padding(.top, 1)
        .padding(.bottom, 2)
    }

    /// A face on the sticker.
    ///
    /// Cache-only (`RouteAvatarImageLoader.cachedImage`), because this whole
    /// overlay is baked by `ImageRenderer` at post time and cannot wait on a
    /// download — an `AsyncImage` here renders empty into the photo. Initials
    /// are the miss behaviour; `PostComposerViewModel` warms the cache when it
    /// loads the competitions, so the miss is rare rather than normal.
    private func stickerFace(_ imageURL: String?, _ name: String, size: CGFloat) -> some View {
        Group {
            if let image = RouteAvatarImageLoader.cachedImage(for: imageURL) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.16)
                    Text(AvatarView.initials(for: name))
                        .font(.system(size: size * 0.46, weight: .black, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        .accessibilityHidden(true)
    }

    private var brandLine: some View {
        MADLogoMark(size: 26, opacity: 0.9, shadow: false)
    }

    private func heroValue(_ datum: RunStatDatum) -> some View {
        // The first enabled stat is rendered large. Distance splits the unit out.
        Group {
            if datum.kind == .distance {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(input.distance.milesText)
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                    Text("mi")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                }
            } else {
                Text(datum.value)
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
            }
        }
    }

    private func chip(_ datum: RunStatDatum) -> some View {
        HStack(spacing: 5) {
            Image(systemName: datum.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(datum.value)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                Text(datum.label.uppercased())
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .tracking(0.8)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    private var stickerBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.black.opacity(0.42))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
    }

    // MARK: Formatters

    static func paceText(_ secPerMile: Double) -> String {
        let m = Int(secPerMile) / 60
        let s = Int(secPerMile) % 60
        return String(format: "%d:%02d", m, s)
    }

    static func durationText(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

/// Compact, glanceable stat chips rendered from a post's `stats_snapshot` —
/// shown on feed cards so a friend's streak and run read clearly even when the
/// photo overlay is small or turned off. Renders nothing when there's no data.
struct PostStatStrip: View {
    let stats: PostStats
    /// When shown over a photo (story viewer), use a darker chip + shadow so the
    /// text stays legible on any image. Default keeps the feed-card appearance.
    var onPhoto: Bool = false
    /// The entry's (linked workout's) feed role, when the server sent it —
    /// reframes the distance chip so a post-goal stroll never reads like it
    /// was the whole day: "extra" renders as green "+0.14 mi extra" (the
    /// goal is already banked; this is bonus), "daily_mile" as the day's
    /// goal achievement. Nil (old servers, unlinked posts) keeps the plain
    /// chip.
    var feedRole: String? = nil

    private struct Item: Identifiable { let id = UUID(); let icon: String; let text: String; let tint: Color }

    private var items: [Item] {
        var out: [Item] = []
        if let s = stats.streak, s > 0 {
            out.append(Item(icon: "flame.fill", text: "\(s) day streak", tint: .orange))
        }
        if let d = stats.distance, d > 0 {
            let miles = String(format: "%.2f", d)
            if feedRole == "extra" {
                out.append(Item(icon: "plus.circle.fill", text: "+\(miles) mi extra", tint: .green))
            } else if feedRole == "daily_mile" {
                out.append(Item(icon: "checkmark.circle.fill", text: "\(miles) mi · goal", tint: .green))
            } else {
                out.append(Item(icon: "figure.run", text: "\(miles) mi", tint: .white.opacity(0.85)))
            }
        }
        if let p = stats.pace, p > 0 {
            out.append(Item(icon: "speedometer", text: "\(RunStatsStickerView.paceText(p)) /mi", tint: .white.opacity(0.85)))
        }
        return out
    }

    var body: some View {
        if !items.isEmpty {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    HStack(spacing: 4) {
                        Image(systemName: item.icon).font(.system(size: 10, weight: .bold))
                        Text(item.text).font(.system(size: 11, weight: .heavy, design: .rounded)).monospacedDigit()
                    }
                    .foregroundColor(item.tint)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(onPhoto ? Color.black.opacity(0.45) : Color.white.opacity(0.06)))
                    .shadow(color: onPhoto ? .black.opacity(0.5) : .clear, radius: onPhoto ? 4 : 0)
                }
            }
        }
    }
}
