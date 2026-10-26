import Combine
import Foundation
import Network
import UIKit

/// A finished post that couldn't reach the server — no signal on the walk,
/// a dropped upload — kept on the phone and sent the moment it can be.
///
/// It holds the BAKED pictures, not the editor's state: the poster already
/// arranged the photo, the stickers and the inset and tapped Share. What is
/// left is purely delivery, so a draft is exactly the two uploads and the one
/// create call `PostComposerViewModel.publish` would have made.
struct PostDraft: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    /// The device's local day when it was composed (`DayKeyFormatter`). The
    /// server only takes photos for TODAY's walks, so a draft is postable
    /// until midnight of this day and no later.
    let localDay: String
    var caption: String?
    var workoutId: String?
    var shareToFeed: Bool
    var shareToStory: Bool
    var stats: PostStats?
    var includeRoute: Bool
    var coauthorUserIds: [String]?
    var buddySessionId: String?
    /// Set when this photo joins a walk's existing post as a crew slide.
    var crewPhotoPostId: String?
    var competitionId: String?
    /// `PostPhotoSource` raw value.
    var photoSource: String
    /// FRONT & BACK: the corner the inset was baked into. Non-nil exactly
    /// when there is a swapped frame on disk.
    var dualInsetCorner: String?
    /// The server refused it for a reason a retry can't fix. Shown on the
    /// card with only Delete offered; never retried automatically.
    var stuckMessage: String?
    var attempts: Int = 0

    var isDual: Bool { dualInsetCorner != nil }
    var isExpired: Bool { localDay != DayKeyFormatter.string(from: Date()) }
}

/// Raised by the composer when a FRONT & BACK's swapped frame didn't upload.
/// Transient by definition — publishing without it is what left a baked inset
/// on the feed that could never be tapped.
struct DualFrameUploadError: Error {}

@MainActor
final class PostDraftStore: ObservableObject {
    static let shared = PostDraftStore()

    /// Newest first.
    @Published private(set) var drafts: [PostDraft] = []
    /// Drafts with a send in flight right now.
    @Published private(set) var sending: Set<UUID> = []

    /// Posted when a draft lands, so the feed can pull it in.
    static let didPublish = Notification.Name("MAD_PostDraftPublished")

    private let monitor = NWPathMonitor()
    private var started = false
    private var retryTask: Task<Void, Never>?

    private init() {
        drafts = Self.loadAll()
    }

    /// Watch the connection, and send whatever is waiting. Idempotent.
    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in PostDraftStore.shared.sendPending() }
        }
        monitor.start(queue: DispatchQueue(label: "mad.postdrafts.path"))
        sendPending()
    }

    // MARK: - Saving

    /// Keep a composed post for later. False only if the pictures couldn't be
    /// written, in which case the caller still has them on screen.
    @discardableResult
    func save(_ draft: PostDraft, primary: UIImage, swapped: UIImage?) -> Bool {
        let dir = Self.directory(for: draft.id)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            guard let primaryData = primary.jpegData(compressionQuality: 0.92) else { return false }
            try primaryData.write(to: dir.appendingPathComponent("primary.jpg"), options: .atomic)
            if let swapped, let data = swapped.jpegData(compressionQuality: 0.92) {
                try data.write(to: dir.appendingPathComponent("swapped.jpg"), options: .atomic)
            }
            try JSONEncoder().encode(draft)
                .write(to: dir.appendingPathComponent("draft.json"), options: .atomic)
        } catch {
            print("[PostDrafts] save failed: \(error)")
            try? FileManager.default.removeItem(at: dir)
            return false
        }
        drafts.removeAll { $0.id == draft.id }
        drafts.insert(draft, at: 0)
        scheduleRetry()
        return true
    }

    func delete(_ draft: PostDraft) {
        try? FileManager.default.removeItem(at: Self.directory(for: draft.id))
        drafts.removeAll { $0.id == draft.id }
    }

    func primaryImage(for draft: PostDraft) -> UIImage? {
        UIImage(contentsOfFile: Self.directory(for: draft.id).appendingPathComponent("primary.jpg").path)
    }

    private func swappedImage(for draft: PostDraft) -> UIImage? {
        UIImage(contentsOfFile: Self.directory(for: draft.id).appendingPathComponent("swapped.jpg").path)
    }

    private func update(_ draft: PostDraft) {
        guard let index = drafts.firstIndex(where: { $0.id == draft.id }) else { return }
        drafts[index] = draft
        try? JSONEncoder().encode(draft).write(
            to: Self.directory(for: draft.id).appendingPathComponent("draft.json"), options: .atomic)
    }

    // MARK: - Sending

    /// Everything still worth trying: not stuck, not from a day that's over.
    var pending: [PostDraft] { drafts.filter { $0.stuckMessage == nil && !$0.isExpired } }

    func sendPending() {
        guard TokenStore.hasTokens else { return }
        for draft in pending where !sending.contains(draft.id) {
            Task { await send(draft) }
        }
    }

    /// One delivery attempt. True when the post is on the server.
    @discardableResult
    func send(_ original: PostDraft) async -> Bool {
        guard !sending.contains(original.id), !original.isExpired else { return false }
        guard let primary = primaryImage(for: original) else {
            delete(original)
            return false
        }
        sending.insert(original.id)
        defer { sending.remove(original.id) }

        var draft = original
        draft.attempts += 1
        do {
            let mediaUrl = try await PostService.uploadMedia(primary)
            var dualMediaUrl: String?
            if draft.isDual {
                // Never without it — a draft exists precisely so the pair
                // arrives whole.
                guard let swapped = swappedImage(for: draft) else { throw DualFrameUploadError() }
                dualMediaUrl = try await PostService.uploadMedia(swapped)
            }
            try await deliver(&draft, mediaUrl: mediaUrl, dualMediaUrl: dualMediaUrl)
            finishPublished(draft)
            return true
        } catch {
            if let message = Self.terminalMessage(for: error) {
                draft.stuckMessage = message
            }
            update(draft)
            scheduleRetry()
            print("[PostDrafts] send attempt \(draft.attempts) failed: \(error)")
            return false
        }
    }

    /// The create (or crew-slide) call, with the two refusals a draft can
    /// still recover from on its own.
    private func deliver(_ draft: inout PostDraft, mediaUrl: String, dualMediaUrl: String?) async throws {
        let source = PostPhotoSource(rawValue: draft.photoSource) ?? .library
        do {
            try await create(draft, mediaUrl: mediaUrl, dualMediaUrl: dualMediaUrl, source: source)
        } catch let APIError.apiError(message) where message == "post_window_closed" && source == .camera {
            // The camera's ten minutes ran out while there was no signal. The
            // shot was taken on the walk and is in the camera roll, which is
            // the library tier's whole claim — so it posts as what it now is.
            draft.photoSource = PostPhotoSource.library.rawValue
            try await create(draft, mediaUrl: mediaUrl, dualMediaUrl: dualMediaUrl, source: .library)
        } catch let APIError.buddyWalkAlreadyPosted(postId, mine) where !mine && postId != nil {
            // Someone else on the walk posted it while this sat waiting —
            // the photo joins their card as this user's slide, exactly the
            // handoff the composer makes.
            draft.crewPhotoPostId = postId
            try await create(draft, mediaUrl: mediaUrl, dualMediaUrl: dualMediaUrl, source: source)
        }
    }

    private func create(_ draft: PostDraft, mediaUrl: String, dualMediaUrl: String?,
                        source: PostPhotoSource) async throws {
        let corner = dualMediaUrl == nil ? nil : draft.dualInsetCorner
        if let crewPostId = draft.crewPhotoPostId {
            try await PostService.addCrewPhoto(
                postId: crewPostId,
                mediaUrl: mediaUrl,
                caption: draft.caption,
                photoSource: source,
                dualMediaUrl: dualMediaUrl,
                dualInsetCorner: corner
            )
            return
        }
        _ = try await PostService.createPost(
            mediaUrl: mediaUrl,
            dualMediaUrl: dualMediaUrl,
            dualInsetCorner: corner,
            caption: draft.caption,
            workoutId: draft.workoutId,
            shareToFeed: draft.shareToFeed,
            shareToStory: draft.shareToStory,
            stats: draft.stats,
            isAuto: false,
            includeRoute: draft.includeRoute,
            coauthorUserId: nil,
            coauthorUserIds: draft.shareToFeed ? draft.coauthorUserIds : nil,
            buddySessionId: draft.shareToFeed ? draft.buddySessionId : nil,
            photoSource: source,
            competitionId: draft.competitionId
        )
    }

    private func finishPublished(_ draft: PostDraft) {
        // The same bookkeeping `publish()` does on a live post: the run has
        // its one deliberate post, so nothing offers it again.
        if let workoutId = draft.workoutId, !workoutId.isEmpty {
            PostedWorkoutRegistry.markPosted(workoutId)
            CelebrationManager.shared.resolvePhotoPrompt(forWorkout: workoutId)
        }
        BuddyPostOffer.clear()
        delete(draft)
        NotificationCenter.default.post(name: Self.didPublish, object: nil)
    }

    /// Back off while something is waiting and the path claims to be fine —
    /// NWPathMonitor only speaks on a CHANGE, and a server blip or a weak
    /// signal that reads as "satisfied" would otherwise never be retried.
    private func scheduleRetry() {
        guard retryTask == nil, !pending.isEmpty else { return }
        let attempts = pending.map(\.attempts).min() ?? 0
        let delay = min(300, 15 * pow(2, Double(min(attempts, 5))))
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.retryTask = nil
                self?.sendPending()
            }
        }
    }

    // MARK: - Classification

    /// A failure a later attempt can fix: no connection, a dropped upload, a
    /// server having a moment.
    nonisolated static func isTransient(_ error: Error) -> Bool {
        if error is DualFrameUploadError { return true }
        if let urlError = error as? URLError {
            return urlError.code != .cancelled && urlError.code != .userAuthenticationRequired
        }
        switch error {
        case PostError.uploadFailed(let code):
            return code == 0 || code == 408 || code == 429 || code >= 500
        case APIError.serverError, APIError.rateLimited, APIError.networkError,
             APIError.invalidResponse, APIError.tokenRefreshFailed:
            return true
        default:
            return false
        }
    }

    /// The copy for a refusal no retry can fix, or nil to keep trying.
    private static func terminalMessage(for error: Error) -> String? {
        if isTransient(error) { return nil }
        switch error {
        case APIError.apiError(let message) where message == "mile_not_completed":
            // The server just hasn't got the walk yet.
            Task { try? await WorkoutSyncService.shared.syncNewWorkouts() }
            return nil
        case APIError.apiError(let message) where message == "post_window_closed":
            return "Couldn't post — there's no walk or run on the server for today."
        case APIError.apiError(let message) where message == "terms_not_accepted":
            return "Accept the community guidelines, then try again."
        case APIError.conflict, APIError.buddyWalkAlreadyPosted:
            return "This walk already has a post."
        default:
            return (error as? LocalizedError)?.errorDescription ?? "Couldn't post this draft."
        }
    }

    // MARK: - Disk

    private static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PostDrafts", isDirectory: true)
    }

    private static func directory(for id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private static func loadAll() -> [PostDraft] {
        let dirs = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)) ?? []
        return dirs
            .compactMap { dir in
                guard let data = try? Data(contentsOf: dir.appendingPathComponent("draft.json")) else {
                    // A save that died between the picture and the metadata.
                    try? FileManager.default.removeItem(at: dir)
                    return nil
                }
                return try? JSONDecoder().decode(PostDraft.self, from: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
