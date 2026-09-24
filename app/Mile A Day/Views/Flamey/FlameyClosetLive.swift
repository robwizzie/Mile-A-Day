import SwiftUI
import Combine

// FLAMEY'S CLOSET — the live glue: presenting it, saving what's chosen,
// restoring it on a new phone, and announcing new items. The screen and the
// unlock card themselves are pure (FlameyClosetView / FlameyUnlockView).

// MARK: - Presenting

/// "Open Flamey's Closet" from anywhere — the hero's hanger, the profile
/// row, Settings, a friend's wardrobe sheet, the unlock card and
/// `mileaday://flamey-closet`. Presented ONCE, at MainTabView root, so a
/// request from any tab (or before any tab exists, on a cold launch from the
/// deep link) still lands. Fun-only: a request on Modern does nothing.
@MainActor
final class FlameyClosetLink: ObservableObject {
    static let shared = FlameyClosetLink()

    struct Request: Identifiable, Equatable {
        let id = UUID()
        /// Items to mark New beyond the unseen ones (the batch unlock card).
        var highlight: Set<FlameyItem> = []
        /// Where to open (the first highlighted item's tab and slot).
        var focus: FlameyItem? = nil
    }

    @Published var pending: Request?

    private init() {}

    func open(highlighting items: Set<FlameyItem> = [], focus: FlameyItem? = nil) {
        guard DashboardStylePreference.current == .fun else { return }
        pending = Request(highlight: items, focus: focus)
    }

    /// The same, raised only AFTER a sheet has finished dismissing — a
    /// presentation raised in a dismissal's own transaction is the one
    /// SwiftUI silently drops (see `PostDeepLink.openAfterDismiss`).
    func openAfterDismiss(highlighting items: Set<FlameyItem> = [], focus: FlameyItem? = nil) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.open(highlighting: items, focus: focus)
        }
    }
}

// MARK: - "New" dots

/// Items this account has SEEN in the Closet. New = owned − seen. Absent
/// (never opened, fresh install) means nothing is new yet: it is seeded, not
/// shouted — only what unlocks AFTER the seed earns a dot.
enum FlameySeenLedger {
    private static let prefix = "flameySeenItemsV1|"

    private static var key: String? {
        guard let me = UserDefaults.standard.string(forKey: "backendUserId"), !me.isEmpty else { return nil }
        return prefix + me
    }

    static func seen() -> Set<FlameyItem>? {
        guard let key, let raw = UserDefaults.standard.stringArray(forKey: key) else { return nil }
        return Set(raw.compactMap(FlameyItem.init(rawValue:)))
    }

    static func markSeen(_ items: Set<FlameyItem>) {
        guard let key else { return }
        let union = (seen() ?? []).union(items)
        UserDefaults.standard.set(union.map(\.rawValue).sorted(), forKey: key)
    }

    /// Seeds the ledger if it has never been written.
    static func seedIfAbsent(_ items: Set<FlameyItem>) {
        guard seen() == nil else { return }
        markSeen(items)
    }

    static func unseen(in owned: Set<FlameyItem>) -> Set<FlameyItem> {
        guard let seen = seen() else { return [] }
        return owned.subtracting(seen).filter { $0.unlock != .always }
    }
}

// MARK: - Server sync

/// Saving and restoring the Closet choice (`PUT /users/:id/flamey-look`,
/// `GET /users/:id/flamey-closet`).
///
/// Local first: `FlameyFacts.setChoice` is the truth this phone draws from
/// (and mirrors to the widget) the instant a tile is tapped; the server copy
/// follows, debounced. A change that hasn't reached the server is DIRTY
/// (persisted per account), so it survives a relaunch offline and is pushed
/// on the next launch/foreground BEFORE any pull — otherwise the pull would
/// hand back the old look and silently undo it. A 400 (an item the server
/// doesn't think is owned) re-syncs from the server's copy.
@MainActor
enum FlameyClosetSync {
    private static let dirtyPrefix = "flameyLookDirtyV1|"
    private static let serverOwnedPrefix = "flameyServerOwnedV1|"
    private static var pushTask: Task<Void, Never>?
    private static var lastPullAt: Date?

    private static var userId: String? {
        guard let me = UserDefaults.standard.string(forKey: "backendUserId"), !me.isEmpty else { return nil }
        return me
    }

    private static var isDirty: Bool {
        get { userId.map { UserDefaults.standard.bool(forKey: dirtyPrefix + $0) } ?? false }
        set { if let userId { UserDefaults.standard.set(newValue, forKey: dirtyPrefix + userId) } }
    }

    /// What the server last said this account owns — fills the gap on a new
    /// phone before the badge list has loaded. Never used to REMOVE items.
    static var serverOwned: Set<FlameyItem> {
        guard let userId, let raw = UserDefaults.standard.stringArray(forKey: serverOwnedPrefix + userId) else { return [] }
        return Set(raw.compactMap(FlameyItem.init(rawValue:)))
    }

    private static func storeServerOwned(_ ids: [String]?) {
        guard let userId, let ids else { return }
        UserDefaults.standard.set(ids, forKey: serverOwnedPrefix + userId)
    }

    /// The choice changed on this phone: keep it locally now, push shortly.
    static func choiceChanged(_ choice: FlameyLookChoice) {
        FlameyFacts.setChoice(choice)
        // The hero and the profile row observe the link purely to redraw
        // when his look changes (it lives in UserDefaults).
        FlameyClosetLink.shared.objectWillChange.send()
        isDirty = true
        pushTask?.cancel()
        pushTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            await push()
        }
    }

    /// Push now (the Closet closing) instead of waiting out the debounce.
    static func flush() {
        guard isDirty else { return }
        pushTask?.cancel()
        pushTask = Task { @MainActor in await push() }
    }

    /// `{"look": {...}}`, or `{"look": null}` for all-auto — the key must
    /// be PRESENT (synthesized Encodable would omit a nil, and the server
    /// answers a missing `look` with 400).
    private struct Body: Encodable {
        let look: FlameyLookChoice?
        enum CodingKeys: String, CodingKey { case look }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(look, forKey: .look)
        }
    }
    private struct Closet: Decodable {
        let look: FlameyLookChoice?
        let owned_item_ids: [String]?
    }

    private static func push() async {
        // `fancyFetch` SIGNS THE USER OUT with no token — defer instead.
        guard TokenStore.hasTokens, let userId, isDirty else { return }
        let choice = FlameyFacts.choice
        guard let body = try? JSONEncoder().encode(Body(look: choice.isAllAuto ? nil : choice)) else { return }
        do {
            let saved = try await APIClient.fancyFetch(endpoint: "/users/\(userId)/flamey-look", method: .PUT,
                                                       body: body, responseType: Closet.self)
            storeServerOwned(saved.owned_item_ids)
            // Only clear if nothing newer was chosen while this was in flight.
            if FlameyFacts.choice == choice { isDirty = false }
        } catch APIError.badRequest {
            // The server refused an item (not owned there, or unknown to it):
            // its copy wins, and the phone stops insisting.
            isDirty = false
            await pull(force: true)
        } catch {
            // Offline / server trouble: stays dirty, retried at the next
            // launch, foreground or change.
        }
    }

    /// Launch / foreground (Fun only). Pushes a pending local change first;
    /// otherwise adopts the server's look, which is how a reinstall or a new
    /// phone gets its Flamey back.
    static func syncOnForeground() async {
        guard DashboardStylePreference.current == .fun, TokenStore.hasTokens, userId != nil else { return }
        if isDirty {
            await push()
            return
        }
        if let last = lastPullAt, Date().timeIntervalSince(last) < 60 { return }
        await pull(force: false)
    }

    private static func pull(force: Bool) async {
        guard TokenStore.hasTokens, let userId else { return }
        guard force || !isDirty else { return }
        lastPullAt = Date()
        guard let closet = try? await APIClient.fancyFetch(endpoint: "/users/\(userId)/flamey-closet",
                                                           responseType: Closet.self) else { return }
        storeServerOwned(closet.owned_item_ids)
        // A local change made while this was in flight wins.
        guard force || !isDirty else { return }
        FlameyFacts.applyServerChoice(closet.look ?? .auto)
        FlameyClosetLink.shared.objectWillChange.send()
    }
}

// MARK: - The screen, live

/// FlameyClosetView fed from the account's facts and saving through
/// `FlameyClosetSync`. What the host presents.
struct FlameyClosetScreen: View {
    let request: FlameyClosetLink.Request
    @Environment(\.dismiss) private var dismiss
    @State private var model: FlameyClosetModel

    init(request: FlameyClosetLink.Request) {
        self.request = request
        _model = State(initialValue: Self.makeModel(request))
    }

    var body: some View {
        FlameyClosetView(model: model, onDone: { dismiss() })
            .onDisappear {
                FlameySeenLedger.markSeen(model.owned)
                FlameyClosetSync.flush()
            }
    }

    @MainActor
    private static func makeModel(_ request: FlameyClosetLink.Request) -> FlameyClosetModel {
        let owned = FlameyFacts.ownedItems.union(FlameyClosetSync.serverOwned)
        let user = UserManager.shared.currentUser
        let completed = ChallengeService.shared.allCompletions().count
        let facts = FlameyProgressFacts(
            currentStreak: user.streak,
            totalMiles: user.totalMiles,
            fastestPaceMinutes: user.fastestMilePace,
            mostMilesInADay: user.mostMilesInOneDay,
            challengesCompleted: completed > 0 ? completed : nil,
            formatDistance: { "\($0.distanceToGoText) \(DistanceUnits.current.abbreviation)" }
        )
        let fresh = FlameySeenLedger.unseen(in: owned).union(request.highlight.intersection(owned))
        let model = FlameyClosetModel(owned: owned, choice: FlameyFacts.choice, newItems: fresh, facts: facts,
                                      signupDate: FlameyFacts.signupDate, focus: request.focus)
        model.onChoiceChange = { FlameyClosetSync.choiceChanged($0) }
        return model
    }
}

// MARK: - Unlock moments

/// Which wardrobe items this account has been TOLD about. The delta against
/// what it owns is the unlock moment; the Celebration stamps the ledger at
/// dismissal (`CelebrationManager.markConsumed` → `FlameyUnlockLedger`).
@MainActor
enum FlameyUnlocks {
    /// Called after every successful badge fetch. `allowAnnounce` is false
    /// until the first-run badge sync has finished (a new account's history
    /// must not be announced one batch at a time mid-import).
    ///
    /// Absent ledger (existing users on first run of this build, reinstalls)
    /// is SEEDED with what's owned right now, silently — those items aren't
    /// news. Anything unlocked after that is.
    static func reconcile(allowAnnounce: Bool) {
        let owned = FlameyFacts.ownedItems.filter { $0.unlock != .always && !$0.isMoodProp }
        let ids = Set(owned.map(\.rawValue))
        guard let announced = FlameyUnlockLedger.announced() else {
            FlameyUnlockLedger.markAnnounced(ids)
            FlameySeenLedger.seedIfAbsent(Set(owned))
            return
        }
        let fresh = ids.subtracting(announced)
        guard !fresh.isEmpty, allowAnnounce else { return }
        guard DashboardStylePreference.current == .fun else {
            // Never shown on Modern — and not saved up for later either: the
            // Closet's New dots are what tells a returning Fun user.
            FlameyUnlockLedger.markAnnounced(fresh)
            return
        }
        CelebrationManager.shared.addCelebration(.flameyUnlocked(itemIds: fresh.sorted()))
    }
}

/// The CelebrationContainer's view for `.flameyUnlocked`: resolves the ids,
/// draws FlameyUnlockView, and does what its buttons say. Dismissal goes
/// through the manager so the ledger is stamped then, never on display.
struct FlameyUnlockCelebrationHost: View {
    let itemIds: [String]
    @ObservedObject private var celebrations = CelebrationManager.shared

    private var items: [FlameyItem] {
        itemIds.compactMap(FlameyItem.init(rawValue:))
            .sorted { ($0.slot.sortIndex, -$0.tier) < ($1.slot.sortIndex, -$1.tier) }
    }

    /// The medal behind a single unlock, from the badge list.
    private var medalName: String? {
        guard items.count == 1, let id = items[0].badgeId else { return nil }
        return UserManager.shared.currentUser.badges.first { $0.id == id }?.name
    }

    var body: some View {
        if DashboardStylePreference.current == .fun, !items.isEmpty {
            FlameyUnlockView(
                items: items,
                owned: FlameyFacts.ownedItems,
                choice: FlameyFacts.choice,
                medalName: medalName,
                onWear: { item in
                    var choice = FlameyFacts.choice
                    choice[item.slot] = .item(item)
                    FlameyClosetSync.choiceChanged(choice)
                    FlameySeenLedger.markSeen([item])
                    celebrations.dismissCurrentCelebration()
                },
                onOpenCloset: {
                    let highlight = Set(items)
                    celebrations.dismissCurrentCelebration()
                    FlameyClosetLink.shared.openAfterDismiss(highlighting: highlight, focus: items.first)
                },
                onLater: { celebrations.dismissCurrentCelebration() }
            )
            .transition(.opacity)
        } else {
            // Style changed since it was queued (or the ids are from a newer
            // catalog): a real view — never EmptyView, which gets no
            // lifecycle — that steps aside at once.
            Color.clear.onAppear { celebrations.dismissCurrentCelebration() }
        }
    }
}

// MARK: - Root host

/// MainTabView's one presentation of the Closet.
struct FlameyClosetPresenter: ViewModifier {
    @ObservedObject private var link = FlameyClosetLink.shared

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $link.pending) { request in
                FlameyClosetScreen(request: request)
            }
    }
}

extension View {
    /// Hosts Flamey's Closet (see `FlameyClosetLink`). MainTabView root only.
    func flameyClosetHost() -> some View { modifier(FlameyClosetPresenter()) }
}

// MARK: - Entry points

/// The Fun hero's way into the Closet: a labelled capsule under Flamey (the
/// top-left corner is his; the top-right holds savers + Share).
struct HeroClosetButton: View {
    var body: some View {
        FlameyClosetPill {
            MADHaptics.action()
            FlameyClosetLink.shared.open()
        }
    }
}

/// "Customize Flamey" on your own profile (Fun only).
struct FlameyClosetProfileRow: View {
    @AppStorage(DashboardStylePreference.key) private var styleRaw = DashboardStyle.modern.rawValue
    /// Re-reads the look when the Closet closes (the choice lives in
    /// UserDefaults, which nothing here observes).
    @ObservedObject private var link = FlameyClosetLink.shared

    var body: some View {
        if styleRaw == DashboardStyle.fun.rawValue, let look = FlameyFacts.look(detail: .compact) {
            let owned = FlameyFacts.ownedItems.union(FlameyClosetSync.serverOwned)
            FlameyClosetProfileCard(
                look: look,
                unlocked: owned.filter { $0.unlock != .always && !$0.isMoodProp }.count,
                total: FlameyItem.closet.filter { $0.unlock != .always }.count,
                fresh: FlameySeenLedger.unseen(in: owned).count
            ) {
                MADHaptics.action()
                FlameyClosetLink.shared.open()
            }
        }
    }
}
