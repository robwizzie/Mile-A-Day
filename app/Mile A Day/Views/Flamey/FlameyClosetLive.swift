import SwiftUI
import Combine
import HealthKit

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
        /// Open on the "what you've unlocked" walkthrough even if it has been
        /// taken before (it always opens on the FIRST visit).
        var journey: Bool = false
        /// Open `focus`'s card on arrival (a medal's "See it in Flamey's
        /// Closet", `mileaday://flamey-closet?item=<id>`).
        var openDetail: Bool = false
    }

    @Published var pending: Request?

    private init() {}

    func open(highlighting items: Set<FlameyItem> = [], focus: FlameyItem? = nil, journey: Bool = false,
              openDetail: Bool = false) {
        guard DashboardStylePreference.current == .fun else { return }
        pending = Request(highlight: items, focus: focus, journey: journey, openDetail: openDetail && focus != nil)
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

    /// `{"look": {...}}`, or `{"look": null}` for basic — the key must
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
        /// nil = the server didn't send `name` (older server); `.some(nil)`
        /// = it did, and he's "Flamey".
        let name: String??
        /// nil = no `outfits` key (older server).
        let outfits: [OutfitDTO]?

        enum CodingKeys: String, CodingKey { case look, owned_item_ids, name, outfits }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            look = try? c.decodeIfPresent(FlameyLookChoice.self, forKey: .look)
            owned_item_ids = try? c.decodeIfPresent([String].self, forKey: .owned_item_ids)
            if c.contains(.name) {
                name = .some((try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil)
            } else {
                name = nil
            }
            outfits = try? c.decodeIfPresent([OutfitDTO].self, forKey: .outfits)
        }
    }

    /// A saved outfit as the server serves it. Timestamps are ISO strings
    /// (never `Date` — the shared decoder can't read fractional seconds).
    struct OutfitDTO: Decodable {
        let id: String
        let name: String
        let look: FlameyLookChoice?
        let created_at: String?
        let updated_at: String?
        let owned_ok: Bool?

        func outfit(localId: String? = nil) -> FlameyOutfit {
            FlameyOutfit(id: localId ?? id, serverId: id, name: name, look: look ?? .basic, ownedOK: owned_ok ?? true)
        }
    }

    private static func push() async {
        // `fancyFetch` SIGNS THE USER OUT with no token — defer instead.
        guard TokenStore.hasTokens, let userId, isDirty else { return }
        let choice = FlameyFacts.choice
        guard let body = try? JSONEncoder().encode(Body(look: choice.isBasic ? nil : choice)) else { return }
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
        // A name or outfit list kept offline goes up first, like the look.
        if isNameDirty { _ = await pushName(FlameyFacts.name) }
        if isOutfitsDirty { _ = await pushOutfits(outfits) }
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
        // Another phone may have renamed him or changed the outfits; a
        // change still waiting to go up from THIS phone wins.
        if let name = closet.name, !isNameDirty {
            FlameyFacts.setName(name)
        }
        if let served = closet.outfits, !isOutfitsDirty {
            storeOutfits(served.map { $0.outfit() })
        }
        // A local change made while this was in flight wins.
        guard force || !isDirty else {
            FlameyClosetLink.shared.objectWillChange.send()
            return
        }
        FlameyFacts.applyServerChoice(closet.look ?? .basic)
        FlameyClosetLink.shared.objectWillChange.send()
    }

    // MARK: His name (`PUT /users/:id/flamey-name`)

    private static let nameDirtyPrefix = "flameyNameDirtyV1|"

    private static var isNameDirty: Bool {
        get { userId.map { UserDefaults.standard.bool(forKey: nameDirtyPrefix + $0) } ?? false }
        set { if let userId { UserDefaults.standard.set(newValue, forKey: nameDirtyPrefix + userId) } }
    }

    private struct NameBody: Encodable {
        let name: String?
        enum CodingKeys: String, CodingKey { case name }
        // `{"name": null}` resets him — the key must be PRESENT.
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(name, forKey: .name)
        }
    }
    private struct NameAck: Decodable { let name: String? }

    /// Renames him. Refused ⇒ why, in words (the name is left alone).
    /// Offline ⇒ kept here and pushed at the next launch/foreground. An
    /// older server (404) ⇒ kept on this phone only.
    static func rename(_ name: String?) async -> FlameySaveOutcome {
        guard TokenStore.hasTokens, userId != nil else {
            FlameyFacts.setName(name)
            isNameDirty = true
            FlameyClosetLink.shared.objectWillChange.send()
            return .deferred
        }
        let outcome = await pushName(name)
        if !outcome.isRejected { FlameyClosetLink.shared.objectWillChange.send() }
        return outcome
    }

    private static func pushName(_ name: String?) async -> FlameySaveOutcome {
        guard TokenStore.hasTokens, let userId,
              let body = try? JSONEncoder().encode(NameBody(name: name)) else { return .deferred }
        do {
            let ack = try await APIClient.fancyFetch(endpoint: "/users/\(userId)/flamey-name", method: .PUT,
                                                     body: body, responseType: NameAck.self)
            FlameyFacts.setName(ack.name)
            isNameDirty = false
            return .saved
        } catch APIError.badRequest(let error) where error.hasPrefix("invalid_flamey_name") {
            // The body's `reason` isn't carried by APIError; every rule but
            // the blocklist is mirrored here, so a name that passes locally
            // was refused by the blocklist.
            isNameDirty = false
            if let raw = name, case .failure(let issue) = FlameyNameRules.validate(raw) {
                return .rejected(issue.message())
            }
            return .rejected(FlameyNameIssue.notAllowed.message())
        } catch APIError.badRequest {
            isNameDirty = false
            return .rejected(FlameyNameIssue.notAllowed.message())
        } catch APIError.notFound {
            // An older server: the name lives on this phone.
            FlameyFacts.setName(name)
            isNameDirty = false
            return .saved
        } catch {
            FlameyFacts.setName(name)
            isNameDirty = true
            return .deferred
        }
    }

    // MARK: Saved outfits (`PUT /users/:id/flamey-outfits`)

    private static let outfitsPrefix = "flameyOutfitsV1|"
    private static let outfitsDirtyPrefix = "flameyOutfitsDirtyV1|"

    private static var isOutfitsDirty: Bool {
        get { userId.map { UserDefaults.standard.bool(forKey: outfitsDirtyPrefix + $0) } ?? false }
        set { if let userId { UserDefaults.standard.set(newValue, forKey: outfitsDirtyPrefix + userId) } }
    }

    /// This account's outfits as this phone last knew them.
    static var outfits: [FlameyOutfit] {
        guard let userId, let data = UserDefaults.standard.data(forKey: outfitsPrefix + userId),
              let list = try? JSONDecoder().decode([FlameyOutfit].self, from: data) else { return [] }
        return list
    }

    private static func storeOutfits(_ list: [FlameyOutfit]) {
        guard let userId, let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: outfitsPrefix + userId)
    }

    private struct OutfitsBody: Encodable {
        struct Entry: Encodable {
            let id: String?
            let name: String
            let look: FlameyLookChoice
            enum CodingKeys: String, CodingKey { case id, name, look }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(id, forKey: .id)
                try c.encode(name, forKey: .name)
                try c.encode(look, forKey: .look)
            }
        }
        let outfits: [Entry]
    }
    private struct OutfitsAck: Decodable { let outfits: [OutfitDTO]? }

    /// Replaces the list. Returns the outcome and — when the server answered —
    /// its copy, with this phone's ids kept (the server keeps the order, so
    /// entry i IS entry i), so nothing on screen changes identity.
    static func saveOutfits(_ list: [FlameyOutfit]) async -> (FlameySaveOutcome, [FlameyOutfit]?) {
        let outcome = await pushOutfits(list)
        switch outcome.0 {
        case .rejected: return outcome
        case .saved, .deferred:
            if outcome.1 == nil { storeOutfits(list) }
            return outcome
        }
    }

    private static func pushOutfits(_ list: [FlameyOutfit]) async -> (FlameySaveOutcome, [FlameyOutfit]?) {
        guard TokenStore.hasTokens, let userId else {
            isOutfitsDirty = true
            return (.deferred, nil)
        }
        // Only what's owned goes up — the server refuses a look naming
        // anything else, and an outfit is worn without it anyway.
        let owned = FlameyFacts.ownedItems.union(serverOwned)
        let entries = list.map { outfit -> OutfitsBody.Entry in
            var look = outfit.look
            for slot in FlameySlot.allCases where look[slot].map({ !owned.contains($0) && $0.unlock != .always }) == true {
                look[slot] = nil
            }
            return .init(id: outfit.serverId, name: outfit.name, look: look)
        }
        guard let body = try? JSONEncoder().encode(OutfitsBody(outfits: entries)) else { return (.deferred, nil) }
        do {
            let ack = try await APIClient.fancyFetch(endpoint: "/users/\(userId)/flamey-outfits", method: .PUT,
                                                     body: body, responseType: OutfitsAck.self)
            isOutfitsDirty = false
            guard let served = ack.outfits else { return (.saved, nil) }
            let merged = served.enumerated().map { i, dto in
                dto.outfit(localId: served.count == list.count ? list[i].id : nil)
            }
            storeOutfits(merged)
            return (.saved, merged)
        } catch APIError.badRequest(let error) {
            isOutfitsDirty = false
            if error.hasPrefix("too_many_outfits") {
                return (.rejected("All \(FlameyOutfit.max) outfit slots are full — pick one to replace."), nil)
            }
            if error.hasPrefix("invalid_outfit_name") {
                return (.rejected(FlameyNameIssue.notAllowed.message(maxLength: FlameyNameRules.outfitMaxLength)), nil)
            }
            if error.hasPrefix("invalid_flamey_look") {
                return (.rejected("Something in this look isn't unlocked on your account yet."), nil)
            }
            return (.rejected("Couldn't save that outfit — try again."), nil)
        } catch APIError.notFound {
            // An older server: outfits live on this phone, and go up once
            // the server knows them (kept dirty, retried on foreground).
            isOutfitsDirty = true
            return (.saved, nil)
        } catch {
            isOutfitsDirty = true
            return (.deferred, nil)
        }
    }
}

// MARK: - First-run walkthrough

/// Whether this account has taken (or skipped) the Closet's "what you've
/// unlocked" walkthrough. Stamped when it ENDS, never when it shows — the
/// celebration rule: a walkthrough torn down mid-page is offered again.
enum FlameyJourneyLedger {
    private static let prefix = "flameyJourneySeenV1|"

    private static var key: String? {
        guard let me = UserDefaults.standard.string(forKey: "backendUserId"), !me.isEmpty else { return nil }
        return prefix + me
    }

    static var seen: Bool {
        guard let key else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func markSeen() {
        guard let key else { return }
        UserDefaults.standard.set(true, forKey: key)
    }
}

// MARK: - Medals, from the app's badge catalog

/// Builds the Closet's medal facts from what the app already knows: the
/// user's earned badges (name + the day they earned it), the catalog's names
/// for the ones they haven't (fetched once, remembered), and the Badges
/// screen's own icon + rarity rules (`iconName(for:)`, `Badge.rarity`), so a
/// medal looks the same in the Closet as on the Badges shelf.
@MainActor
enum FlameyMedalCatalog {
    private static let namesKey = "flameyMedalNamesV1"
    private static var fetchedThisLaunch = false

    private static var cachedNames: [String: String] {
        (UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String]) ?? [:]
    }

    static func medals() -> [String: FlameyMedalInfo] {
        let earned = Dictionary(UserManager.shared.currentUser.badges.filter { !$0.isLocked }.map { ($0.id, $0) },
                                uniquingKeysWith: { first, _ in first })
        let names = cachedNames
        let details = BadgeEarnedDetails.all()
        var out: [String: FlameyMedalInfo] = [:]
        for id in FlameyWardrobe.catalogBadgeIds {
            let badge = earned[id] ?? Badge(id: id, name: names[id] ?? "", description: "")
            let name = earned[id]?.name ?? names[id] ?? HolidayKey(badgeId: id)?.medalName
            let rarity: FlameyMedalRarity
            switch badge.rarity {
            case .common: rarity = .common
            case .rare: rarity = .rare
            case .legendary: rarity = .legendary
            }
            let detail = earned[id] != nil ? details[id] : nil
            out[id] = FlameyMedalInfo(badgeId: id, name: name, icon: iconName(for: badge), rarity: rarity,
                                      earnedAt: earned[id]?.dateAwarded, isEarned: earned[id] != nil,
                                      earnedSummary: detail?.summary,
                                      earnedDay: FlameyClosetCopy.parseDay(detail?.date),
                                      earnedWorkoutId: detail?.workoutId)
        }
        return out
    }

    /// The catalog's names for medals not yet earned — once per launch, then
    /// remembered for offline opens. Calls back only when something changed.
    static func refreshNames(_ onChange: @escaping () -> Void) {
        guard !fetchedThisLaunch, TokenStore.hasTokens else { return }
        fetchedThisLaunch = true
        Task { @MainActor in
            guard let catalog = try? await BadgeAPIService.fetchCatalog() else {
                fetchedThisLaunch = false
                return
            }
            let wanted = FlameyWardrobe.catalogBadgeIds
            var names = cachedNames
            for dto in catalog where wanted.contains(dto.badgeId) { names[dto.badgeId] = dto.name }
            guard names != cachedNames else { return }
            UserDefaults.standard.set(names, forKey: namesKey)
            onChange()
        }
    }
}

// MARK: - "Where to earn it"

/// Carries out a `FlameyEarnRoute` once the Closet has gone: each one lands on
/// the real screen where that medal is earned, through the same doors the rest
/// of the app uses (`DeepLinkRouter`, `MAD_SwitchTab`, `.madStartBuddyWalk`).
/// Raised AFTER the dismissal (the `openAfterDismiss` delay) — a presentation
/// raised in a dismissal's own transaction is the one SwiftUI drops.
@MainActor
enum FlameyEarnRouter {
    static func go(_ route: FlameyEarnRoute) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { perform(route) }
    }

    private static func switchTab(_ tab: Int) {
        NotificationCenter.default.post(name: NSNotification.Name("MAD_SwitchTab"), object: nil, userInfo: ["tab": tab])
    }

    private static func perform(_ route: FlameyEarnRoute) {
        switch route {
        case .startWalk:
            DeepLinkRouter.shared.requestOpenTracker(activity: nil)
        case .startRun:
            DeepLinkRouter.shared.requestOpenTracker(activity: .run)
        case .ghostRace:
            // Ghost Race is the tracker wizard's own step ("Ghost Race" on the
            // race question) — opening the wizard is the one door to it.
            DeepLinkRouter.shared.requestOpenTracker(activity: nil)
        case .buddyWalk:
            switchTab(0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(name: .madStartBuddyWalk, object: nil)
            }
        case .compete:
            switchTab(1)
        case .createCompetition:
            DeepLinkRouter.shared.pendingCompeteAction = .createCompetition
            switchTab(1)
        case .weeklyChallenge:
            DeepLinkRouter.shared.pendingCompeteAction = .weeklyChallenge
            switchTab(1)
        case .dailyChallenge:
            switchTab(0)
        case .postStory, .hypeFriends:
            switchTab(2)
        case .nudgeFriends:
            switchTab(3)
        case .holiday:
            break
        }
    }
}

// MARK: - The screen, live

/// FlameyClosetView fed from the account's facts and saving through
/// `FlameyClosetSync` — opening on the first-run walkthrough the first time.
/// What the hosts present.
struct FlameyClosetScreen: View {
    let request: FlameyClosetLink.Request
    /// False when presented over a friend's sheet: leaving for another tab
    /// from there would land behind that sheet, so locked cards say WHERE
    /// instead of offering a button.
    var canRoute: Bool = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: FlameyClosetModel
    @State private var showingJourney: Bool

    init(request: FlameyClosetLink.Request, canRoute: Bool = true) {
        self.request = request
        self.canRoute = canRoute
        _model = State(initialValue: Self.makeModel(request))
        // A request aimed at ONE item (from a medal, a deep link) goes
        // straight there; the first-run walkthrough waits for a plain open.
        _showingJourney = State(initialValue: request.journey
            || (!FlameyJourneyLedger.seen && !request.openDetail))
    }

    var body: some View {
        ZStack {
            if showingJourney {
                FlameyJourneyView(model: model, onFinish: finishJourney)
                    .transition(.opacity)
            } else {
                FlameyClosetView(model: model, onDone: { dismiss() }, onShowJourney: {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { showingJourney = true }
                })
                .transition(.opacity)
            }
        }
        .onAppear {
            if canRoute {
                model.onEarn = { route in
                    model.detail = nil
                    dismiss()
                    FlameyEarnRouter.go(route)
                }
            }
            FlameyMedalCatalog.refreshNames { model.medals = FlameyMedalCatalog.medals() }
            if request.openDetail, let item = request.focus, !showingJourney {
                // After the cover has finished presenting: a sheet raised in
                // the same transaction as its host's presentation is dropped.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { model.detail = item }
            }
        }
        .onDisappear {
            FlameySeenLedger.markSeen(model.owned)
            FlameyClosetSync.flush()
        }
    }

    private func finishJourney() {
        FlameyJourneyLedger.markSeen()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { showingJourney = false }
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
                                      medals: FlameyMedalCatalog.medals(),
                                      signupDate: FlameyFacts.signupDate, focus: request.focus,
                                      name: FlameyFacts.name, outfits: FlameyClosetSync.outfits)
        // Only a SAVE reaches here — the Closet edits a draft.
        model.onChoiceChange = { FlameyClosetSync.choiceChanged($0) }
        model.onRename = { await FlameyClosetSync.rename($0) }
        model.onOutfitsChange = { [weak model] list in
            let (outcome, served) = await FlameyClosetSync.saveOutfits(list)
            if let served { model?.adoptOutfits(served) }
            return outcome
        }
        model.workoutView = { id in AnyView(FlameyEarnedWorkoutView(workoutId: id)) }
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
    private var medal: FlameyMedalInfo? {
        guard items.count == 1, let id = items[0].badgeId else { return nil }
        return FlameyMedalCatalog.medals()[id]
    }

    var body: some View {
        if DashboardStylePreference.current == .fun, !items.isEmpty {
            FlameyUnlockView(
                items: items,
                owned: FlameyFacts.ownedItems,
                choice: FlameyFacts.choice,
                medalName: medal?.name,
                medal: medal,
                flameyName: FlameyFacts.displayName,
                onWear: { item in
                    var choice = FlameyFacts.choice
                    choice[item.slot] = item
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
/// top-left corner is his; the top-right holds savers + Share). Wears a dot
/// while there is something to see — the walkthrough not yet taken, or items
/// unlocked since the last visit — which is how the Closet is discovered
/// instead of ambushing anyone at launch.
struct HeroClosetButton: View {
    /// Redraws when the Closet closes (the ledgers live in UserDefaults).
    @ObservedObject private var link = FlameyClosetLink.shared

    private var hasNews: Bool {
        !FlameyJourneyLedger.seen
            || !FlameySeenLedger.unseen(in: FlameyFacts.ownedItems.union(FlameyClosetSync.serverOwned)).isEmpty
    }

    var body: some View {
        FlameyClosetPill(hasNews: hasNews, name: FlameyFacts.displayName) {
            MADHaptics.action()
            FlameyClosetLink.shared.open()
        }
    }
}

/// "Flamey's Closet" on your own profile (Fun only).
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
                fresh: FlameySeenLedger.unseen(in: owned).count,
                firstVisit: !FlameyJourneyLedger.seen,
                name: FlameyFacts.displayName
            ) {
                MADHaptics.action()
                FlameyClosetLink.shared.open()
            }
        }
    }
}

// MARK: - The Medals screen's Flamey links

/// The medal grid tile's glyph, only on Fun and only for a medal that dresses
/// him. Hosts overlay it on the medal; a Modern user sees nothing.
struct FlameyMedalItemGlyphLive: View {
    let badgeId: String
    let earned: Bool
    @AppStorage(DashboardStylePreference.key) private var styleRaw = DashboardStyle.modern.rawValue

    var body: some View {
        let items = FlameyMedalLink.items(forBadge: badgeId)
        if styleRaw == DashboardStyle.fun.rawValue, !items.isEmpty {
            FlameyMedalItemGlyph(items: items, earned: earned)
        }
    }
}

/// The medal detail's "Unlocks for Flamey" card (Fun only). It presents the
/// Closet on its OWN cover: the medal screen can be pushed inside a sheet,
/// and a cover raised from MainTabView's root can't present over one. From
/// here "where to earn it" has no tab to leave for, so locked cards say
/// where instead of offering a button (`canRoute: false`).
struct FlameyMedalUnlockCardLive: View {
    let badgeId: String
    let earned: Bool
    @AppStorage(DashboardStylePreference.key) private var styleRaw = DashboardStyle.modern.rawValue
    @State private var closet: FlameyClosetLink.Request?

    var body: some View {
        let items = FlameyMedalLink.items(forBadge: badgeId)
        if styleRaw == DashboardStyle.fun.rawValue, !items.isEmpty {
            FlameyMedalUnlockCard(items: items, earned: earned, name: FlameyFacts.displayName) { item in
                closet = FlameyClosetLink.Request(focus: item, openDetail: true)
            }
            .fullScreenCover(item: $closet) { request in
                FlameyClosetScreen(request: request, canRoute: false)
            }
        }
    }
}

// MARK: - "View workout" from a medal

/// The workout that earned a medal, opened by its id (the server's
/// `earned_detail.workout_id`, else `triggeringWorkoutId` — both are the
/// HKWorkout UUID the sync uploaded). Found in this phone's HealthKit through
/// the app's LONG-LIVED store (a per-call store is released before its query
/// answers); a workout that isn't on this phone (another device, deleted
/// from Health) says so rather than spinning.
struct FlameyEarnedWorkoutView: View {
    let workoutId: String
    @Environment(\.dismiss) private var dismiss
    @State private var workout: HKWorkout?
    @State private var missing = false

    var body: some View {
        Group {
            if let workout {
                WorkoutDetailView(workout: workout)
            } else {
                VStack(spacing: 14) {
                    if missing {
                        Image(systemName: "figure.walk.motion")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                            .accessibilityHidden(true)
                        Text("That workout isn't on this phone")
                            .madFont(size: 18, weight: .heavy, design: .rounded)
                            .foregroundColor(.white)
                        Text("It may have been recorded on another device or removed from Apple Health.")
                            .madFont(size: 14, weight: .semibold, design: .rounded)
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button {
                            dismiss()
                        } label: {
                            Text("Close")
                                .madFont(size: 16, weight: .bold, design: .rounded)
                                .foregroundColor(FlameyClosetStyle.ember)
                                .frame(minWidth: 88, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(FlameyClosetStyle.ground.ignoresSafeArea())
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard workout == nil, !missing else { return }
        let manager = HealthKitManager.shared
        // Already in memory (recent history) — no query needed.
        if let known = (manager.cachedWorkouts + manager.recentWorkouts)
            .first(where: { $0.uuid.uuidString.caseInsensitiveCompare(workoutId) == .orderedSame }) {
            workout = known
            return
        }
        guard let uuid = UUID(uuidString: workoutId), HKHealthStore.isHealthDataAvailable() else {
            missing = true
            return
        }
        let found: HKWorkout? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(),
                                      predicate: HKQuery.predicateForObject(with: uuid),
                                      limit: 1, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout])?.first)
            }
            manager.healthStore.execute(query)
        }
        if let found { workout = found } else { missing = true }
    }
}

/// The medal detail's "HOW YOU EARNED IT" card (every style — it's about the
/// medal, not Flamey): the server's sentence + day + "View workout", else the
/// requirement and the earned date. Presents the workout on its OWN sheet.
struct MedalHowEarnedCard: View {
    let badge: Badge
    /// The medal's requirement in words (BadgeDetailView's unlock text).
    let requirement: String
    @State private var workout: FlameyWorkoutRef?

    var body: some View {
        let detail = BadgeEarnedDetails.entry(for: badge.id)
        let medal = FlameyMedalInfo(
            badgeId: badge.id, name: badge.name, icon: iconName(for: badge), rarity: .common,
            earnedAt: badge.dateAwarded, isEarned: true,
            earnedSummary: detail?.summary,
            earnedDay: FlameyClosetCopy.parseDay(detail?.date),
            earnedWorkoutId: detail?.workoutId)
        FlameyHowEarned(medal: medal, requirement: requirement) { id in
            MADHaptics.tap()
            workout = FlameyWorkoutRef(id: id)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        .sheet(item: $workout) { ref in
            FlameyEarnedWorkoutView(workoutId: ref.id)
        }
    }
}
