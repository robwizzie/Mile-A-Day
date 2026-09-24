import SwiftUI
import Observation

// FLAMEY'S CLOSET — the model and the pure pieces (progress, copy, tabs).
// Deliberately free of app services: `FlameyClosetLive.swift` builds one of
// these from `FlameyFacts` and wires `onChoiceChange` to the server, so the
// screen itself renders from stub data in the macOS ImageRenderer harness.

// MARK: - Tabs

/// The Closet's four tabs and the slots each one holds, in display order.
enum FlameyClosetTab: String, CaseIterable, Identifiable, Hashable {
    case flame, outfit, extras, style

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flame: return "Flame"
        case .outfit: return "Outfit"
        case .extras: return "Extras"
        case .style: return "Style"
        }
    }

    var slots: [FlameySlot] {
        switch self {
        case .flame: return [.color]
        case .outfit: return [.head, .eyes, .chest, .back, .feet, .costume]
        case .extras: return [.held, .trail, .companion, .aura]
        case .style: return [.bubble]
        }
    }

    static func tab(for slot: FlameySlot) -> FlameyClosetTab {
        allCases.first { $0.slots.contains(slot) } ?? .flame
    }
}

extension FlameySlot {
    /// The Closet's chip label (the catalog's `displayName` is for sentences).
    var closetLabel: String {
        switch self {
        case .color: return "Colour"
        case .bubble: return "Bubble"
        default: return displayName
        }
    }

    /// Whether "None" means anything here. A bare colour IS Classic and a bare
    /// bubble IS the classic bubble, so those two slots offer Auto + items only.
    var offersNone: Bool { self != .color && self != .bubble }
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
            let short = gap < 60 ? "\(gap)s to go" : "\(gap / 60)m \(gap % 60)s to go"
            let spokenMinutes = gap / 60
            let spokenSeconds = gap % 60
            var spoken = ""
            if spokenMinutes > 0 { spoken += "\(spokenMinutes) minute\(spokenMinutes == 1 ? "" : "s") " }
            if spokenSeconds > 0 || spokenMinutes == 0 { spoken += "\(spokenSeconds) second\(spokenSeconds == 1 ? "" : "s") " }
            return .init(fraction: min(1, Double(target) / best), short: short,
                         spoken: spoken + "to go")
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
        return "Worn automatically on \(list)"
    }

    /// The tag a holiday tile carries ("Halloween").
    static func holidayTag(_ item: FlameyItem) -> String? {
        item.holidays.first?.holidayName
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

    static func tryOnLine(_ item: FlameyItem, seed: Int) -> String {
        let lines = ["Ooh, I want these!", "Earn it for me?", "Just looking…", "Can we keep it?"]
        return lines[abs(seed) % lines.count]
    }

    static let autoLines = ["My best stuff!", "The good stuff", "Dress me well!"]
    static let bareLines = ["Keeping it simple", "Less is more", "Au naturel"]
    static let surpriseLines = ["Surprise!", "Bold choice!", "Fashion!", "Mix and match!"]
}

// MARK: - The model

/// Everything the Closet shows and does. A plain value store: the screen
/// mutates it, and `onChoiceChange` is how a change leaves (the live glue
/// debounces it to `PUT /users/:id/flamey-look`).
@MainActor @Observable
final class FlameyClosetModel {
    private(set) var owned: Set<FlameyItem>
    private(set) var choice: FlameyLookChoice
    /// A LOCKED item on the stage, never saved.
    private(set) var tryingOn: FlameyItem?
    var tab: FlameyClosetTab
    var slotForTab: [FlameyClosetTab: FlameySlot]
    /// Items unlocked since the last visit (the "New" dots).
    private(set) var newItems: Set<FlameyItem>
    /// The item the caption strip talks about (last tapped).
    private(set) var focus: FlameyItem?
    /// His line and when he said it (the stage hop keys off the date).
    private(set) var line: String?
    private(set) var lineAt: Date?

    let facts: FlameyProgressFacts
    /// The day the stage resolves for (a holiday outfit comes on by itself).
    let date: Date
    let signupDate: Date?
    @ObservationIgnored var onChoiceChange: (FlameyLookChoice) -> Void = { _ in }
    @ObservationIgnored private var lineSeed = 0

    init(owned: Set<FlameyItem>, choice: FlameyLookChoice, newItems: Set<FlameyItem> = [],
         facts: FlameyProgressFacts = .init(), date: Date = Date(), signupDate: Date? = nil,
         focus: FlameyItem? = nil) {
        self.owned = owned.union(FlameyItem.allCases.filter { $0.unlock == .always })
        self.choice = choice
        self.newItems = newItems
        self.facts = facts
        self.date = date
        self.signupDate = signupDate
        var slots: [FlameyClosetTab: FlameySlot] = [:]
        for tab in FlameyClosetTab.allCases { slots[tab] = tab.slots[0] }
        // Open where the news is: the first new item's tab and slot.
        let lead = focus ?? newItems.sorted { ($0.slot.sortIndex, $0.tier) < ($1.slot.sortIndex, $1.tier) }.first
        if let lead {
            let tab = FlameyClosetTab.tab(for: lead.slot)
            slots[tab] = lead.slot
            self.tab = tab
        } else {
            self.tab = .flame
        }
        self.slotForTab = slots
        self.focus = lead
    }

    var slot: FlameySlot { slotForTab[tab] ?? tab.slots[0] }

    // MARK: Reading

    func owns(_ item: FlameyItem) -> Bool { owned.contains(item) }

    /// What's on the stage: the saved choice, plus the try-on.
    var stageLook: FlameyLook {
        var choice = self.choice
        var owned = self.owned
        if let tryingOn {
            owned.insert(tryingOn)
            choice[tryingOn.slot] = .item(tryingOn)
        }
        return FlameyLook.resolve(owned: owned, choice: choice, date: date, signupDate: signupDate, detail: .full)
    }

    /// The saved look, resolved (what the rest of the app draws).
    var savedLook: FlameyLook {
        FlameyLook.resolve(owned: owned, choice: choice, date: date, signupDate: signupDate, detail: .full)
    }

    func items(in slot: FlameySlot) -> [FlameyItem] { FlameyWardrobe.items(in: slot) }

    /// AUTO's pick for a slot.
    func autoItem(in slot: FlameySlot) -> FlameyItem? { FlameyWardrobe.best(in: slot, owned: owned) }

    func ownedCount(in slot: FlameySlot) -> Int { items(in: slot).filter(owns).count }

    func counts(for tab: FlameyClosetTab) -> (owned: Int, total: Int) {
        let all = tab.slots.flatMap { items(in: $0) }
        return (all.filter(owns).count, all.count)
    }

    func hasNew(in slot: FlameySlot) -> Bool { items(in: slot).contains { newItems.contains($0) } }
    func hasNew(in tab: FlameyClosetTab) -> Bool { tab.slots.contains { hasNew(in: $0) } }

    /// Is this tile the one the slot is set to?
    func isChosen(_ choice: FlameySlotChoice, in slot: FlameySlot) -> Bool {
        switch (self.choice[slot], choice) {
        case (.auto, .auto), (.bare, .bare): return true
        case (.item(let a), .item(let b)): return a == b && owned.contains(a)
        // An item you no longer own reads as AUTO (the resolver's rule).
        case (.item(let a), .auto): return !owned.contains(a)
        default: return false
        }
    }

    /// Is he wearing this right now (by choice or by AUTO)?
    func isWorn(_ item: FlameyItem) -> Bool { savedLook.wears(item) }

    func progress(for item: FlameyItem) -> FlameyUnlockProgress? {
        owns(item) ? nil : FlameyUnlockProgress.progress(for: item, facts: facts)
    }

    // MARK: Doing

    func select(_ slotChoice: FlameySlotChoice, in slot: FlameySlot) {
        tryingOn = nil
        switch slotChoice {
        case .item(let item):
            guard owns(item) else { return tryOn(item) }
            focus = item
            say(FlameyClosetCopy.wearLine(item, seed: nextSeed()))
        case .auto:
            focus = autoItem(in: slot)
            say(FlameyClosetCopy.autoLines[nextSeed() % FlameyClosetCopy.autoLines.count])
        case .bare:
            focus = nil
            say(FlameyClosetCopy.bareLines[nextSeed() % FlameyClosetCopy.bareLines.count])
        }
        guard choice[slot] != slotChoice else { return }
        choice[slot] = slotChoice
        onChoiceChange(choice)
    }

    func tryOn(_ item: FlameyItem) {
        guard !owns(item) else { return select(.item(item), in: item.slot) }
        tryingOn = item
        focus = item
        say(FlameyClosetCopy.tryOnLine(item, seed: nextSeed()))
    }

    func takeOff() {
        tryingOn = nil
        focus = nil
    }

    /// "Best look": every slot back on AUTO.
    func bestLook() {
        tryingOn = nil
        focus = nil
        say(FlameyClosetCopy.autoLines[nextSeed() % FlameyClosetCopy.autoLines.count])
        guard !choice.isAllAuto else { return }
        choice = .auto
        onChoiceChange(choice)
    }

    /// "Surprise me": a random OWNED item per slot. A costume covers
    /// everything else, so it only turns up now and then.
    func surprise<G: RandomNumberGenerator>(using rng: inout G) {
        tryingOn = nil
        var next = FlameyLookChoice.auto
        for slot in FlameySlot.allCases {
            let pool = items(in: slot).filter(owns)
            switch slot {
            case .costume:
                if let item = pool.randomElement(using: &rng), Double.random(in: 0..<1, using: &rng) < 0.2 {
                    next[slot] = .item(item)
                } else {
                    next[slot] = .bare
                }
            case .color, .bubble:
                if let item = pool.randomElement(using: &rng) { next[slot] = .item(item) }
            default:
                // Bare is in the draw, so a surprise isn't always maximal.
                let options: [FlameySlotChoice] = pool.map { .item($0) } + [.bare]
                next[slot] = options.randomElement(using: &rng) ?? .bare
            }
        }
        focus = nil
        say(FlameyClosetCopy.surpriseLines[nextSeed() % FlameyClosetCopy.surpriseLines.count])
        choice = next
        onChoiceChange(choice)
    }

    func surprise() {
        var rng = SystemRandomNumberGenerator()
        surprise(using: &rng)
    }

    /// The server's copy replaced ours (a 400 re-sync, another device).
    func adopt(choice: FlameyLookChoice, owned: Set<FlameyItem>? = nil) {
        if let owned { self.owned = owned.union(FlameyItem.allCases.filter { $0.unlock == .always }) }
        self.choice = choice
    }

    func clearLine() { line = nil }

    private func say(_ text: String) {
        line = text
        lineAt = Date()
    }

    private func nextSeed() -> Int {
        lineSeed += 1
        return lineSeed + Int(Date().timeIntervalSince1970) % 7
    }
}

extension FlameySlot {
    var sortIndex: Int { FlameySlot.allCases.firstIndex(of: self) ?? 0 }
}
