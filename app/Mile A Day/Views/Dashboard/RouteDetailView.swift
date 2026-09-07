import SwiftUI
import HealthKit
import CoreLocation

/// Every walk on one route — the answer to the question the repeats banner
/// raises. "Your 6th time on this route" is only interesting if you can then
/// ask what the other five were, and until now it was a dead sentence.
///
/// Reached from two places, and they must land on the same screen: the Routes
/// tab's rows, and the banner itself on a workout's detail sheet.
struct RouteDetailView: View {
    let summary: RouteSummary
    @ObservedObject var healthManager: HealthKitManager

    @Environment(\.dismiss) private var dismiss
    @State private var order: Order = .fastest
    @State private var flyoverLaunch: FlyoverLaunch?
    /// The HKWorkouts behind the outings, fetched once so a row can open the
    /// real detail sheet. Until they land the rows still draw — they just
    /// aren't tappable yet, which is honest rather than a dead tap.
    @State private var workoutsById: [String: HKWorkout] = [:]
    @State private var pager: RouteWorkoutSelection?

    enum Order: String, CaseIterable, Identifiable {
        case fastest = "Fastest"
        case recent = "Recent"
        var id: String { rawValue }
    }

    private var accent: Color { MADTheme.workoutColor(summary.workoutType ?? "walking") }

    private var owner: RouteArtAvatar {
        RouteArtAvatar(
            name: UserManager.shared.currentUser.name,
            imageURL: UserManager.shared.currentUser.profileImageUrl
        )
    }

    private var listed: [RouteOuting] {
        order == .fastest ? summary.ranked : summary.outings
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: MADTheme.Spacing.md) {
                        mapCard
                        statsCard
                        outingsCard
                    }
                    .padding(.horizontal, MADTheme.Spacing.md)
                    .padding(.vertical, MADTheme.Spacing.md)
                }
            }
            .navigationTitle(summary.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
            }
        }
        .fullScreenCover(item: $flyoverLaunch) { launch in
            RouteFlyoverPlayerView(launch: launch)
        }
        .sheet(item: $pager) { selection in
            WorkoutPagerView(
                workouts: selection.workouts,
                startIndex: selection.startIndex
            )
            // Injected explicitly rather than relying on this sheet inheriting
            // it: `WorkoutDetailView` inside the pager reads `healthManager`
            // as an `@EnvironmentObject`, and a missing one is a CRASH at
            // presentation, not a compile error — the same reason WorkoutsView
            // re-injects it. This screen can be reached from a sheet raised by
            // a sheet, so the chain is worth not trusting.
            .environmentObject(healthManager)
        }
        .task { await loadWorkouts() }
    }

    // MARK: Map

    private var mapCard: some View {
        RouteArtView(
            coordinates: summary.coordinates,
            routeColor: accent,
            authorAvatar: owner,
            paletteDate: summary.lastWalked
        )
        .frame(height: 260)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
        // Overlaid AFTER the art, the rule every route surface follows.
        .overlay(alignment: .topLeading) {
            FlyoverChipButton(accent: accent) {
                flyoverLaunch = FlyoverLaunch(
                    coordinates: summary.coordinates,
                    workoutType: summary.workoutType ?? "walking",
                    stats: nil,
                    author: owner,
                    officialDistanceMiles: summary.typicalDistanceMiles > 0
                        ? summary.typicalDistanceMiles : nil
                )
            }
            .padding(10)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Stats

    private var statsCard: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            HStack(spacing: MADTheme.Spacing.sm) {
                statTile("TIMES", "\(summary.timesWalked)", accent)
                statTile("BEST", summary.fastest.map {
                    RunStatsStickerView.durationText($0.duration)
                } ?? "—", accent)
                statTile("AVERAGE", averageText, .primary)
            }
            // Only ever says what it can prove. `untimedCount` is walks on this
            // route the local index can't time — the same honest split the
            // repeats banner makes between "count" and "ranked", and without
            // saying so the tiles look like they've lost a walk the header
            // number is still counting.
            if summary.untimedCount > 0 {
                Text("\(summary.untimedCount) more \(summary.untimedCount == 1 ? "walk" : "walks") on this route aren't timed on this phone.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(MADTheme.Spacing.md)
        .cardStyle()
    }

    private func statTile(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(color)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(MADTheme.CornerRadius.small)
    }

    /// The MEAN of the ranked walks — the median is the right summary for a
    /// route's LENGTH (one drifted trace can't move it) but the wrong one for
    /// its times, where "how do I usually do" is genuinely an average.
    private var averageText: String {
        let ranked = summary.ranked
        guard !ranked.isEmpty else { return "—" }
        let total = ranked.reduce(0) { $0 + $1.duration }
        return RunStatsStickerView.durationText(total / Double(ranked.count))
    }

    // MARK: Outings

    private var outingsCard: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            HStack {
                Text("EVERY TIME")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.secondary)
                Spacer()
                Picker("Order", selection: $order) {
                    ForEach(Order.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }

            ForEach(Array(listed.enumerated()), id: \.element.id) { position, outing in
                outingRow(outing, position: position)
                if outing.id != listed.last?.id {
                    Divider().overlay(Color.white.opacity(0.08))
                }
            }
        }
        .padding(MADTheme.Spacing.md)
        .cardStyle()
    }

    private func outingRow(_ outing: RouteOuting, position: Int) -> some View {
        // A rank badge only means something in rank order; in date order the
        // same "1" beside the newest walk would read as "your fastest".
        let rankBadge: String? = order == .fastest ? "\(position + 1)" : nil
        let workout = workoutsById[outing.id]
        // Built here rather than inline in the body: an array literal of mixed
        // optional/non-optional strings is exactly the expression the
        // type-checker gives up on inside a ViewBuilder.
        let detail: String = [RouteFormat.paceText(outing), outing.distanceMiles.distanceFormatted]
            .compactMap { $0 }
            .joined(separator: "  ·  ")
        return Button {
            guard let workout else { return }
            let ordered = listed.compactMap { workoutsById[$0.id] }
            pager = RouteWorkoutSelection(
                workouts: ordered,
                startIndex: ordered.firstIndex(where: { $0.uuid == workout.uuid }) ?? 0
            )
        } label: {
            HStack(spacing: MADTheme.Spacing.sm) {
                if let rankBadge {
                    Text(rankBadge)
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(position == 0 ? .black : .white.opacity(0.8))
                        .frame(width: 24, height: 24)
                        .background(
                            Circle().fill(position == 0 ? accent : Color.white.opacity(0.10))
                        )
                        .monospacedDigit()
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(RunStatsStickerView.durationText(outing.duration))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(.primary)
                        .monospacedDigit()
                    Text(detail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                Text(RouteFormat.dayText(outing.date))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                if workout != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.6))
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(workout == nil)
    }

    /// One HealthKit query for the whole route rather than one per row.
    private func loadWorkouts() async {
        guard workoutsById.isEmpty else { return }
        let uuids = summary.outings.compactMap { UUID(uuidString: $0.id) }
        guard !uuids.isEmpty else { return }
        let fetched: [HKWorkout] = await withCheckedContinuation { continuation in
            healthManager.fetchWorkoutsByUUIDs(uuids) { continuation.resume(returning: $0) }
        }
        workoutsById = Dictionary(
            fetched.map { ($0.uuid.uuidString, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

/// Item-based sheet payload, per the fullScreenCover/sheet rule in ios.md —
/// an `isPresented` flag beside a separate `@State` races to a stale nil.
struct RouteWorkoutSelection: Identifiable {
    let id = UUID()
    let workouts: [HKWorkout]
    let startIndex: Int
}
