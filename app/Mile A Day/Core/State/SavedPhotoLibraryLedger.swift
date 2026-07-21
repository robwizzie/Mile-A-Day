import Combine
import Foundation

/// Remembers which mid-run snaps are already in the user's photo library, so
/// the review gallery can show "Saved" and refuse to save the same shot twice.
///
/// Keyed by `MidRunPhotoStash.Entry.id` (the snap's stash filename). Every
/// in-app capture auto-saves to the camera roll at shutter time and every
/// library import obviously already lives there — this ledger is how the UI
/// knows which entries are covered without re-hitting Photos. Persisted so the
/// state survives the mid-run → post-run-prompt hop and an app relaunch;
/// pruned to the live stash on read so it can't grow without bound.
final class SavedPhotoLibraryLedger: ObservableObject {
    static let shared = SavedPhotoLibraryLedger()

    private static let storeKey = "savedPhotoLibraryLedger.v1"
    /// Backstop cap — the stash tops out at 5 and is cleared each run, so this
    /// is only reached if pruning never runs (e.g. a capture-heavy session
    /// that never opens the gallery).
    private static let maxKeys = 500

    @Published private(set) var savedIds: Set<String>

    private init() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.storeKey) ?? []
        savedIds = Set(stored)
    }

    /// Whether this snap is known to already be in the photo library.
    func contains(_ id: String) -> Bool { savedIds.contains(id) }

    /// Record that this snap landed in the photo library.
    func markSaved(_ id: String) {
        guard !savedIds.contains(id) else { return }
        savedIds.insert(id)
        persist()
    }

    /// Drop keys no longer backed by a live stash entry. Call with the current
    /// stash ids (e.g. when the gallery appears) to keep the store bounded.
    func prune(keeping liveIds: [String]) {
        let trimmed = savedIds.intersection(liveIds)
        guard trimmed != savedIds else { return }
        savedIds = trimmed
        persist()
    }

    private func persist() {
        var ids = Array(savedIds)
        if ids.count > Self.maxKeys { ids = Array(ids.suffix(Self.maxKeys)) }
        UserDefaults.standard.set(ids, forKey: Self.storeKey)
    }
}
