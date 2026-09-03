import Foundation
import HealthKit
import Observation

/// One Stealth Mode window: `end == nil` while it is still open. A FUTURE
/// `end` is "stealth until <date>"; a backdated `start` is "also hide routes
/// since…". Mirrors the server's `stealth_windows` rows.
struct StealthWindow: Codable, Equatable {
    let start: Date
    var end: Date?

    func isOpen(at now: Date = Date()) -> Bool {
        start <= now && (end.map { $0 > now } ?? true)
    }

    /// Overlap, not containment: a walk that straddles the moment stealth was
    /// switched on or off is hidden — the conservative reading, and the same
    /// one the server applies.
    func overlaps(start workoutStart: Date, end workoutEnd: Date) -> Bool {
        start <= workoutEnd && (end.map { $0 >= workoutStart } ?? true)
    }
}

/// Wire shape of a window inside `NotificationSettingsResponse`. Strings, not
/// Dates: the backend serialises timestamptz WITH fractional seconds, which
/// APIClient's `.iso8601` decoder cannot parse — one bad date would fail the
/// whole preferences payload (ios.md).
struct StealthWindowDTO: Codable {
    let started_at: String
    let ended_at: String?
}

/// Stealth Mode on the phone — "friends never see WHERE this walk was".
///
/// The SERVER is the authority: it keeps the window log, stamps every workout
/// that overlaps one (`workouts.stealth`, sticky), and refuses to store a route
/// for it. This store is defence in depth on the device that actually holds
/// the GPS trace: it decides (a) that the trace never leaves the phone — the
/// sync omits it and the backfill sweep skips it, (b) that no local path
/// renders it into an image or offers it for sharing, and (c) the owner-only
/// "Stealth" badge. Windows are hydrated from the server (server wins), so a
/// reinstall classifies history correctly; the local copy is written FIRST on
/// a toggle so an offline enable still protects the next upload.
///
/// Three things make a workout stealth, any one of them:
///   1. `MAD_stealth` HKWorkout metadata — the in-app tracker stamps it at
///      finish from a flag LATCHED at start (a toggle flipped mid-walk can't
///      un-hide the walk).
///   2. A per-workout hide the owner asked for ("Hide this route from
///      friends") — the HKWorkout carries no metadata for that, so the id is
///      remembered here.
///   3. `[startDate, endDate]` overlaps any window — the only signal for a
///      Watch/Strava/third-party workout, which carries no MAD metadata.
@MainActor
@Observable
final class StealthModeStore {
    static let shared = StealthModeStore()

    /// HKWorkout metadata key the tracker stamps; the sync reads it back.
    static let metadataKey = "MAD_stealth"
    /// Server limits, mirrored so the sheet never offers what the PUT rejects.
    static let backdateLimitDays = 30
    static let untilLimitDays = 90

    private static let windowsKey = "MAD_StealthWindowsV1"
    private static let hiddenIdsKey = "MAD_StealthHiddenWorkoutIdsV1"

    private(set) var windows: [StealthWindow]
    private(set) var hiddenWorkoutIds: Set<String>
    private var hydratedThisProcess = false

    private init() {
        windows = Self.loadWindows()
        hiddenWorkoutIds = Set(
            UserDefaults.standard.array(forKey: Self.hiddenIdsKey) as? [String] ?? [])
    }

    // MARK: - State

    var openWindow: StealthWindow? { windows.first { $0.isOpen() } }
    var isOn: Bool { openWindow != nil }
    /// Trip mode's end date, when one was set.
    var until: Date? { openWindow?.end }
    /// When the current window opened — drives the "still on since…" nudge.
    var onSince: Date? { openWindow?.start }

    /// Recent windows, newest first, for the sheet's history list.
    var recentWindows: [StealthWindow] {
        windows.sorted { $0.start > $1.start }
    }

    // MARK: - Mutation

    /// Local-first toggle. The server call is the caller's (the sheet owns
    /// it); the response then re-hydrates and wins.
    func setOn(_ on: Bool, until: Date? = nil, since: Date? = nil) {
        let now = Date()
        if on {
            if let index = windows.firstIndex(where: { $0.isOpen(at: now) }) {
                var window = windows[index]
                if let since, since < window.start {
                    window = StealthWindow(start: since, end: window.end)
                }
                window.end = until
                windows[index] = window
            } else {
                windows.append(StealthWindow(start: since ?? now, end: until))
            }
        } else {
            for index in windows.indices where windows[index].isOpen(at: now) {
                windows[index].end = now
            }
        }
        persistWindows()
    }

    /// Server wins: replaces the local log wholesale.
    func hydrate(from dtos: [StealthWindowDTO]) {
        let parsed = dtos.compactMap { dto -> StealthWindow? in
            guard let start = BuddyDate.parse(dto.started_at) else { return nil }
            return StealthWindow(start: start, end: BuddyDate.parse(dto.ended_at))
        }
        windows = parsed
        hydratedThisProcess = true
        persistWindows()
    }

    /// Hydrate from any preferences response that carries windows (older
    /// servers don't — leave the local log alone then).
    func apply(_ response: NotificationSettingsResponse) {
        if let dtos = response.stealth_windows {
            hydrate(from: dtos)
        }
    }

    /// Remember a per-workout hide (the HKWorkout has no metadata for it).
    func markHidden(_ workoutId: String) {
        hiddenWorkoutIds.insert(workoutId)
        UserDefaults.standard.set(Array(hiddenWorkoutIds), forKey: Self.hiddenIdsKey)
    }

    // MARK: - Classification

    func isStealth(_ workout: HKWorkout) -> Bool {
        if (workout.metadata?[Self.metadataKey] as? NSNumber)?.boolValue == true {
            return true
        }
        if hiddenWorkoutIds.contains(workout.uuid.uuidString) { return true }
        return windows.contains { $0.overlaps(start: workout.startDate, end: workout.endDate) }
    }

    // MARK: - Server hydration

    /// Once per process, best-effort. There is no launch-time preferences
    /// sync in the app, so without this a reinstall would badge nothing until
    /// the user happened to open the sharing settings.
    func hydrateFromServerIfNeeded() async {
        guard !hydratedThisProcess else { return }
        guard let response = try? await FriendService().getNotificationSettings() else { return }
        apply(response)
    }

    // MARK: - Persistence

    private static func loadWindows() -> [StealthWindow] {
        guard let data = UserDefaults.standard.data(forKey: windowsKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // A blob this build can't read is an empty log, never a crash — the
        // server re-hydrates it on the next preferences read.
        return (try? decoder.decode([StealthWindow].self, from: data)) ?? []
    }

    private func persistWindows() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(windows) {
            UserDefaults.standard.set(data, forKey: Self.windowsKey)
        }
    }
}
