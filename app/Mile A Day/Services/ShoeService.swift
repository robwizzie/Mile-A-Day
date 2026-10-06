import Foundation
import HealthKit
import Observation
import UIKit

// MARK: - Models

/// A default pair is chosen PER ACTIVITY, so running shoes can stay off
/// walks. Every on-foot workout files under one of the two — mirrors the
/// server's `shoeActivitySql`, which decides what the sync stamps.
enum ShoeActivity: String, CaseIterable, Identifiable, Hashable {
    case walking, running

    var id: String { rawValue }

    /// "Walks" / "Runs".
    var title: String {
        switch self {
        case .walking: return "Walks"
        case .running: return "Runs"
        }
    }

    /// "walks" / "runs", for the middle of a sentence.
    var noun: String { title.lowercased() }

    /// "3 walks" / "1 run".
    func count(_ n: Int) -> String {
        let one = self == .walking ? "walk" : "run"
        return n == 1 ? "1 \(one)" : "\(n) \(noun)"
    }

    var symbol: String {
        switch self {
        case .walking: return "figure.walk"
        case .running: return "figure.run"
        }
    }

    /// 13:30/mi — the walk/run divide `ActivityCardView` draws `other` with.
    private static let walkRunPaceSeconds: TimeInterval = 810

    /// Which default a workout takes: runs → running; walks and hikes →
    /// walking; `.other` (Fitbit-via-Google-Health walks) by pace. nil for
    /// anything not on foot, which the sync never gives a pair.
    static func of(_ workout: HKWorkout) -> ShoeActivity? {
        switch workout.workoutActivityType {
        case .running: return .running
        case .walking, .hiking: return .walking
        case .cycling: return nil
        default:
            let miles = workout.madDistanceMiles
            guard miles > 0, workout.duration > 0 else { return .walking }
            return workout.duration / miles < walkRunPaceSeconds ? .running : .walking
        }
    }
}

/// One pair of the user's shoes. PRIVATE: every endpoint behind this is
/// self-only on the server and nothing about a shoe is ever put on a post,
/// a feed card or a friend's view of a profile.
///
/// Distances are MILES, like everywhere else; screens format them through
/// `DistanceUnits`.
struct Shoe: Codable, Identifiable, Hashable {
    let shoe_id: String
    let name: String
    let brand: String?
    let colorway: String?
    let image_url: String?
    let starting_miles: Double
    let replace_at_miles: Double?
    /// Default for either activity (what builds before the split read).
    let is_default: Bool
    /// The activities this pair is the default for. nil on a server that
    /// predates the split, where one default meant every activity.
    let default_for: [String]?
    /// Timestamps stay strings (fractional-second `timestamptz` breaks
    /// `.iso8601` — see `BuddyDate`); only presence is read here.
    let retired_at: String?
    let created_at: String?
    let tracked_miles: Double
    let total_miles: Double
    let workout_count: Int
    /// `YYYY-MM-DD` local dates of the first/last counted workout.
    let first_used: String?
    let last_used: String?

    var id: String { shoe_id }
    var isRetired: Bool { retired_at != nil }

    var defaultActivities: Set<ShoeActivity> {
        guard let default_for else { return is_default ? Set(ShoeActivity.allCases) : [] }
        return Set(default_for.compactMap(ShoeActivity.init(rawValue:)))
    }

    func isDefault(for activity: ShoeActivity) -> Bool {
        defaultActivities.contains(activity)
    }

    var imageURL: URL? { ProfileImageService.fullImageURL(for: image_url) }

    /// "Nike · Volt Tint/Sapphire", whichever halves exist.
    var detailLine: String? {
        let parts = [brand, colorway].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Share of the replace-at mileage used, uncapped (over 1 = past it).
    var wearFraction: Double? {
        guard let target = replace_at_miles, target > 0 else { return nil }
        return total_miles / target
    }
}

/// A counted workout behind a shoe's mileage.
struct ShoeWorkout: Codable, Identifiable, Hashable {
    let workout_id: String
    let local_date: String
    let workout_type: String
    let distance: Double
    let total_duration: Double

    var id: String { workout_id }
}

/// The pair on one workout. `source`:
/// - "user": picked in the app (shoe_id nil = picked "none")
/// - "default": stamped by the sync from the default pair
/// - "predicted": the workout hasn't synced yet; this is the default the
///   sync WILL stamp
/// - nil: nothing assigned
struct WorkoutShoeAssignment: Codable, Hashable {
    let shoe_id: String?
    let source: String?
}

/// A new pair as typed into the add form.
struct ShoeDraft {
    var name: String = ""
    var brand: String = ""
    var colorway: String = ""
    /// Miles, never display units.
    var startingMiles: Double = 0
    var replaceAtMiles: Double?
    var defaultFor: Set<ShoeActivity> = []
}

/// A pair just taken off an activity's default, with how many of that
/// activity's workouts the sync gave it — the app offers to take it off
/// those, since "not for walks" usually means it's carrying walks it was
/// never worn on.
struct ShoeDefaultCleanup: Identifiable, Hashable {
    let shoeId: String
    let shoeName: String
    let activity: ShoeActivity
    let count: Int

    var id: String { "\(shoeId)#\(activity.rawValue)" }
}

// MARK: - API

enum ShoeService {
    private static func userId() throws -> String {
        guard let id = UserManager.shared.currentUser.backendUserId else {
            throw APIError.notAuthenticated
        }
        return id
    }

    private struct ShoeList: Decodable { let shoes: [Shoe] }
    struct ReplacedDefault: Decodable {
        let shoe_id: String
        let auto_assigned: Int
    }
    private struct DefaultChange: Decodable {
        let shoes: [Shoe]
        let previous: ReplacedDefault?
    }
    private struct ClearedAuto: Decodable {
        let cleared: Int
        let shoes: [Shoe]
    }
    private struct WorkoutList: Decodable { let workouts: [ShoeWorkout] }
    private struct OK: Decodable { let success: Bool? }

    /// JSONSerialization rather than an Encodable struct: a PATCH needs to
    /// send an explicit `null` to clear a field, which a synthesized encoder
    /// silently omits.
    private static func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    static func list() async throws -> [Shoe] {
        let uid = try userId()
        return try await APIClient.fancyFetch(
            endpoint: "/users/\(uid)/shoes",
            responseType: ShoeList.self
        ).shoes
    }

    static func create(_ draft: ShoeDraft) async throws -> Shoe {
        let uid = try userId()
        var body: [String: Any] = [
            "name": draft.name,
            "starting_miles": draft.startingMiles,
            "default_for": ShoeActivity.allCases.filter(draft.defaultFor.contains).map(\.rawValue),
        ]
        if !draft.brand.isEmpty { body["brand"] = draft.brand }
        if !draft.colorway.isEmpty { body["colorway"] = draft.colorway }
        if let target = draft.replaceAtMiles { body["replace_at_miles"] = target }
        return try await APIClient.fancyFetch(
            endpoint: "/users/\(uid)/shoes",
            method: .POST,
            body: try json(body),
            responseType: Shoe.self
        )
    }

    /// `fields` uses the server's keys; `NSNull()` clears a nullable field.
    static func update(_ shoeId: String, fields: [String: Any]) async throws -> Shoe {
        let uid = try userId()
        return try await APIClient.fancyFetch(
            endpoint: "/users/\(uid)/shoes/\(shoeId)",
            method: .PATCH,
            body: try json(fields),
            responseType: Shoe.self
        )
    }

    static func delete(_ shoeId: String) async throws {
        let uid = try userId()
        _ = try await APIClient.fancyFetch(
            endpoint: "/users/\(uid)/shoes/\(shoeId)",
            method: .DELETE,
            responseType: OK.self
        )
    }

    static func workouts(for shoeId: String) async throws -> [ShoeWorkout] {
        let uid = try userId()
        return try await APIClient.fancyFetch(
            endpoint: "/users/\(uid)/shoes/\(shoeId)/workouts",
            responseType: WorkoutList.self
        ).workouts
    }

    /// `activity` picks which default to predict for a workout the server
    /// hasn't seen yet (the recap opens before the sync).
    static func assignment(forWorkout workoutId: String, activity: ShoeActivity?) async throws -> WorkoutShoeAssignment {
        let uid = try userId()
        let query = activity.map { "?activity=\($0.rawValue)" } ?? ""
        return try await APIClient.fancyFetch(
            endpoint: "/users/\(uid)/workout-shoes/\(workoutId)\(query)",
            responseType: WorkoutShoeAssignment.self
        )
    }

    /// Makes `shoeId` the default for `activity`; nil = no default for it.
    static func setDefault(_ shoeId: String?, for activity: ShoeActivity) async throws -> (shoes: [Shoe], previous: ReplacedDefault?) {
        let uid = try userId()
        let body: [String: Any] = ["shoe_id": shoeId ?? NSNull()]
        let result = try await APIClient.fancyFetch(
            endpoint: "/users/\(uid)/shoe-defaults/\(activity.rawValue)",
            method: .PUT,
            body: try json(body),
            responseType: DefaultChange.self
        )
        return (result.shoes, result.previous)
    }

    /// Takes the pair off the `activity` workouts the sync gave it. The
    /// user's own picks are left alone.
    static func clearAutoAssigned(_ shoeId: String, activity: ShoeActivity) async throws -> (cleared: Int, shoes: [Shoe]) {
        let uid = try userId()
        let result = try await APIClient.fancyFetch(
            endpoint: "/users/\(uid)/shoes/\(shoeId)/clear-auto",
            method: .POST,
            body: try json(["activity": activity.rawValue]),
            responseType: ClearedAuto.self
        )
        return (result.cleared, result.shoes)
    }

    /// `shoeId` nil records an explicit "no shoes" for that workout, which
    /// also stops the sync stamping the default onto it.
    static func setShoe(_ shoeId: String?, forWorkout workoutId: String) async throws -> WorkoutShoeAssignment {
        let uid = try userId()
        let body: [String: Any] = ["shoe_id": shoeId ?? NSNull()]
        return try await APIClient.fancyFetch(
            endpoint: "/users/\(uid)/workout-shoes/\(workoutId)",
            method: .PUT,
            body: try json(body),
            responseType: WorkoutShoeAssignment.self
        )
    }

    /// The pair's picture, picked from the camera roll.
    static func uploadImage(_ image: UIImage, shoeId: String) async throws -> Shoe {
        let uid = try userId()
        guard let url = URL(string: "\(AppConfig.baseURL)/users/\(uid)/shoes/\(shoeId)/image") else {
            throw APIError.invalidURL
        }
        guard let data = image.shoeUploadJPEG() else {
            throw APIError.apiError("Couldn't prepare that photo")
        }
        guard let token = TokenStore.accessToken else { throw APIError.notAuthenticated }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"shoe.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard http.statusCode == 200 else { throw APIError.serverError(http.statusCode) }
        return try JSONDecoder().decode(Shoe.self, from: responseData)
    }
}

private extension UIImage {
    /// At most 1200px on the long side, flattened onto white — product shots
    /// are often transparent PNGs and JPEG has no alpha.
    func shoeUploadJPEG() -> Data? {
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }
        let ratio = min(1, 1200 / longest)
        let target = CGSize(width: (size.width * ratio).rounded(), height: (size.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let flattened = UIGraphicsImageRenderer(size: target, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            draw(in: CGRect(origin: .zero, size: target))
        }
        return flattened.jpegData(compressionQuality: 0.85)
    }
}

// MARK: - Store

/// The one in-memory copy of the user's shoes, shared by the profile card,
/// the manage screen and every workout's picker so a change in one place
/// shows in the others without each re-fetching.
@MainActor
@Observable
final class ShoeStore {
    static let shared = ShoeStore()

    private(set) var shoes: [Shoe] = []
    private(set) var hasLoaded = false
    private(set) var loadFailed = false
    private var inFlight: Task<Void, Never>?
    private var loadedAt: Date?

    private init() {}

    /// Pairs still in rotation — the ones a workout can be given.
    var active: [Shoe] { shoes.filter { !$0.isRetired } }
    var retired: [Shoe] { shoes.filter(\.isRetired) }
    /// The pair new `activity` workouts get; nil = none.
    func defaultShoe(for activity: ShoeActivity) -> Shoe? {
        shoes.first { $0.isDefault(for: activity) && !$0.isRetired }
    }

    func shoe(id: String?) -> Shoe? {
        guard let id else { return nil }
        return shoes.first { $0.shoe_id == id }
    }

    /// Loads unless a load finished in the last `maxAge` seconds.
    func refreshIfStale(maxAge: TimeInterval = 60) async {
        if let loadedAt, Date().timeIntervalSince(loadedAt) < maxAge { return }
        await refresh()
    }

    func refresh() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { @MainActor in
            do {
                self.shoes = try await ShoeService.list()
                self.loadFailed = false
                self.loadedAt = Date()
            } catch {
                print("[ShoeStore] load failed: \(error)")
                self.loadFailed = true
            }
            self.hasLoaded = true
        }
        inFlight = task
        await task.value
        inFlight = nil
    }

    /// Creates the pair, then attaches its picture. A failed picture upload
    /// still leaves the shoe saved (it can be given a photo later), and is
    /// reported through the returned flag rather than thrown.
    func add(_ draft: ShoeDraft, image: UIImage?) async throws -> (shoe: Shoe, imageFailed: Bool) {
        var shoe = try await ShoeService.create(draft)
        var imageFailed = false
        if let image {
            do {
                shoe = try await ShoeService.uploadImage(image, shoeId: shoe.shoe_id)
            } catch {
                print("[ShoeStore] image upload failed: \(error)")
                imageFailed = true
            }
        }
        await refresh()
        return (shoe, imageFailed)
    }

    func update(_ shoeId: String, fields: [String: Any]) async throws {
        _ = try await ShoeService.update(shoeId, fields: fields)
        await refresh()
    }

    /// Sets the default for one activity. Returns the pair that lost it when
    /// the sync had given that pair some of the activity's workouts, so the
    /// caller can offer to take it off them.
    @discardableResult
    func setDefault(_ shoeId: String?, for activity: ShoeActivity) async throws -> ShoeDefaultCleanup? {
        let previousName = shoes.first { $0.isDefault(for: activity) }?.name
        let result = try await ShoeService.setDefault(shoeId, for: activity)
        adopt(result.shoes)
        guard let previous = result.previous, previous.auto_assigned > 0 else { return nil }
        return ShoeDefaultCleanup(
            shoeId: previous.shoe_id,
            shoeName: shoe(id: previous.shoe_id)?.name ?? previousName ?? "That pair",
            activity: activity,
            count: previous.auto_assigned
        )
    }

    func clearAutoAssigned(_ cleanup: ShoeDefaultCleanup) async throws {
        let result = try await ShoeService.clearAutoAssigned(cleanup.shoeId, activity: cleanup.activity)
        adopt(result.shoes)
    }

    /// A full list the server just answered with — no second round trip.
    private func adopt(_ list: [Shoe]) {
        shoes = list
        loadFailed = false
        hasLoaded = true
        loadedAt = Date()
    }

    func replaceImage(_ image: UIImage, shoeId: String) async throws {
        _ = try await ShoeService.uploadImage(image, shoeId: shoeId)
        await refresh()
    }

    func delete(_ shoeId: String) async throws {
        try await ShoeService.delete(shoeId)
        shoes.removeAll { $0.shoe_id == shoeId }
        await refresh()
    }

    /// Mileage moved between pairs — re-read the totals.
    func workoutAssignmentChanged() {
        Task { await refresh() }
    }

    /// Account switch / sign-out: never show one person's shoes to the next.
    func reset() {
        shoes = []
        hasLoaded = false
        loadFailed = false
        loadedAt = nil
    }
}
