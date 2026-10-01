import SwiftUI

/// The OUTDOOR / UNKNOWN routeless scene: a walk whose map isn't on this card.
///
/// Stats-first — the distance is the hero, pace and time under it — over a
/// mile-by-mile RIBBON: one segment per mile (the last one as long as the
/// partial mile actually was), each tinted by that mile's pace from the
/// splits, with the author's badge riding it start to finish. It reads as "a
/// walk, this far, this fast" without pretending to be a map and without
/// saying why there isn't one: a stealth walk, a maps-off walk and a device
/// that recorded no trace must look identical to a friend. Never a track and
/// never "laps" — that's the indoor scene, and an outdoor walk drawn as
/// "8.8 LAPS" contradicts itself.
///
/// Fun authors get their Flamey at the finish line cheering and a chunkier,
/// glowing ribbon; Modern authors get a hairline road and a flat accent
/// ribbon. Motion is one reveal (a mask's `scaleEffect` and the badge's
/// offset — transforms only) plus the cheerleader's loops; Reduce Motion and
/// `still` draw the finished frame.
struct DistanceRibbonCard: View {
    let stats: PostStats
    let workoutType: String?
    var splits: [WorkoutSplitBar] = []
    var avatar: RouteArtAvatar? = nil
    var style: RoutelessCardStyle = .modern
    var still: Bool = false

    @State private var revealed = false
    @State private var avatarImage: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var effectiveStill: Bool { still || reduceMotion }

    private var accent: Color { ActivityCardView.color(workoutType) }
    private var distance: Double { max(0, stats.distance ?? 0) }
    private var revealDuration: Double { min(2.2, 0.9 + distance * 0.3) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoutelessHeaderRow(style: style, accent: accent, workoutType: workoutType,
                               pace: stats.pace)
            Spacer(minLength: 6)
            RoutelessDistanceHeadline(style: style, distance: distance, size: 66,
                                      revealed: revealed, still: effectiveStill,
                                      duration: revealDuration)
            RoutelessStatPair(style: style, accent: accent, stats: stats, alignment: .leading)
                .padding(.top, 4)
            Spacer(minLength: 10)
            ribbon
                .frame(height: style.isFun ? 98 : 64)
        }
        .padding(16)
        .task {
            guard !effectiveStill, !revealed else { return }
            try? await Task.sleep(for: .milliseconds(300))
            revealed = true
        }
        .task(id: avatar?.imageURL) {
            guard let url = avatar?.imageURL, !url.isEmpty else { return }
            avatarImage = await RouteAvatarImageLoader.loadImage(for: url)
        }
    }

    // MARK: The ribbon

    private struct Segment: Identifiable {
        let id: Int          // 0-based mile index
        let from: Double     // miles
        let to: Double
        let paceFraction: Double?  // 1 = fastest mile, 0 = slowest; nil = no split
        let pace: Double?
        var isPartial: Bool { to - from < 0.95 }
    }

    private var segments: [Segment] {
        guard distance > 0 else { return [] }
        let count = max(1, Int(ceil(distance - 0.005)))
        let byMile = Dictionary(splits.map { ($0.mile, $0) }, uniquingKeysWith: { a, _ in a })
        let paces = splits.map(\.paceSeconds)
        let fastest = paces.min() ?? 0
        let slowest = paces.max() ?? 0
        return (0..<count).map { i in
            let split = byMile[i + 1]
            var fraction: Double? = nil
            if let split {
                fraction = slowest > fastest ? 1 - (split.paceSeconds - fastest) / (slowest - fastest) : 1
            }
            return Segment(id: i, from: Double(i), to: min(Double(i + 1), distance),
                           paceFraction: fraction, pace: split?.paceSeconds)
        }
    }

    private var ribbon: some View {
        GeometryReader { geo in
            let fun = style.isFun
            let thickness: CGFloat = fun ? 14 : 10
            // Fun leaves the finish free for Flamey to stand past the line.
            let finishRoom: CGFloat = fun ? 56 : 12
            let length = max(1, geo.size.width - finishRoom - 4)
            let y: CGFloat = fun ? 56 : 22
            let segs = segments
            let gap: CGFloat = segs.count > 12 ? 1 : 3
            let labelEvery = max(1, Int(ceil(Double(segs.count) / 7)))
            let progress: CGFloat = (effectiveStill || revealed) ? 1 : 0
            let x: (Double) -> CGFloat = { miles in
                distance > 0 ? CGFloat(miles / distance) * length : 0
            }

            ZStack(alignment: .topLeading) {
                // The road — the whole distance, unfilled.
                Capsule()
                    .fill(Color.white.opacity(fun ? 0.08 : 0.06))
                    .frame(width: length, height: thickness)
                    .offset(x: 2, y: y - thickness / 2)

                // One segment per mile, pace-tinted, revealed by a mask that
                // scales across — a transform, so the reveal costs nothing.
                ZStack(alignment: .topLeading) {
                    ForEach(segs) { seg in
                        let x0 = x(seg.from) + (seg.id == 0 ? 0 : gap / 2)
                        let x1 = x(seg.to) - (seg.id == segs.count - 1 ? 0 : gap / 2)
                        RoundedRectangle(cornerRadius: thickness / 2, style: .continuous)
                            .fill(segmentFill(seg, fun: fun))
                            .frame(width: max(2, x1 - x0), height: thickness)
                            .offset(x: 2 + x0, y: y - thickness / 2)
                    }
                }
                // Offsets don't size a ZStack: pin it to the ribbon's box so
                // the mask below measures the whole road, not one segment.
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .shadow(color: fun ? accent.opacity(0.55) : .clear, radius: 6)
                .mask(
                    Rectangle()
                        .frame(width: length + 4, height: geo.size.height)
                        .scaleEffect(x: max(progress, 0.001), anchor: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(effectiveStill ? nil : .easeOut(duration: revealDuration), value: revealed)
                )

                // Mile labels under their segments: the split's pace when we
                // have it, and which mile it was.
                ForEach(segs) { seg in
                    if seg.id % labelEvery == 0 || seg.id == segs.count - 1 {
                        let width = x(seg.to) - x(seg.from)
                        if width >= 34 {
                            segmentLabel(seg)
                                .frame(width: width)
                                .offset(x: 2 + x(seg.from), y: y + thickness / 2 + 6)
                        }
                    }
                }

                // Start dot.
                Circle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 6, height: 6)
                    .offset(x: 2 - 3, y: y - 3)

                if case .fun(let look, let name) = style {
                    // Past the finish line, cheering the walker home.
                    TrackCheerleader(look: look, name: name, size: 48, still: effectiveStill)
                        .frame(width: 76)
                        .position(x: geo.size.width - 24, y: y - 22)
                }

                // The rider — rests at the finish.
                rider(fun: fun)
                    .position(x: 2, y: y)
                    .offset(x: length * progress)
                    .animation(effectiveStill ? nil : .easeOut(duration: revealDuration), value: revealed)
            }
        }
    }

    private func segmentFill(_ seg: Segment, fun: Bool) -> some ShapeStyle {
        // Faster miles burn brighter; with no split every mile is the same.
        let strength = seg.paceFraction.map { 0.45 + 0.55 * $0 } ?? 0.9
        let partialDim = seg.isPartial ? 0.75 : 1
        let base = accent.opacity(strength * partialDim)
        return LinearGradient(colors: fun ? [base, accent.opacity(min(1, strength + 0.2) * partialDim)] : [base, base],
                              startPoint: .leading, endPoint: .trailing)
    }

    private func segmentLabel(_ seg: Segment) -> some View {
        let type = RoutelessType(style: style)
        let mileLabel = seg.isPartial ? String(format: "+%.2f", seg.to - seg.from) : "MI \(seg.id + 1)"
        return VStack(spacing: 1) {
            if let pace = seg.pace, !seg.isPartial {
                Text(RunStatsStickerView.paceText(pace))
                    .font(.system(size: 11, weight: type.valueWeight, design: type.design))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.85))
            }
            Text(mileLabel)
                .font(.system(size: 8, weight: .heavy, design: type.design))
                .tracking(1)
                .foregroundColor(.white.opacity(0.42))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    @ViewBuilder
    private func rider(fun: Bool) -> some View {
        if let avatar {
            RouteAvatarBadge(
                name: avatar.name,
                image: avatarImage ?? RouteAvatarImageLoader.cachedImage(for: avatar.imageURL),
                size: fun ? 26 : 22, ring: accent)
        } else {
            Circle()
                .fill(.white)
                .frame(width: 10, height: 10)
                .shadow(color: accent, radius: 5)
        }
    }
}
