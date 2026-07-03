import SwiftUI

/// Branded 4:5 stats card used as the auto feed image for a run that has no
/// photo and no GPS route (e.g. a treadmill mile).
///
/// Laid out at DESIGN size (360×450 — phone-card proportions) and rendered to
/// 1080×1350 by `RunPostService.renderStatsCard` with `scale = 3`. Never
/// render this at a 1080-wide frame with scale 1: point sizes would become
/// raw pixels and everything displays at a third of the intended size (the
/// original "tiny stats card" bug).
struct RunStatsCardView: View {
    /// The design-space size the card is laid out against; render scale is
    /// derived from it so the flattened image is exactly 1080×1350.
    static let designSize = CGSize(width: 360, height: 450)

    let stats: RunStatsInput
    /// "running" / "walking" — drives the icon + accent.
    let workoutType: String

    private var icon: String { ActivityCardView.icon(workoutType) }
    private var accent: Color { ActivityCardView.color(workoutType) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.09, blue: 0.12), .black],
                startPoint: .top, endPoint: .bottom
            )
            // Accent glow behind the hero number.
            RadialGradient(colors: [accent.opacity(0.4), .clear],
                           center: .init(x: 0.5, y: 0.3), startRadius: 10, endRadius: 240)

            VStack(spacing: 0) {
                // Header: what + when.
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .bold))
                        Text(ActivityCardView.verb(workoutType).uppercased())
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .tracking(1.5)
                    }
                    .foregroundColor(accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(accent.opacity(0.15)))

                    Spacer()

                    if let date = stats.dateText, !date.isEmpty {
                        Text(date)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.55))
                    }
                }

                Spacer()

                // Hero: the distance owns the card.
                Image(systemName: icon)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [.white, accent],
                                                    startPoint: .top, endPoint: .bottom))
                    .shadow(color: accent.opacity(0.5), radius: 14)
                    .padding(.bottom, 8)

                Text(String(format: "%.2f", stats.distance))
                    .font(.system(size: 104, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                Text("MILES")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(8)
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                // Stat tiles: readable at feed size, not confetti chips.
                // Plain stacks, not LazyVGrid — lazy containers can render
                // empty through ImageRenderer.
                let tiles = statTiles
                if !tiles.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(Array(stride(from: 0, to: tiles.count, by: 2)), id: \.self) { row in
                            HStack(spacing: 10) {
                                statTile(tiles[row])
                                if row + 1 < tiles.count {
                                    statTile(tiles[row + 1])
                                }
                            }
                        }
                    }
                }

                // Brand row — kept above the carousel's page-dot zone.
                HStack(spacing: 6) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(accent)
                    Text("Mile A Day")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(.top, 18)
                .padding(.bottom, 26)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
        }
        .frame(width: Self.designSize.width, height: Self.designSize.height)
    }

    private struct StatTile {
        let icon: String
        let label: String
        let value: String
        var tint: Color = .white
    }

    private var statTiles: [StatTile] {
        var out: [StatTile] = []
        if let p = stats.paceSecondsPerMile, p > 0 {
            out.append(StatTile(icon: "speedometer", label: "PACE",
                                value: "\(RunStatsStickerView.paceText(p)) /mi"))
        }
        if let d = stats.durationSeconds, d > 0 {
            out.append(StatTile(icon: "clock.fill", label: "TIME",
                                value: RunStatsStickerView.durationText(d)))
        }
        if let c = stats.calories, c > 0 {
            out.append(StatTile(icon: "bolt.fill", label: "CALORIES",
                                value: "\(Int(c.rounded()))"))
        } else if let s = stats.steps, s > 0 {
            out.append(StatTile(icon: "shoeprints.fill", label: "STEPS",
                                value: s.formatted(.number.grouping(.automatic))))
        }
        if let s = stats.streak, s > 0 {
            out.append(StatTile(icon: "flame.fill", label: "STREAK",
                                value: "\(s) days", tint: .orange))
        }
        return out
    }

    private func statTile(_ tile: StatTile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: tile.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(tile.tint == .white ? accent : tile.tint)
                Text(tile.label)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.5))
            }
            Text(tile.value)
                .font(.system(size: 21, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(tile.tint)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }
}

/// Transparent overlay composited onto the auto ROUTE image: activity + date
/// up top, and a scrimmed stats band (big distance, pace/time chips, streak,
/// brand) along the bottom — so a route post carries its numbers instead of
/// being a bare map. Same design-space/scale contract as RunStatsCardView.
struct RouteStatsOverlayView: View {
    let stats: RunStatsInput
    let workoutType: String

    private var accent: Color { ActivityCardView.color(workoutType) }

    var body: some View {
        VStack(spacing: 0) {
            // Top: activity + date chips over the map.
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: ActivityCardView.icon(workoutType))
                        .font(.system(size: 13, weight: .bold))
                    Text(ActivityCardView.verb(workoutType).uppercased())
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(1.5)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.black.opacity(0.6)))

                Spacer()

                if let date = stats.dateText, !date.isEmpty {
                    Text(date)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                }
            }
            .padding(16)

            Spacer()

            // Bottom: stats band on a scrim so it reads over any map colors.
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.2f", stats.distance))
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                    Text("MI")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                    Spacer()
                    if let s = stats.streak, s > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("\(s)")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .monospacedDigit()
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                    }
                }

                HStack(spacing: 8) {
                    if let p = stats.paceSecondsPerMile, p > 0 {
                        scrimChip("speedometer", "\(RunStatsStickerView.paceText(p)) /mi")
                    }
                    if let d = stats.durationSeconds, d > 0 {
                        scrimChip("clock.fill", RunStatsStickerView.durationText(d))
                    }
                    Spacer()
                    HStack(spacing: 5) {
                        Image(systemName: "figure.run.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(accent)
                        Text("Mile A Day")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 44)
            // Clear of the carousel page dots.
            .padding(.bottom, 30)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55), .black.opacity(0.85)],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
        .frame(width: RunStatsCardView.designSize.width,
               height: RunStatsCardView.designSize.height)
    }

    private func scrimChip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .monospacedDigit()
        }
        .foregroundColor(.white)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.black.opacity(0.55)))
    }
}
