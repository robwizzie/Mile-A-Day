import SwiftUI
import Observation

// FLAMEY'S CLOSET — the model and the pure pieces (progress, medals, where to
// earn, copy, tabs). Deliberately free of app services: `FlameyClosetLive.swift`
// builds one of these from `FlameyFacts` and wires its callbacks to the server
// and the app's routes, so every screen renders from stub data in the macOS
// ImageRenderer harness.
//
// THE RULE the whole Closet is built around: owning something never puts it
// on him. Until the user picks something he is BASIC — exactly the Flamey
// that existed before the wardrobe — and every change is one they made
// (a tap, "Best look", "Surprise me", a "Wear it"), each with an undo.

// MARK: - Tabs

/// The Closet's four tabs and the slots each one holds, in display order.
/// A tab is ONE scroll of stacked sections (one per slot), never a sub-chip
/// that hides the rest — so everything the tab offers is a scroll away.
enum FlameyClosetTab: String, CaseIterable, Identifiable, Hashable {
    case flame, outfit, extras, style

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flame: return "Colour"
        case .outfit: return "Outfit"
        case .extras: return "Extras"
        case .style: return "Bubble"
        }
    }

    var slots: [FlameySlot] {
        switch self {
        case .flame: return [.color]
        case .outfit: return [.head, .eyes, .chest, .feet, .back, .costume]
        case .extras: return [.companion, .trail, .held, .aura]
        case .style: return [.bubble]
        }
    }

    static func tab(for slot: FlameySlot) -> FlameyClosetTab {
        allCases.first { $0.slots.contains(slot) } ?? .flame
    }
}

extension FlameySlot {
    /// The Closet's section title (the catalog's `displayName` is for sentences).
    var closetLabel: String {
        switch self {
        case .color: return "Flame colours"
        case .head: return "Hats"
        case .eyes: return "Eyewear"
        case .chest: return "Chest"
        case .back: return "Capes & wings"
        case .feet: return "Shoes"
        case .costume: return "Costumes"
        case .held: return "In his hand"
        case .trail: return "Trails"
        case .companion: return "Companions"
        case .aura: return "Auras"
        case .bubble: return "Speech bubbles"
        }
    }

    /// One word for the jump row and tight captions.
    var shortLabel: String {
        switch self {
        case .color: return "Colour"
        case .head: return "Hats"
        case .eyes: return "Eyes"
        case .chest: return "Chest"
        case .back: return "Capes"
        case .feet: return "Shoes"
        case .costume: return "Costumes"
        case .held: return "Held"
        case .trail: return "Trails"
        case .companion: return "Buddies"
        case .aura: return "Auras"
        case .bubble: return "Bubbles"
        }
    }

    /// What an EMPTY slot looks like on him: Classic for the colour, the
    /// classic bubble for the bubble, nothing anywhere else.
    var basicItem: FlameyItem? {
        switch self {
        case .color: return .classic
        case .bubble: return .classicBubble
        default: return nil
        }
    }

    var sortIndex: Int { FlameySlot.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: - Medals

/// A medal's rarity, as the app's badge catalog grades it.
enum FlameyMedalRarity: String, Hashable {
    case common, rare, legendary

    var label: String {
        switch self {
        case .common: return "Common"
        case .rare: return "Rare"
        case .legendary: return "Legendary"
        }
    }

    /// The medal face — the same pair `medalGradientColors` gives the badge
    /// grid, so a medal looks the same here as on the Badges screen.
    var colors: [Color] {
        switch self {
        case .legendary: return [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 0.85, green: 0.45, blue: 0.0)]
        case .rare: return [Color(red: 0.7, green: 0.4, blue: 1.0), Color(red: 0.5, green: 0.15, blue: 0.85)]
        case .common: return [Color(red: 0.4, green: 0.7, blue: 1.0), Color(red: 0.15, green: 0.45, blue: 0.85)]
        }
    }

    var ink: Color { colors[0] }
}

/// The medal behind an item, as the app knows it: its name, icon and rarity
/// from the badge catalog, and — when the user holds it — the day they
/// earned it. The live glue builds these from the badge list; the harness
/// passes stubs.
struct FlameyMedalInfo: Equatable, Hashable {
    let badgeId: String
    /// nil until the catalog has told us (the item's unlock line stands in).
    var name: String?
    /// SF Symbol.
    var icon: String
    var rarity: FlameyMedalRarity
    /// When they earned it; nil = not earned (or earned but undated).
    var earnedAt: Date?
    var isEarned: Bool

    /// A fallback for an id the catalog hasn't described yet.
    static func placeholder(badgeId: String) -> FlameyMedalInfo {
        let holiday = HolidayKey(badgeId: badgeId)
        return FlameyMedalInfo(badgeId: badgeId, name: holiday?.medalName, icon: holiday?.medalIcon ?? "star.fill",
                               rarity: holiday != nil ? .rare : .common, earnedAt: nil, isEarned: false)
    }
}

// MARK: - Where to earn it

/// The one place in the app where the medal behind a locked item is earned.
/// Pure: `FlameyClosetLive` turns a route into a tab switch / parked request
/// AFTER the Closet has dismissed (a presentation raised in a dismissal's own
/// transaction is the one SwiftUI drops).
enum FlameyEarnRoute: Hashable {
    case startWalk
    case startRun
    case ghostRace
    case buddyWalk
    case compete
    case createCompetition
    case dailyChallenge
    case weeklyChallenge
    case postStory
    case hypeFriends
    case nudgeFriends
    /// No button: the day comes round on its own.
    case holiday(HolidayKey)

    static func route(for item: FlameyItem) -> FlameyEarnRoute? {
        guard let id = item.badgeId else { return nil }
        if let holiday = HolidayKey(badgeId: id) { return .holiday(holiday) }
        if id.hasPrefix("ghost_") { return .ghostRace }
        if id.hasPrefix("buddy_") { return .buddyWalk }
        if id.hasPrefix("comp_started_") { return .createCompetition }
        if id.hasPrefix("comp_") { return .compete }
        if id.hasPrefix("challenge_") { return .dailyChallenge }
        if id.hasPrefix("weekly_") { return .weeklyChallenge }
        if id.hasPrefix("story_") { return .postStory }
        if id.hasPrefix("hype_") { return .hypeFriends }
        if id.hasPrefix("nudge_") { return .nudgeFriends }
        if id.hasPrefix("pace_") { return .startRun }
        return .startWalk
    }

    /// The button's words; nil = no button (a holiday).
    var buttonTitle: String? {
        switch self {
        case .startWalk: return "Start a walk"
        case .startRun: return "Start a run"
        case .ghostRace: return "Race a ghost"
        case .buddyWalk: return "Start a buddy walk"
        case .compete: return "Go to Compete"
        case .createCompetition: return "Start a competition"
        case .dailyChallenge: return "See today's challenge"
        case .weeklyChallenge: return "Open the weekly challenge"
        case .postStory: return "Post a story"
        case .hypeFriends: return "Hype a friend"
        case .nudgeFriends: return "Nudge a friend"
        case .holiday: return nil
        }
    }

    var icon: String {
        switch self {
        case .startWalk: return "figure.walk"
        case .startRun: return "figure.run"
        case .ghostRace: return "stopwatch"
        case .buddyWalk: return "person.2.fill"
        case .compete, .createCompetition: return "trophy.fill"
        case .dailyChallenge: return "star.circle.fill"
        case .weeklyChallenge: return "calendar"
        case .postStory: return "camera.fill"
        case .hypeFriends: return "hands.clap.fill"
        case .nudgeFriends: return "hand.wave.fill"
        case .holiday: return "calendar"
        }
    }

    /// Where that is, in words — so the button is never a mystery.
    var whereLine: String {
        switch self {
        case .startWalk: return "Every walk counts. Start one from the Dashboard."
        case .startRun: return "Your fastest mile counts — start a run from the Dashboard."
        case .ghostRace: return "Start a walk or run and pick Ghost Race to chase your best mile."
        case .buddyWalk: return "Walk with friends from With a Buddy on the Dashboard."
        case .compete: return "Join or win competitions on the Compete tab."
        case .createCompetition: return "Create a competition on the Compete tab and invite friends."
        case .dailyChallenge: return "Today's challenge is on your Dashboard."
        case .weeklyChallenge: return "This week's challenge is on the Compete tab."
        case .postStory: return "Post a story from the Feed after a walk."
        case .hypeFriends: return "Hype friends' walks and posts in the Feed."
        case .nudgeFriends: return "Nudge a friend who hasn't walked yet from Friends."
        case .holiday(let key): return "Walk your mile on \(key.holidayName) and it's yours."
        }
    }
}

// MARK: - Progress toward a locked item

/// The numbers the app already knows about the user — the same ones
/// `BadgeDetailView`'s locked-progress card reads. Any of them may be unknown;
/// an item whose number is unknown simply shows no progress.
struct FlameyProgressFacts: Equatable {
    var currentStreak: Int = 0
    var totalMiles: Double = 0
    /// Fastest mile, in MINUTES per mile (0 = none recorded).
    var fastestPaceMinutes: Double = 0
    var mostMilesInADay: Double = 0
    /// Daily challenges completed, when the history has loaded.
    var challengesCompleted: Int? = nil
    /// Formats a distance given in MILES in the user's unit ("12.4 mi").
    var formatDistance: (Double) -> String = { String(format: "%.1f mi", $0) }

    static func == (a: Self, b: Self) -> Bool {
        a.currentStreak == b.currentStreak && a.totalMiles == b.totalMiles
            && a.fastestPaceMinutes == b.fastestPaceMinutes && a.mostMilesInADay == b.mostMilesInADay
            && a.challengesCompleted == b.challengesCompleted
    }
}

/// How close the user is to a locked item: a 0–1 fill, the short line the
/// tile prints ("24s to go") and the words VoiceOver says ("24 seconds to go").
struct FlameyUnlockProgress: Equatable {
    let fraction: Double
    let short: String
    let spoken: String

    /// Distance-in-one-day medal targets, in miles (mirrors BadgeDetailView).
    static func dailyTargetMiles(_ id: String) -> Double? {
        switch id {
        case "daily_2": return 2
        case "daily_3": return 3.1
        case "daily_5": return 5
        case "daily_8": return 8
        case "daily_10": return 10
        case "daily_10k": return 6.2
        case "daily_half": return 13.1
        case "daily_15": return 15
        case "daily_20": return 20
        case "daily_marathon": return 26.2
        case "daily_50k": return 31
        case "daily_ultra": return 50
        default: return nil
        }
    }

    /// nil when the app doesn't know (a ghost race, a hype count, a holiday).
    static func progress(for item: FlameyItem, facts: FlameyProgressFacts) -> FlameyUnlockProgress? {
        guard let id = item.badgeId else { return nil }
        func number(after prefix: String) -> Int? { Int(id.dropFirst(prefix.count)) }

        if id.hasPrefix("streak_") || id.hasPrefix("consistency_"),
           let target = number(after: id.hasPrefix("streak_") ? "streak_" : "consistency_"), target > 0 {
            let need = max(1, target - facts.currentStreak)
            let days = need == 1 ? "day" : "days"
            return .init(fraction: min(1, Double(facts.currentStreak) / Double(target)),
                         short: "\(need) more \(days)", spoken: "\(need) more \(days)")
        }
        if id.hasPrefix("miles_"), let target = number(after: "miles_"), target > 0 {
            let need = max(0.1, Double(target) - facts.totalMiles)
            let text = facts.formatDistance(need)
            return .init(fraction: min(1, facts.totalMiles / Double(target)),
                         short: "\(text) to go", spoken: "\(text) to go")
        }
        if id.hasPrefix("pace_"), let target = Int(id.dropFirst("pace_".count).dropLast("min".count)) {
            let best = facts.fastestPaceMinutes
            guard best > 0 else { return nil }
            let gap = max(1, Int(((best - Double(target)) * 60).rounded(.up)))
            let short = gap < 60 ? "\(gap)s faster" : "\(gap / 60)m \(gap % 60)s faster"
            let spokenMinutes = gap / 60
            let spokenSeconds = gap % 60
            var spoken = ""
            if spokenMinutes > 0 { spoken += "\(spokenMinutes) minute\(spokenMinutes == 1 ? "" : "s") " }
            if spokenSeconds > 0 || spokenMinutes == 0 { spoken += "\(spokenSeconds) second\(spokenSeconds == 1 ? "" : "s") " }
            return .init(fraction: min(1, Double(target) / best), short: short,
                         spoken: spoken + "faster to go")
        }
        if let target = dailyTargetMiles(id) {
            let need = max(0.1, target - facts.mostMilesInADay)
            let text = facts.formatDistance(need)
            return .init(fraction: min(1, facts.mostMilesInADay / target),
                         short: "\(text) more in a day", spoken: "\(text) more in one day")
        }
        if id.hasPrefix("challenge_"), let target = number(after: "challenge_"), target > 0,
           let done = facts.challengesCompleted {
            let need = max(1, target - done)
            let noun = need == 1 ? "challenge" : "challenges"
            return .init(fraction: min(1, Double(done) / Double(target)),
                         short: "\(need) more \(noun)", spoken: "\(need) more \(noun)")
        }
        return nil
    }
}

// MARK: - Copy

enum FlameyClosetCopy {
    /// "Worn automatically on Halloween" — or nil for an everyday item.
    static func holidayLine(_ item: FlameyItem) -> String? {
        guard let first = item.holidays.first else { return nil }
        let names = item.holidays.map(\.holidayName)
        let list = names.count == 2 ? "\(names[0]) and \(names[1])" : first.holidayName
        return "He wears it on \(list) either way"
    }

    /// What he says when he puts something on.
    static func wearLine(_ item: FlameyItem, seed: Int) -> String {
        let name = item.displayName
        let lines: [String]
        switch item.slot {
        case .color: lines = ["Feeling \(name.lowercased())!", "\(name) suits me", "New flame, who dis?"]
        case .head: lines = ["How's the \(name.lowercased())?", "Hat hair, don't care", "Topped off!"]
        case .eyes: lines = ["Looking sharp", "Can't see the haters", "Eyes on the mile"]
        case .chest: lines = ["Dressed to walk", "Fancy!", "Very distinguished"]
        case .back: lines = ["Swoosh!", "Heroic, right?", "Off we go!"]
        case .feet: lines = ["Fresh kicks!", "Built for speed", "Let's move!"]
        case .costume: lines = ["Guess who!", "Totally in disguise", "Ta-da!"]
        case .held: lines = ["Got it!", "Hold my flame", "Ready to cheer!"]
        case .trail: lines = ["Whoosh!", "Leave 'em in the dust", "Catch me!"]
        case .companion: lines = ["Say hi to my friend!", "We walk together", "Best buddies"]
        case .aura: lines = ["Glowing up", "Main character energy", "Shine on"]
        case .bubble: lines = ["How do I sound?", "New voice, same me", "Better, right?"]
        }
        return lines[abs(seed) % lines.count]
    }

    static let bestLines = ["My best stuff!", "The good stuff", "Dressed to impress"]
    static let basicLines = ["Just me again", "Back to basics", "Classic me"]
    static let takeOffLines = ["Less is more", "Keeping it simple", "Off it comes"]
    static let surpriseLines = ["Surprise!", "Bold choice!", "Fashion!", "Mix and match!"]

    /// "Sep 12, 2026".
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// "Sat, Oct 31".
    static func shortDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    static func lowercasedFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.lowercased() + s.dropFirst()
    }
}

// MARK: - Undo toast

struct FlameyClosetToast: Equatable, Identifiable {
    let id = UUID()
    let text: String
    /// The choice to go back to; nil = nothing to undo.
    let undo: FlameyLookChoice?
}

// MARK: - The model

/// Everything the Closet shows and does. A plain value store: the screen
/// mutates it, and `onChoiceChange` is how a change leaves (the live glue
/// debounces it to `PUT /users/:id/flamey-look`).
@MainActor @Observable
final class FlameyClosetModel {
    private(set) var owned: Set<FlameyItem>
    private(set) var choice: FlameyLookChoice
    var tab: FlameyClosetTab
    /// Items unlocked since the last visit (the "New" dots).
    private(set) var newItems: Set<FlameyItem>
    /// The item the caption under the stage talks about (last tapped).
    private(set) var focus: FlameyItem?
    /// The item whose detail card is open.
    var detail: FlameyItem?
    /// The undo toast.
    private(set) var toast: FlameyClosetToast?
    /// His line and when he said it (the stage hop keys off the date).
    private(set) var line: String?
    private(set) var lineAt: Date?
    /// Medal facts per badge id (name, icon, rarity, earned date).
    var medals: [String: FlameyMedalInfo]

    let facts: FlameyProgressFacts
    /// The day the stage resolves for (a holiday outfit comes on by itself).
    let date: Date
    let signupDate: Date?
    @ObservationIgnored var onChoiceChange: (FlameyLookChoice) -> Void = { _ in }
    /// "Where to earn it": the host dismisses the Closet and goes there.
    /// nil where the Closet cannot leave for another tab (it is presented
    /// over a friend's sheet) — the card then says where, without a button.
    @ObservationIgnored var onEarn: ((FlameyEarnRoute) -> Void)? = nil
    @ObservationIgnored private var lineSeed = 0

    init(owned: Set<FlameyItem>, choice: FlameyLookChoice, newItems: Set<FlameyItem> = [],
         facts: FlameyProgressFacts = .init(), medals: [String: FlameyMedalInfo] = [:],
         date: Date = Date(), signupDate: Date? = nil, focus: FlameyItem? = nil) {
        self.owned = owned.union(FlameyItem.allCases.filter { $0.unlock == .always })
        self.choice = choice
        self.newItems = newItems
        self.facts = facts
        self.medals = medals
        self.date = date
        self.signupDate = signupDate
        // Open where the news is: the first new item's tab.
        let lead = focus ?? newItems.sorted { ($0.slot.sortIndex, $0.tier) < ($1.slot.sortIndex, $1.tier) }.first
        self.tab = lead.map { FlameyClosetTab.tab(for: $0.slot) } ?? .flame
        self.focus = lead
    }

    // MARK: Reading

    func owns(_ item: FlameyItem) -> Bool { owned.contains(item) }

    /// What the rest of the app draws — the saved choice, resolved for today.
    var stageLook: FlameyLook {
        FlameyLook.resolve(owned: owned, choice: choice, date: date, signupDate: signupDate, detail: .full)
    }

    /// Everything he'd look like with `item` put on over the current choice
    /// (owned or not — the detail card's preview; nothing is saved).
    func preview(with item: FlameyItem?) -> FlameyLook {
        var choice = self.choice
        var owned = self.owned
        if let item {
            owned.insert(item)
            choice[item.slot] = item
            // A costume covers what's under it — preview it on its own.
            if item.slot == .costume {
                for slot in FlameySlot.allCases where item.hides.contains(slot) { choice[slot] = nil }
            }
        }
        return FlameyLook.resolve(owned: owned, choice: choice, date: date, signupDate: signupDate, detail: .full)
    }

    var isBasic: Bool { choice.isBasic }

    /// A slot's items: what you own first (so picking is one glance), then
    /// the locked ones, each in ladder order.
    func items(in slot: FlameySlot) -> [FlameyItem] {
        let all = FlameyWardrobe.items(in: slot)
        return all.filter(owns) + all.filter { !owns($0) }
    }

    func ownedCount(in slot: FlameySlot) -> Int { FlameyWardrobe.items(in: slot).filter(owns).count }
    func totalCount(in slot: FlameySlot) -> Int { FlameyWardrobe.items(in: slot).count }

    func counts(for tab: FlameyClosetTab) -> (owned: Int, total: Int) {
        let all = tab.slots.flatMap { FlameyWardrobe.items(in: $0) }
        return (all.filter(owns).count, all.count)
    }

    /// Everything unlockable, owned vs total (starter items excluded — they
    /// were never "unlocked").
    var tally: (owned: Int, total: Int) {
        let all = FlameyItem.closet.filter { $0.unlock != .always }
        return (all.filter(owns).count, all.count)
    }

    func hasNew(in slot: FlameySlot) -> Bool { FlameyWardrobe.items(in: slot).contains { newItems.contains($0) } }
    func hasNew(in tab: FlameyClosetTab) -> Bool { tab.slots.contains { hasNew(in: $0) } }

    /// Picked in the Closet (the Classic colour / bubble count as picked
    /// when nothing else is — that IS what he's wearing).
    func isWorn(_ item: FlameyItem) -> Bool {
        if let picked = choice[item.slot] { return picked == item && owns(item) }
        return item.slot.basicItem == item
    }

    /// The item he actually wears in a slot, by choice.
    func worn(in slot: FlameySlot) -> FlameyItem? {
        guard let item = choice[slot], owns(item) else { return nil }
        return item
    }

    func progress(for item: FlameyItem) -> FlameyUnlockProgress? {
        owns(item) ? nil : FlameyUnlockProgress.progress(for: item, facts: facts)
    }

    func medal(for item: FlameyItem) -> FlameyMedalInfo? {
        guard let id = item.badgeId else { return nil }
        var info = medals[id] ?? .placeholder(badgeId: id)
        if owns(item) { info.isEarned = true }
        return info
    }

    /// The next time a holiday item's day comes round (today counts).
    func nextHoliday(for item: FlameyItem) -> (HolidayKey, Date)? {
        guard !item.holidays.isEmpty else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: date)
        for offset in 0..<400 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let key = HolidayCalendar.holiday(on: day), item.holidays.contains(key) else { continue }
            return (key, day)
        }
        return nil
    }

    // MARK: Doing

    /// A tile tap: an owned item goes on (or comes off, if he's wearing it);
    /// a locked one opens its card — there's nothing to wear yet, and the
    /// card is where "how do I get this" is answered.
    func tap(_ item: FlameyItem) {
        guard owns(item) else {
            focus = item
            detail = item
            return
        }
        if isWorn(item), item.slot.basicItem != item {
            takeOff(item.slot)
        } else {
            wear(item)
        }
    }

    func wear(_ item: FlameyItem) {
        guard owns(item) else { return }
        focus = item
        say(FlameyClosetCopy.wearLine(item, seed: nextSeed()))
        var next = choice
        // Picking the Classic colour / bubble is the same as leaving it basic.
        next[item.slot] = item.slot.basicItem == item ? nil : item
        commit(next, toast: "Wearing \(item.displayName)")
    }

    func takeOff(_ slot: FlameySlot) {
        guard let item = choice[slot] else { return }
        focus = item
        say(FlameyClosetCopy.takeOffLines[nextSeed() % FlameyClosetCopy.takeOffLines.count])
        var next = choice
        next[slot] = nil
        commit(next, toast: "Took off \(item.displayName)")
    }

    /// "Best look": the best thing owned in every everyday slot. Explicit —
    /// written into the choice like any pick, and undoable.
    func bestLook() {
        var next = FlameyLookChoice.basic
        for slot in FlameySlot.allCases {
            if let best = FlameyWardrobe.best(in: slot, owned: owned), best.slot.basicItem != best {
                next[slot] = best
            }
        }
        focus = nil
        say(FlameyClosetCopy.bestLines[nextSeed() % FlameyClosetCopy.bestLines.count])
        commit(next, toast: next.isBasic ? "Nothing to wear yet" : "Best look on")
    }

    /// "Surprise me": a random OWNED item per slot. A costume covers
    /// everything else, so it only turns up now and then.
    func surprise<G: RandomNumberGenerator>(using rng: inout G) {
        var next = FlameyLookChoice.basic
        for slot in FlameySlot.allCases {
            let pool = FlameyWardrobe.items(in: slot).filter(owns).filter { $0.slot.basicItem != $0 }
            switch slot {
            case .costume:
                if let item = pool.randomElement(using: &rng), Double.random(in: 0..<1, using: &rng) < 0.2 {
                    next[slot] = item
                }
            case .color, .bubble:
                next[slot] = pool.randomElement(using: &rng)
            default:
                // Nothing is in the draw, so a surprise isn't always maximal.
                if Double.random(in: 0..<1, using: &rng) < 0.7 { next[slot] = pool.randomElement(using: &rng) }
            }
        }
        focus = nil
        say(FlameyClosetCopy.surpriseLines[nextSeed() % FlameyClosetCopy.surpriseLines.count])
        commit(next, toast: "Surprise look on")
    }

    func surprise() {
        var rng = SystemRandomNumberGenerator()
        surprise(using: &rng)
    }

    /// "Reset to basic": the Flamey from before the wardrobe.
    func resetToBasic() {
        guard !choice.isBasic else { return }
        focus = nil
        say(FlameyClosetCopy.basicLines[nextSeed() % FlameyClosetCopy.basicLines.count])
        commit(.basic, toast: "Back to basic Flamey")
    }

    func undo() {
        guard let previous = toast?.undo else { return }
        toast = nil
        focus = nil
        choice = previous
        onChoiceChange(choice)
    }

    func clearToast(_ id: UUID) {
        if toast?.id == id { toast = nil }
    }

    /// The server's copy replaced ours (a 400 re-sync, another device).
    func adopt(choice: FlameyLookChoice, owned: Set<FlameyItem>? = nil) {
        if let owned { self.owned = owned.union(FlameyItem.allCases.filter { $0.unlock == .always }) }
        self.choice = choice
    }

    func earn(_ item: FlameyItem) {
        guard let route = FlameyEarnRoute.route(for: item), route.buttonTitle != nil else { return }
        onEarn?(route)
    }

    func clearLine() { line = nil }

    /// "Seen": the New dots go once the Closet closes.
    func markAllSeen() { newItems = [] }

    private func commit(_ next: FlameyLookChoice, toast text: String) {
        let previous = choice
        guard next != previous else {
            toast = FlameyClosetToast(text: text, undo: nil)
            return
        }
        choice = next
        toast = FlameyClosetToast(text: text, undo: previous)
        onChoiceChange(choice)
    }

    private func say(_ text: String) {
        line = text
        lineAt = Date()
    }

    private func nextSeed() -> Int {
        lineSeed += 1
        return lineSeed + Int(Date().timeIntervalSince1970) % 7
    }
}
