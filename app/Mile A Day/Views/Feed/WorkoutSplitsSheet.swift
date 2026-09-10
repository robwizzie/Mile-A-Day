import SwiftUI

/// SPLITS, the second chip on a card's media — dark glass beside the filled
/// FLYOVER pill, so the two read as "the primary thing" and "the detail".
/// Drawn only when the post's workout actually carries splits.
struct SplitsChipButton: View {
    /// The workout's colour — the glyph's tint.
    var accent: Color = MADTheme.Colors.madRed
    let action: () -> Void

    var body: some View {
        Button {
            MADHaptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(accent)
                Text("SPLITS")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundColor(.white)
                    // Constant text, so a published width can't run away —
                    // and without it a squeezed row wraps the word inside its
                    // own capsule instead of the row re-arranging.
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            // Lifted off the card's ground, not the black glass it wore when
            // it sat ON a photo: both call sites moved into the control row
            // under the media, and a 55%-black capsule on a dark card reads as
            // a hole punched in it rather than a button.
            .background(Capsule().fill(Color.white.opacity(0.10)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show mile splits")
    }
}

/// A workout's per-mile splits, opened from a post or a raw workout card —
/// indoor or outdoor alike, since splits are pace and time, not location
/// (the server sends them regardless of route sharing).
///
/// Reads top to bottom the way the run happened: the headline numbers, the
/// pace wave (the indoor card's own strip, given room), a fastest-mile chip,
/// then one bar per mile in the same recipe the workout detail screen draws.
/// Bars are normalised by PACE, not time, so a partial last mile sits where
/// its speed puts it rather than reading as the fastest split of the day;
/// only full miles can be "fastest", because a 0.06-mile tail's pace is
/// noise.
struct WorkoutSplitsSheet: View {
    /// One person's leg of the walk. A solo card has exactly one of these;
    /// a buddy walk has the author plus everyone credited on the card.
    ///
    /// Colour comes from the CARD's route legend, so the person you tap here
    /// is the person whose line you were just looking at — the two surfaces
    /// naming the same walker differently is what makes a crew card unreadable.
    struct Walker: Identifiable {
        let id: String
        let name: String
        let color: Color
        let distance: Double?
        let durationSeconds: Double?
        let movingSeconds: Double?
        let bars: [WorkoutSplitBar]
        /// The pace the server already computed for this leg — single-workout
        /// cards carry it in `stats_snapshot`. Wins over the derived figure so
        /// the sheet can never disagree with the card that opened it.
        var servedPace: Double? = nil

        /// Display pace under the shared >=50%-of-elapsed rule, so a crew
        /// member's pace can't be computed differently from the author's.
        var paceSecondsPerMile: Double? {
            if let servedPace, servedPace > 0 { return servedPace }
            guard let distance, distance > 0 else { return nil }
            return DisplayPace.secondsPerMile(
                distanceMiles: distance,
                movingSeconds: movingSeconds,
                elapsedSeconds: durationSeconds
            )
        }
    }

    let walkers: [Walker]
    let workoutType: String?
    /// nil = unknown; the chip simply doesn't draw (routeless is never
    /// "indoor" on its own).
    let isIndoor: Bool?
    /// The walk's combined figures, when it was a walk together — the number
    /// the card headlines, restated here so the per-person rows below it are
    /// visibly parts of a whole.
    var groupDistance: Double? = nil

    /// Whoever the sheet opens on: the viewer if they were on the walk, else
    /// the author. Seeded by the caller, then owned by the picker.
    @State private var selectedId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        walkers: [Walker],
        workoutType: String?,
        isIndoor: Bool?,
        groupDistance: Double? = nil,
        initialWalkerId: String? = nil
    ) {
        self.walkers = walkers
        self.workoutType = workoutType
        self.isIndoor = isIndoor
        self.groupDistance = groupDistance
        _selectedId = State(
            initialValue: initialWalkerId ?? walkers.first?.id ?? ""
        )
    }

    /// The one-person form every non-buddy card uses. Kept so the ordinary
    /// call sites read exactly as they did.
    init(
        bars: [WorkoutSplitBar],
        stats: PostStats?,
        workoutType: String?,
        isIndoor: Bool?,
        ownerName: String
    ) {
        self.init(
            walkers: [
                Walker(
                    id: "owner",
                    name: ownerName,
                    color: ActivityCardView.color(workoutType),
                    distance: stats?.distance,
                    durationSeconds: stats?.duration,
                    movingSeconds: nil,
                    bars: bars,
                    servedPace: stats?.pace
                )
            ],
            workoutType: workoutType,
            isIndoor: isIndoor
        )
    }

    private var walker: Walker {
        walkers.first { $0.id == selectedId } ?? walkers[0]
    }
    private var bars: [WorkoutSplitBar] { walker.bars }
    private var pace: Double? { walker.paceSecondsPerMile }
    private var isCrew: Bool { walkers.count > 1 }

    private var accent: Color { ActivityCardView.color(workoutType) }
    private var verb: String { ActivityCardView.verb(workoutType, paceSecondsPerMile: pace) }
    private var icon: String { ActivityCardView.icon(workoutType, paceSecondsPerMile: pace) }
    private var noun: String { PostCardView.activityNoun(workoutType, pace: pace) }

    /// Same threshold the flyover's split toasts use for "a whole mile".
    private static let fullMile = 0.95

    private func isFull(_ bar: WorkoutSplitBar) -> Bool {
        (bar.partialDistance ?? 1) >= Self.fullMile
    }

    private var fastest: WorkoutSplitBar? {
        let full = bars.filter(isFull)
        guard full.count >= 2 else { return nil }
        return full.min { $0.paceSeconds < $1.paceSeconds }
    }

    private var slowest: WorkoutSplitBar? {
        let full = bars.filter(isFull)
        guard full.count >= 2 else { return nil }
        return full.max { $0.paceSeconds < $1.paceSeconds }
    }

    private var fastestPace: Double { bars.map(\.paceSeconds).min() ?? 0 }
    private var slowestPace: Double { bars.map(\.paceSeconds).max() ?? 0 }

    /// The fastest split fills the bar; the slowest reads at 35% so every
    /// mile stays visible — the workout detail screen's rule.
    private func fraction(_ bar: WorkoutSplitBar) -> CGFloat {
        guard slowestPace > fastestPace else { return 1 }
        let normalized = (bar.paceSeconds - fastestPace) / (slowestPace - fastestPace)
        return CGFloat(1 - normalized * 0.65)
    }

    /// The split's own time. The wire carries pace and distance; for a full
    /// mile the two are the same number, for a partial it's pace × distance.
    private func splitSeconds(_ bar: WorkoutSplitBar) -> Double {
        bar.paceSeconds * (bar.partialDistance ?? 1)
    }

    private func label(_ bar: WorkoutSplitBar) -> String {
        if let d = bar.partialDistance, d < Self.fullMile {
            return "Last \(d.milesText) mi"
        }
        return "Mile \(bar.mile)"
    }

    /// "Rob · Walk · 19:30 · 18:24 /mi" — whichever of those the run has.
    private var detailLine: String {
        var parts = [walker.name, noun]
        if let d = walker.durationSeconds, d > 0 {
            parts.append(RunStatsStickerView.durationText(d))
        }
        if let p = pace, p > 0 {
            parts.append("\(RunStatsStickerView.paceText(p)) /mi")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                    header
                    if isCrew { crewPicker }
                    headline

                    if bars.isEmpty {
                        noSplitsNote
                    } else {
                        if bars.count >= 2 {
                            PaceWaveStrip(bars: bars, accent: walker.color, height: 64)
                                .padding(.vertical, MADTheme.Spacing.xs)
                        }

                        if let fastest, let slowest, fastest.id != slowest.id {
                            summaryChips(fastest: fastest, slowest: slowest)
                        }

                        rows

                        Text("Pace per mile, from the workout's own splits.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.top, MADTheme.Spacing.xs)
                    }
                }
                // Switching walker changes every number on the screen, so it
                // gets a transition — without one the whole sheet appears to
                // twitch and it isn't obvious that a tap did anything.
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: selectedId)
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.top, MADTheme.Spacing.lg)
                .padding(.bottom, MADTheme.Spacing.xl)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12, weight: .bold))
                Text(verb.uppercased())
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.4)
            }
            .foregroundColor(accent)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(Capsule().fill(accent.opacity(0.15)))

            if let isIndoor {
                Text(isIndoor ? "INDOOR" : "OUTDOOR")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }

            Spacer(minLength: 0)

            Text("SPLITS")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.6)
                .foregroundColor(.white.opacity(0.45))
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text((walker.distance ?? 0).milesText)
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                Text("mi")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
            Text(detailLine)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(1)
            // The whole walk, under one person's share of it — so the big
            // number reads as a part rather than as the total it isn't.
            if isCrew, let groupDistance, groupDistance > 0 {
                Text("\(groupDistance.distanceFormatted) between the \(walkers.count) of you")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(accent)
                    .padding(.top, 2)
            }
        }
    }

    /// Who to look at. One pill per walker in their own route colour, with
    /// their distance on it — so "how far did each of us go" is answered by
    /// the picker itself, before anyone taps anything.
    ///
    /// A horizontal rail rather than a segmented control: names are data and
    /// a crew can be five people, which is exactly the case that squeezes a
    /// segmented control's labels to nothing.
    private var crewPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(walkers) { person in
                    Button {
                        MADHaptics.tap()
                        selectedId = person.id
                    } label: {
                        walkerPill(person)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(walkerAccessibility(person))
                    .accessibilityAddTraits(person.id == selectedId ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 2)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func walkerPill(_ person: Walker) -> some View {
        let selected = person.id == selectedId
        return HStack(spacing: 6) {
            Circle()
                .fill(person.color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(person.name)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(selected ? .white : .white.opacity(0.65))
                .lineLimit(1)
            if let distance = person.distance, distance > 0 {
                Text(distance.distanceFormatted)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(selected ? .white.opacity(0.75) : .white.opacity(0.45))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(person.color.opacity(selected ? 0.22 : 0.08))
        )
        .overlay(
            Capsule().strokeBorder(person.color.opacity(selected ? 0.7 : 0), lineWidth: 1.5)
        )
    }

    private func walkerAccessibility(_ person: Walker) -> String {
        var parts = [person.name]
        if let distance = person.distance, distance > 0 {
            parts.append(distance.distanceFormatted)
        }
        parts.append(person.bars.isEmpty ? "no splits" : "\(person.bars.count) splits")
        return parts.joined(separator: ", ")
    }

    /// A crew member whose phone hasn't handed us splits — an indoor leg, a
    /// walk that hasn't synced, or an older upload. Said plainly, because an
    /// empty chart under someone's name reads as the app losing their walk.
    private var noSplitsNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white.opacity(0.35))
                .accessibilityHidden(true)
            Text(walker.distance == nil
                 ? "\(walker.name) hasn't synced this walk yet."
                 : "No mile splits for \(walker.name)'s walk.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, MADTheme.Spacing.sm)
    }

    private func summaryChips(fastest: WorkoutSplitBar, slowest: WorkoutSplitBar) -> some View {
        let spread = max(0, slowest.paceSeconds - fastest.paceSeconds)
        return HStack(spacing: MADTheme.Spacing.sm) {
            summaryChip(
                icon: "bolt.fill",
                title: "FASTEST",
                value: "Mile \(fastest.mile) · \(RunStatsStickerView.paceText(fastest.paceSeconds))",
                tint: MADTheme.Colors.success
            )
            summaryChip(
                icon: "arrow.left.and.right",
                title: "SPREAD",
                value: "\(Int(spread.rounded()))s between miles",
                tint: .white.opacity(0.7)
            )
        }
    }

    private func summaryChip(icon: String, title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.45))
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var rows: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            ForEach(bars) { bar in
                SplitBarRow(
                    mile: bar.mile,
                    timeLabel: RunStatsStickerView.durationText(splitSeconds(bar)),
                    fraction: fraction(bar),
                    isFastest: bar.id == fastest?.id,
                    color: walker.color,
                    label: label(bar),
                    detailLabel: "\(RunStatsStickerView.paceText(bar.paceSeconds)) /mi",
                    dimmed: !isFull(bar)
                )
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }
}
