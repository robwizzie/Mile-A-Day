import CoreLocation
import Foundation

/// Decides which points of a walk may leave the phone.
///
/// The server can only trim a finished route, and a live one has no finish yet.
/// So nothing is released until the walker has moved `holdbackMeters` past it:
/// the first stretch never goes (nothing is released before that far in), and
/// neither does the last, because the walker stops before they've passed it.
/// Stopping at your front door sends nothing about your front door.
struct LiveRouteRelease {
    let holdbackMeters: Double
    /// One point per this many metres: a map line needs no more.
    let spacingMeters: Double = 20

    private var consumed = 0
    private var walked = 0.0
    private var last: CLLocation?
    private var held: [(coordinate: CLLocationCoordinate2D, walkedAt: Double)] = []
    private var lastReleasedAt: Double?

    init(holdbackMeters: Double) {
        self.holdbackMeters = holdbackMeters
    }

    /// Feed the whole trail, as often as you like. Returns newly releasable points.
    mutating func release(from trail: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        // A shorter trail is a new walk on this phone.
        if trail.count < consumed {
            self = LiveRouteRelease(holdbackMeters: holdbackMeters)
        }
        for coordinate in trail[consumed...] {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if let last { walked += location.distance(from: last) }
            last = location
            held.append((coordinate, walked))
        }
        consumed = trail.count

        var released: [CLLocationCoordinate2D] = []
        while let next = held.first, walked - next.walkedAt >= holdbackMeters {
            held.removeFirst()
            guard next.walkedAt >= holdbackMeters else { continue }
            if let lastReleasedAt, next.walkedAt - lastReleasedAt < spacingMeters { continue }
            lastReleasedAt = next.walkedAt
            released.append(next.coordinate)
        }
        return released
    }
}

/// One friend's shared line on the buddy map.
struct BuddyFriendRoute: Identifiable, Equatable {
    let userId: String
    let coordinates: [CLLocationCoordinate2D]
    var id: String { userId }

    static func == (lhs: BuddyFriendRoute, rhs: BuddyFriendRoute) -> Bool {
        lhs.userId == rhs.userId && lhs.coordinates.count == rhs.coordinates.count
    }
}

/// "Share my route" for one buddy walk. Off by default, every walk.
///
/// Lives outside the map because the walk outlives it: the phone's Stats tab,
/// a locked screen and the Duo folding all take the map away while the walker
/// is still out, and the line has to keep up. The server is the authority on
/// who sees what (`buddyLiveRouteService`); this decides what is sent.
@MainActor
final class BuddyLiveRouteSharing: ObservableObject {
    static let shared = BuddyLiveRouteSharing()

    @Published private(set) var isSharing = false
    @Published private(set) var friendRoutes: [BuddyFriendRoute] = []

    /// How far behind the walker the shared line ends. Your Hide start & end
    /// setting, with a floor: "Off" means something different when the line is
    /// following you live.
    static var holdbackMeters: Double {
        Double(max(RoutePrivacyTrim.currentSettingMeters, minimumHoldbackMeters))
    }
    private static let minimumHoldbackMeters = 100
    private static let cadence: Duration = .seconds(20)
    private static let maxPointsPerPost = 60

    private var sessionId: String?
    private var release = LiveRouteRelease(holdbackMeters: BuddyLiveRouteSharing.holdbackMeters)
    /// Released but not yet accepted, so a dropped request loses nothing.
    private var outbox: [CLLocationCoordinate2D] = []
    private var loop: Task<Void, Never>?

    private init() {}

    /// The map appeared for this walk. Picks up a share from before a relaunch.
    func attach(sessionId: String) async {
        guard self.sessionId != sessionId else { return }
        detach()
        self.sessionId = sessionId
        guard let state = try? await BuddySessionService.shared.fetchLiveRoutes(sessionId: sessionId),
              self.sessionId == sessionId, state.sharing
        else { return }
        apply(state)
        startLoop()
    }

    func setSharing(_ enabled: Bool) async throws {
        guard let sessionId else { return }
        let sharing = try await BuddySessionService.shared.setLiveRouteSharing(
            sessionId: sessionId, enabled: enabled)
        if sharing {
            isSharing = true
            startLoop()
        } else {
            stop()
        }
    }

    /// The walk is over for this phone. The server clears the line on finish.
    func detach() {
        stop()
        sessionId = nil
    }

    private func stop() {
        loop?.cancel()
        loop = nil
        isSharing = false
        friendRoutes = []
        outbox = []
        release = LiveRouteRelease(holdbackMeters: Self.holdbackMeters)
    }

    private func apply(_ state: BuddyLiveRoutesState) {
        isSharing = state.sharing
        friendRoutes = state.routes.map { route in
            BuddyFriendRoute(
                userId: route.user_id,
                coordinates: route.points.compactMap { point in
                    point.count == 2
                        ? CLLocationCoordinate2D(latitude: point[0], longitude: point[1]) : nil
                })
        }
    }

    private func startLoop() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: Self.cadence)
            }
        }
    }

    private func tick() async {
        guard let sessionId else { return }
        outbox += release.release(from: WorkoutLocationManager.shared.liveTrail)

        while !outbox.isEmpty {
            let batch = Array(outbox.prefix(Self.maxPointsPerPost))
            guard let result = try? await BuddySessionService.shared.postLiveRoutePoints(
                sessionId: sessionId,
                points: batch.map { [$0.latitude, $0.longitude] })
            else { break }  // Kept in the outbox for the next tick.
            guard result.sharing else {
                stop()  // A setting changed, Stealth started, or the walk ended.
                return
            }
            outbox.removeFirst(batch.count)
        }

        if let state = try? await BuddySessionService.shared.fetchLiveRoutes(sessionId: sessionId) {
            guard state.sharing else {
                stop()
                return
            }
            apply(state)
        }
    }
}
