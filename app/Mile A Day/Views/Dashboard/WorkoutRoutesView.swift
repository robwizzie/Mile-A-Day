import SwiftUI
import HealthKit
import CoreLocation

// MARK: - Model

/// One walk on a route.
struct RouteOuting: Identifiable, Equatable {
    /// The workout's UUID string.
    let id: String
    let date: Date
    let distanceMiles: Double
    let duration: TimeInterval

    /// Seconds per mile. Elapsed duration, the same arithmetic the workout row
    /// and the route preview's flyover HUD print — three surfaces disagreeing
    /// about one walk's pace is worse than any of them being ideal.
    var paceSecondsPerMile: TimeInterval? {
        guard distanceMiles > 0, duration > 0 else { return nil }
        return duration / distanceMiles
    }
}

/// A path the user has walked, and every walk on it.
///
/// Built by joining `RouteMatcher`'s clustering of the server's route library
/// against the LOCAL `WorkoutIndex`, which is where durations live — the route
/// endpoint serves traces, not times. A walk in the group that the index can't
/// time is counted (`timesWalked`) but not ranked, the same split the repeats
/// banner already makes between `count` and `ranked`.
struct RouteSummary: Identifiable {
    /// The group's leader id — stable between passes, so a row keeps its
    /// identity across a refresh.
    let id: String
    /// The most recent outing's trace, which is what the row draws.
    let coordinates: [CLLocationCoordinate2D]
    let workoutType: String?
    /// Newest first.
    let outings: [RouteOuting]
    /// Walks on this route the local index couldn't time (older than the
    /// index, or synced from a device this one never saw).
    let untimedCount: Int

    var timesWalked: Int { outings.count + untimedCount }

    /// Ranked outings, quickest first. Only walks with a real duration AND a
    /// real distance — a zero of either isn't a fast lap, it's missing data.
    var ranked: [RouteOuting] {
        outings
            .filter { $0.duration > 0 && $0.distanceMiles > 0 }
            .sorted { $0.duration < $1.duration }
    }

    var fastest: RouteOuting? { ranked.first }
    var slowest: RouteOuting? { ranked.count >= 2 ? ranked.last : nil }
    var lastWalked: Date? { outings.first?.date }

    /// The route's length, as the MEDIAN of its walks rather than the mean: a
    /// single mis-tracked outing (a GPS drift that added half a mile, a walk
    /// cut short) drags an average and can't move a median.
    var typicalDistanceMiles: Double {
        let values = outings.map(\.distanceMiles).filter { $0 > 0 }.sorted()
        guard !values.isEmpty else { return 0 }
        return values[values.count / 2]
    }

    /// "Loop" when the walk came back to where it started, else "Out & back".
    ///
    /// Measured against the route's own size, not a fixed distance: 100m from
    /// the start closes a neighbourhood block and is nowhere near closing a
    /// ten-mile ride.
    var shapeName: String {
        guard let first = coordinates.first, let last = coordinates.last else { return "Route" }
        let start = CLLocation(latitude: first.latitude, longitude: first.longitude)
        let end = CLLocation(latitude: last.latitude, longitude: last.longitude)
        let gap = end.distance(from: start)
        let span = max(typicalDistanceMiles * 1609.34, 1)
        return gap < max(120, span * 0.12) ? "Loop" : "Out & back"
    }

    /// "1.17 mi loop" — the row's title.
    ///
    /// Deliberately NOT a place name: reverse geocoding is throttled, fails
    /// silently and would put a wrong town on a row that already draws the
    /// real map with the real street names on it.
    var title: String {
        "\(typicalDistanceMiles.distanceFormatted) \(shapeName.lowercased())"
    }
}

/// Loads the user's routes once per screen and keeps them for the tab.
@MainActor
final class RouteLibraryModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, ready, failed }

    @Published private(set) var summaries: [RouteSummary] = []
    @Published private(set) var phase: Phase = .idle

    /// Resolved in `init`-free fashion by the host's `.task`; a view whose body
    /// renders `EmptyView` gets no lifecycle, so the LOADING state has to be
    /// something the tab draws (it is — see `WorkoutRoutesView.body`).
    func load(healthManager: HealthKitManager, force: Bool = false) async {
        guard force || phase == .idle || phase == .failed else { return }
        phase = .loading

        // Runs off this actor: `RouteMatcher` is a plain enum, and the
        // clustering inside is the expensive half.
        guard let bundle = await RouteMatcher.groupedLibrary() else {
            phase = .failed
            return
        }

        // Back on the main actor for the index join — `workoutRecord(forUUID:)`
        // lazily builds a lookup cache and is not thread-safe.
        let tracesById = Dictionary(
            bundle.routes.map { ($0.workoutId, $0.coordinates) },
            uniquingKeysWith: { first, _ in first }
        )

        var built: [RouteSummary] = []
        for group in bundle.groups {
            var outings: [RouteOuting] = []
            var untimed = 0
            for id in group.workoutIds {
                guard let record = healthManager.workoutRecord(forUUID: id) else {
                    untimed += 1
                    continue
                }
                outings.append(RouteOuting(
                    id: id,
                    date: record.localEndTime,
                    distanceMiles: record.distance,
                    duration: record.duration
                ))
            }
            outings.sort { $0.date > $1.date }

            // Draw the most recent walk we actually hold a trace for — the
            // leader is whichever id sorted first, which is arbitrary, and a
            // row showing a two-year-old version of a route someone walked
            // yesterday reads as stale data.
            let drawableId = outings.first(where: { tracesById[$0.id] != nil })?.id
                ?? group.workoutIds.first(where: { tracesById[$0] != nil })
            guard let drawableId, let coords = tracesById[drawableId] else { continue }

            built.append(RouteSummary(
                id: group.id,
                coordinates: coords,
                workoutType: healthManager.workoutRecord(forUUID: drawableId)?.workoutType,
                outings: outings,
                untimedCount: untimed
            ))
        }

        summaries = built
        phase = .ready
    }
}

// MARK: - The tab

/// Every path the user walks more than once, and how they've done on each.
///
/// The fourth face of the Workouts screen, beside Calendar / List / Trends —
/// the others slice history by TIME, this one slices it by PLACE. It answers
/// the question the repeats banner raises and can't finish: "my 6th time on
/// this route" invites "so what were the other five?".
///
/// Client-only by construction. The server already serves every route the user
/// has (`GET /workouts/:id/routes`, which the repeats banner has always used),
/// and durations already live in the local `WorkoutIndex`, so there is nothing
/// here for the backend to add.
struct WorkoutRoutesView: View {
    @ObservedObject var healthManager: HealthKitManager
    @StateObject private var model = RouteLibraryModel()
    @State private var sort: Sort = .mostWalked
    @State private var selected: RouteSummary?

    enum Sort: String, CaseIterable, Identifiable {
        case mostWalked = "Most walked"
        case fastest = "Fastest"
        case recent = "Recent"
        var id: String { rawValue }
    }

    /// Routes walked ONCE are not routes yet — they're just walks, and the
    /// Calendar and List tabs already list every one of those. Showing them
    /// here would bury the handful of paths this screen exists for under every
    /// one-off the user has ever taken.
    private var repeated: [RouteSummary] {
        model.summaries.filter { $0.timesWalked >= 2 }
    }

    private var sorted: [RouteSummary] {
        switch sort {
        case .mostWalked:
            // Ties broken by recency, so a shelf of 2-time routes still reads
            // newest-first rather than in clustering order.
            return repeated.sorted {
                ($0.timesWalked, $0.lastWalked ?? .distantPast)
                    > ($1.timesWalked, $1.lastWalked ?? .distantPast)
            }
        case .fastest:
            // By the route's own best pace, never its best TIME — a long route
            // would otherwise sort last however fast it was run.
            return repeated.sorted {
                ($0.fastest?.paceSecondsPerMile ?? .greatestFiniteMagnitude)
                    < ($1.fastest?.paceSecondsPerMile ?? .greatestFiniteMagnitude)
            }
        case .recent:
            return repeated.sorted {
                ($0.lastWalked ?? .distantPast) > ($1.lastWalked ?? .distantPast)
            }
        }
    }

    var body: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            switch model.phase {
            case .idle, .loading:
                loadingCard
            case .failed:
                failedCard
            case .ready:
                if repeated.isEmpty {
                    emptyCard
                } else {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    LazyVStack(spacing: MADTheme.Spacing.md) {
                        ForEach(sorted) { summary in
                            RouteSummaryRow(summary: summary) { selected = summary }
                        }
                    }
                }
            }
        }
        .task { await model.load(healthManager: healthManager) }
        .sheet(item: $selected) { summary in
            RouteDetailView(summary: summary, healthManager: healthManager)
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Finding your routes…")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.lg)
        .cardStyle()
    }

    /// A failure is not an absence: "you have no routes" over a network error
    /// is the same lie the weekly challenge card used to tell on a Sunday.
    private var failedCard: some View {
        VStack(spacing: 10) {
            Text("Couldn't load your routes")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(.primary)
            Text("Check your connection and try again.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await model.load(healthManager: healthManager, force: true) }
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundColor(MADTheme.Colors.madRed)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.lg)
        .cardStyle()
    }

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(MADTheme.Colors.redGradient)
                .accessibilityHidden(true)
            Text("No repeat routes yet")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(.primary)
            Text("Walk the same loop twice and it shows up here, with every time you've done it.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, MADTheme.Spacing.md)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.lg)
        .cardStyle()
    }
}

// MARK: - Row

/// One route: its shape, how many times, and the spread between best and worst.
struct RouteSummaryRow: View {
    let summary: RouteSummary
    let onOpen: () -> Void

    private var accent: Color { MADTheme.workoutColor(summary.workoutType ?? "walking") }

    private var owner: RouteArtAvatar {
        RouteArtAvatar(
            name: UserManager.shared.currentUser.name,
            imageURL: UserManager.shared.currentUser.profileImageUrl
        )
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 10) {
                header

                RouteArtView(
                    coordinates: summary.coordinates,
                    routeColor: accent,
                    authorAvatar: owner,
                    paletteDate: summary.lastWalked
                )
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium,
                                            style: .continuous))
                .accessibilityHidden(true)

                times
            }
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
            .contentShape(Rectangle())
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel("\(summary.title), walked \(summary.timesWalked) times")
        .accessibilityHint("Opens every walk on this route")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(summary.title)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(summary.timesWalked)×")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundColor(accent)
                .monospacedDigit()
        }
    }

    /// Best and worst, side by side — the spread IS the story of a repeated
    /// route. A single best time says nothing about whether today was good.
    @ViewBuilder
    private var times: some View {
        if let fastest = summary.fastest {
            HStack(spacing: MADTheme.Spacing.sm) {
                RouteTimeTile(label: "BEST", outing: fastest, accent: accent)
                if let slowest = summary.slowest {
                    RouteTimeTile(label: "SLOWEST", outing: slowest, accent: .secondary)
                }
            }
        }
    }
}

/// One labelled time on a route.
struct RouteTimeTile: View {
    let label: String
    let outing: RouteOuting
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundColor(.secondary)
            Text(RunStatsStickerView.durationText(outing.duration))
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundColor(accent)
                .monospacedDigit()
            Text(RouteFormat.paceText(outing) ?? RouteFormat.dayText(outing.date))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(MADTheme.CornerRadius.small)
    }
}

/// Shared formatting for the routes screens, so the row and the detail can't
/// print one walk two ways.
enum RouteFormat {
    /// "24:53 /mi", already in the viewer's unit (ios.md: never a bare "mi").
    static func paceText(_ outing: RouteOuting) -> String? {
        guard let pace = outing.paceSecondsPerMile else { return nil }
        return "\(RunStatsStickerView.paceText(pace.pacePerDisplayUnit)) /\(DistanceUnits.current.abbreviation)"
    }

    static func dayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}
