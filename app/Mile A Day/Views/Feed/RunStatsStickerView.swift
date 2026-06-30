import SwiftUI

// MARK: - Stat kinds, styles, accents

/// A single run statistic the user can choose to show on their post.
enum RunStatKind: String, CaseIterable, Identifiable, Codable {
    case distance, pace, duration, streak, calories, steps, date
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
        }
    }
}

/// Visual templates for the overlay. The user can flip between them live.
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
    var icon: String {
        switch self {
        case .card: return "rectangle.fill"
        case .minimal: return "minus.rectangle.fill"
        case .stacked: return "list.bullet.rectangle.fill"
        case .streak: return "flame.fill"
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

/// User-controlled overlay configuration. Persisted between sessions so the
/// composer remembers how someone likes to show their run.
struct StickerConfig: Equatable, Codable {
    var style: StickerStyle = .card
    var accent: StickerAccent = .orange
    var enabled: [RunStatKind] = [.distance, .streak]

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
struct RunStatsStickerView: View {
    let input: RunStatsInput
    let config: StickerConfig

    private var data: [RunStatDatum] {
        config.enabled.compactMap { input.datum(for: $0) }
    }
    private var accent: Color { config.accent.color }

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
        return VStack(alignment: .leading, spacing: 8) {
            brandLine
            if let hero { heroValue(hero) }
            if !rest.isEmpty {
                HStack(spacing: 14) {
                    ForEach(rest) { chip($0) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(stickerBackground)
    }

    // MARK: Minimal — single inline pill

    private var minimalStyle: some View {
        HStack(spacing: 8) {
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
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(stickerBackground)
    }

    // MARK: Shared pieces

    private var brandLine: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .font(.system(size: 11, weight: .black))
                .foregroundColor(accent)
            Text("MILE A DAY")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.85))
        }
    }

    private func heroValue(_ datum: RunStatDatum) -> some View {
        // The first enabled stat is rendered large. Distance splits the unit out.
        Group {
            if datum.kind == .distance {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.2f", input.distance))
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

    private struct Item: Identifiable { let id = UUID(); let icon: String; let text: String; let tint: Color }

    private var items: [Item] {
        var out: [Item] = []
        if let s = stats.streak, s > 0 {
            out.append(Item(icon: "flame.fill", text: "\(s) day streak", tint: .orange))
        }
        if let d = stats.distance, d > 0 {
            out.append(Item(icon: "figure.run", text: "\(String(format: "%.2f", d)) mi", tint: .white.opacity(0.85)))
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
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                }
            }
        }
    }
}
