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
// (a tap, "Best look", "Surprise me", an outfit), and none of it leaves
// the Closet until they tap Save — trying things on is free.

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

    /// The one sentence that says which medals fill this slot — every slot is
    /// (almost) one medal ladder, so the rule is learnable once, in the
    /// section header, instead of item by item.
    var familyRule: String {
        switch self {
        case .color: return "Colours come from streak medals — the longer the streak, the rarer the flame."
        case .head: return "Hats come from lifetime-mile medals — walk further, better hats."
        case .eyes: return "Eyewear comes from daily-challenge medals."
        case .chest: return "Chest pieces come from weekly-challenge medals."
        case .back: return "Capes come from entering competitions; wings and banners from winning them."
        case .feet: return "Shoes come from pace medals — run faster, cooler kicks."
        case .costume: return "Costumes are rare: beat ghosts, walk huge miles — or it's Halloween."
        case .held: return "Held items come from hyping friends and starting competitions."
        case .trail: return "Trails come from big days — more miles in one day, flashier trails."
        case .companion: return "Buddies come from buddy walks — walk together, gain a sidekick."
        case .aura: return "Auras come from beating ghosts by a margin and posting stories."
        case .bubble: return "Speech bubbles come from nudging friends."
        }
    }

    /// "Pick his shoes" — a walkthrough section's instruction.
    var pickLabel: String {
        switch self {
        case .color: return "Colour"
        case .head: return "Hat"
        case .eyes: return "Eyewear"
        case .chest: return "Chest"
        case .back: return "Cape or wings"
        case .feet: return "Shoes"
        case .costume: return "Costume"
        case .held: return "In his hand"
        case .trail: return "Trail"
        case .companion: return "Buddy"
        case .aura: return "Aura"
        case .bubble: return "Speech bubble"
        }
    }
}

extension FlameyLookChoice {
    /// The choice with `item` picked (nil = that slot cleared). Picking a
    /// costume leaves the rest alone (it covers them); picking something a
    /// costume would cover takes the costume off, so the pick is visible.
    /// The Classic colour / bubble are stored as "nothing picked".
    func picking(_ item: FlameyItem?, in slot: FlameySlot) -> FlameyLookChoice {
        var next = self
        guard let item else {
            next[slot] = nil
            return next
        }
        next[slot] = slot.basicItem == item ? nil : item
        if slot != .costume, let costume = next[.costume], costume.hides.contains(slot) {
            next[.costume] = nil
        }
        return next
    }
}

// MARK: - Medal ↔ item

/// Which Flamey items a medal unlocks — what the Medals screen shows (Fun
/// only) and links into the Closet with.
enum FlameyMedalLink {
    private static let byBadge: [String: [FlameyItem]] = {
        var out: [String: [FlameyItem]] = [:]
        for item in FlameyItem.closet {
            guard let id = item.badgeId else { continue }
            out[id, default: []].append(item)
        }
        return out
    }()

    static func items(forBadge id: String) -> [FlameyItem] { byBadge[id] ?? [] }
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
    /// HOW it was earned, in the server's words ("You ran a 7:42 mile") —
    /// `earned_detail.summary` on the user's badge list. nil on an older
    /// server: the card falls back to the medal's requirement.
    var earnedSummary: String? = nil
    /// The day that happened (`earned_detail.date`, their calendar).
    var earnedDay: Date? = nil
    /// The workout that did it, when there was one — "View workout".
    var earnedWorkoutId: String? = nil

    /// The day to print beside HOW: the detail's own day, else the award.
    var earnedDate: Date? { earnedDay ?? earnedAt }

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
    static let outfitLines = ["Quick change!", "Outfit on!", "Ta-da!", "This one's a classic"]
    static let savedLines = ["Looking good!", "All set!", "Wearing it out!"]

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

    /// HOW an earned medal was earned: the server's own sentence ("You ran a
    /// 7:42 mile") when it sent one, else the medal's requirement ("Run a
    /// mile under 8:00") — never just a name and a date.
    static func howEarned(_ medal: FlameyMedalInfo, requirement: String) -> (text: String, isDetail: Bool) {
        if let summary = medal.earnedSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return (summary, true)
        }
        return (requirement, false)
    }

    /// "2026-08-14" (the server's calendar day) → local noon that day, so
    /// printing it can't slip a day across a timezone.
    static func parseDay(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let parts = raw.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]; c.hour = 12
        return Calendar.current.date(from: c)
    }
}

// MARK: - His name

/// Flamey's NAME — what he is called on every surface about the user's own
/// mascot ("Sparky's Closet", "New for Sparky", a friend's "Aaron's Sparky").
/// nil / absent = "Flamey", which is never stored. The rules MIRROR the
/// server's `parseDisplayName` (nameModeration.ts): trimmed, typographic
/// apostrophes folded, runs of spaces collapsed, letters (any script) +
/// digits + single spaces + `- ' . !` + emoji, at most 20 characters counted
/// the way a person counts them (grapheme clusters = Swift `Character`s).
/// The blocklist is the server's alone; its `not_allowed` is surfaced in
/// words here.
enum FlameyNameRules {
    static let fallback = "Flamey"
    static let maxLength = 20
    static let outfitMaxLength = 24

    static func display(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return fallback }
        return name
    }

    /// "Sparky's" / "James'" (matches `FriendFlameyFacts.possessive`).
    static func possessive(_ name: String) -> String {
        name.hasSuffix("s") ? "\(name)’" : "\(name)’s"
    }

    static func normalize(_ raw: String) -> String {
        var s = raw.precomposedStringWithCanonicalMapping
        s = s.replacingOccurrences(of: "[\u{2018}\u{2019}\u{02BC}]", with: "'", options: .regularExpression)
        s = s.replacingOccurrences(of: "[ \u{00A0}\u{2000}-\u{200A}\u{202F}\u{205F}\u{3000}]+", with: " ",
                                   options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// The typed text as it would be stored, or why not.
    static func validate(_ raw: String, maxLength: Int = maxLength) -> Result<String, FlameyNameIssue> {
        if raw.unicodeScalars.contains(where: {
            $0.properties.generalCategory == .control || $0 == "\u{2028}" || $0 == "\u{2029}"
        }) {
            return .failure(.characters)
        }
        let name = normalize(raw)
        guard !name.isEmpty else { return .failure(.empty) }
        guard name.unicodeScalars.allSatisfy(isAllowed) else { return .failure(.characters) }
        guard name.count <= maxLength else { return .failure(.tooLong) }
        return .success(name)
    }

    private static let punctuation: Set<Unicode.Scalar> = [" ", "-", "'", ".", "!"]
    private static let joiners: Set<Unicode.Scalar> = ["\u{200D}", "\u{FE0E}", "\u{FE0F}", "\u{20E3}"]

    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        let p = scalar.properties
        if punctuation.contains(scalar) || joiners.contains(scalar) { return true }
        if p.isAlphabetic { return true }
        switch p.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark, .decimalNumber, .letterNumber, .otherNumber: return true
        default: break
        }
        if p.isEmoji && (p.isEmojiPresentation || scalar.value > 0x238C) { return true }
        if p.isEmojiModifier || p.isEmojiModifierBase { return true }
        if (0x1F1E6...0x1F1FF).contains(scalar.value) || (0xE0020...0xE007F).contains(scalar.value) { return true }
        return false
    }
}

/// Why a name (his, or an outfit's) was refused — the server's `reason`
/// strings, in friendly words.
enum FlameyNameIssue: String, Equatable, Error {
    case tooLong = "too_long"
    case empty
    case characters
    case notAllowed = "not_allowed"

    func message(maxLength: Int = FlameyNameRules.maxLength) -> String {
        switch self {
        case .tooLong: return "That's a bit long — \(maxLength) characters at most."
        case .empty: return "Give it a name first."
        case .characters: return "Letters, numbers, spaces, emoji and - ' . ! only."
        case .notAllowed: return "Let's pick a different name — that one isn't allowed."
        }
    }
}

/// What happened to a change that has to reach the server.
enum FlameySaveOutcome: Equatable {
    /// On the server (or local-only by design, on an older server).
    case saved
    /// Kept on this phone; it syncs when the connection is back.
    case deferred
    /// Refused, with words to show beside the thing that was refused.
    case rejected(String)

    var isRejected: Bool {
        if case .rejected = self { return true }
        return false
    }

    var message: String? {
        switch self {
        case .saved: return nil
        case .deferred: return "Saved on this phone — it syncs when you're back online."
        case .rejected(let text): return text
        }
    }
}

// MARK: - Saved outfits

/// One of up to five saved looks. `id` is the LOCAL identity (the server's
/// id once it has one, else a phone-made one); `serverId` is what is sent
/// back so the server keeps the row. A look can name things no longer owned
/// — those draw as unavailable and are left off when it's worn.
struct FlameyOutfit: Identifiable, Hashable, Codable {
    var id: String
    var serverId: String?
    var name: String
    var look: FlameyLookChoice
    /// False when the SERVER dropped items it no longer counts as owned.
    var ownedOK: Bool = true

    static let max = 5

    init(id: String = "local-" + UUID().uuidString, serverId: String? = nil, name: String,
         look: FlameyLookChoice, ownedOK: Bool = true) {
        self.id = id
        self.serverId = serverId
        self.name = name
        self.look = look
        self.ownedOK = ownedOK
    }
}

// MARK: - Undo toast

struct FlameyClosetToast: Equatable, Identifiable {
    let id = UUID()
    let text: String
    /// The DRAFT to go back to; nil = nothing to undo.
    let undo: FlameyLookChoice?
}

/// "Save changes to Sparky's look?" — raised by `leave`, holding where the
/// person was going.
struct FlameyLeavePrompt: Identifiable {
    enum Answer { case save, discard, keepEditing }
    let id = UUID()
    let then: () -> Void
}

// MARK: - The model

/// Everything the Closet shows and does.
///
/// The Closet is an EDITING SESSION. `choice` is the DRAFT — what the stage
/// shows and every tap changes — and `savedChoice` is what he actually wears
/// everywhere else. Nothing leaves this screen until Save (`saveDraft`), and
/// Discard puts the draft back; leaving with a draft asks first
/// (`leave` → `leavePrompt`). Undo toasts step back WITHIN the draft.
/// `onChoiceChange` fires only on a save.
@MainActor @Observable
final class FlameyClosetModel {
    private(set) var owned: Set<FlameyItem>
    /// The draft on the stage.
    private(set) var choice: FlameyLookChoice
    /// What is saved — worn on the dashboard, widgets and friends' screens.
    private(set) var savedChoice: FlameyLookChoice
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
    /// Medal facts per badge id (name, icon, rarity, earned date, how).
    var medals: [String: FlameyMedalInfo]
    /// His name; nil = "Flamey".
    private(set) var name: String?
    /// Saved outfits, in the user's order (max `FlameyOutfit.max`).
    private(set) var outfits: [FlameyOutfit]
    /// "Save changes?" is up, holding what to do once it's answered.
    var leavePrompt: FlameyLeavePrompt?

    let facts: FlameyProgressFacts
    /// The day the stage resolves for (a holiday outfit comes on by itself).
    let date: Date
    let signupDate: Date?
    @ObservationIgnored var onChoiceChange: (FlameyLookChoice) -> Void = { _ in }
    /// Renames him on the server (nil = back to "Flamey").
    @ObservationIgnored var onRename: (String?) async -> FlameySaveOutcome = { _ in .saved }
    /// Replaces the outfit list on the server; the live glue hands the
    /// server's copy (its ids) back through `adoptOutfits`.
    @ObservationIgnored var onOutfitsChange: ([FlameyOutfit]) async -> FlameySaveOutcome = { _ in .saved }
    /// "Where to earn it": the host dismisses the Closet and goes there.
    /// nil where the Closet cannot leave for another tab (it is presented
    /// over a friend's sheet) — the card then says where, without a button.
    @ObservationIgnored var onEarn: ((FlameyEarnRoute) -> Void)? = nil
    /// "View workout" on a medal: the live host's workout screen for an id.
    /// nil (the harness) = no link.
    @ObservationIgnored var workoutView: ((String) -> AnyView)? = nil
    @ObservationIgnored private var lineSeed = 0

    init(owned: Set<FlameyItem>, choice: FlameyLookChoice, newItems: Set<FlameyItem> = [],
         facts: FlameyProgressFacts = .init(), medals: [String: FlameyMedalInfo] = [:],
         date: Date = Date(), signupDate: Date? = nil, focus: FlameyItem? = nil,
         name: String? = nil, outfits: [FlameyOutfit] = []) {
        self.owned = owned.union(FlameyItem.allCases.filter { $0.unlock == .always })
        self.choice = choice
        self.savedChoice = choice
        self.newItems = newItems
        self.facts = facts
        self.medals = medals
        self.date = date
        self.signupDate = signupDate
        self.name = name
        self.outfits = outfits
        // Open where the news is: the first new item's tab.
        let lead = focus ?? newItems.sorted { ($0.slot.sortIndex, $0.tier) < ($1.slot.sortIndex, $1.tier) }.first
        self.tab = lead.map { FlameyClosetTab.tab(for: $0.slot) } ?? .flame
        self.focus = lead
    }

    // MARK: Reading

    func owns(_ item: FlameyItem) -> Bool { owned.contains(item) }

    /// "Flamey", or what they named him.
    var displayName: String { FlameyNameRules.display(name) }
    /// "Sparky's".
    var possessiveName: String { FlameyNameRules.possessive(displayName) }

    /// The draft differs from what's saved: Save / Discard are offered and
    /// leaving asks first.
    var hasUnsavedChanges: Bool { choice != savedChoice }

    /// The draft, resolved for today — what the stage draws.
    var stageLook: FlameyLook {
        FlameyLook.resolve(owned: owned, choice: choice, date: date, signupDate: signupDate, detail: .full)
    }

    /// Everything he'd look like with `item` put on over the draft (owned or
    /// not — the detail card's preview; nothing is changed).
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

    /// Him in an arbitrary choice (the walkthrough's picks, an outfit chip).
    func look(for choice: FlameyLookChoice, detail: FlameyRenderDetail = .full) -> FlameyLook {
        FlameyLook.resolve(owned: owned, choice: choice, date: date, signupDate: signupDate, detail: detail)
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

    /// On him in the DRAFT (the Classic colour / bubble count when nothing
    /// else is picked — that IS what he's wearing).
    func isWorn(_ item: FlameyItem) -> Bool {
        if let picked = choice[item.slot] { return picked == item && owns(item) }
        return item.slot.basicItem == item
    }

    /// The item he wears in a slot in the draft.
    func worn(in slot: FlameySlot) -> FlameyItem? {
        guard let item = choice[slot], owns(item) else { return nil }
        return item
    }

    /// A slot the draft changed from what's saved.
    func isChanged(_ slot: FlameySlot) -> Bool { choice[slot] != savedChoice[slot] }

    /// How many slots the draft changed.
    var changedSlotCount: Int { FlameySlot.allCases.filter(isChanged).count }

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

    // MARK: Outfits, reading

    /// What an outfit names that isn't owned (any more) — drawn as
    /// unavailable, left off when worn.
    func unavailableItems(in outfit: FlameyOutfit) -> [FlameyItem] {
        outfit.look.items.filter { !owns($0) }
    }

    /// It would leave something off: an item it names isn't owned here, or
    /// the server already dropped one from its copy.
    func hasUnavailable(_ outfit: FlameyOutfit) -> Bool {
        !unavailableItems(in: outfit).isEmpty || !outfit.ownedOK
    }

    /// The outfit's look minus anything not owned — what wearing it does.
    func wearable(_ outfit: FlameyOutfit) -> FlameyLookChoice {
        var look = outfit.look
        for slot in FlameySlot.allCases where look[slot].map({ !owns($0) }) == true { look[slot] = nil }
        return look
    }

    /// The outfit the draft IS right now (its chip reads as selected).
    var currentOutfit: FlameyOutfit? { outfits.first { wearable($0) == choice } }

    var outfitsFull: Bool { outfits.count >= FlameyOutfit.max }

    /// "Outfit 3" — the save sheet's suggestion.
    var suggestedOutfitName: String {
        let taken = Set(outfits.map(\.name))
        var n = outfits.count + 1
        while taken.contains("Outfit \(n)") { n += 1 }
        return "Outfit \(n)"
    }

    // MARK: Doing — every one of these changes the DRAFT only

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
        // Picking the Classic colour / bubble is the same as leaving it basic.
        edit(choice.picking(item, in: item.slot), toast: "Trying on \(item.displayName)")
    }

    func takeOff(_ slot: FlameySlot) {
        guard let item = choice[slot] else { return }
        focus = item
        say(FlameyClosetCopy.takeOffLines[nextSeed() % FlameyClosetCopy.takeOffLines.count])
        var next = choice
        next[slot] = nil
        edit(next, toast: "Took off \(item.displayName)")
    }

    /// "Best look": the best thing owned in every everyday slot.
    func bestLook() {
        var next = FlameyLookChoice.basic
        for slot in FlameySlot.allCases {
            if let best = FlameyWardrobe.best(in: slot, owned: owned), best.slot.basicItem != best {
                next[slot] = best
            }
        }
        focus = nil
        say(FlameyClosetCopy.bestLines[nextSeed() % FlameyClosetCopy.bestLines.count])
        edit(next, toast: next.isBasic ? "Nothing to wear yet" : "Trying on your best look")
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
        edit(next, toast: "Trying a surprise look")
    }

    func surprise() {
        var rng = SystemRandomNumberGenerator()
        surprise(using: &rng)
    }

    /// "Basic": the Flamey from before the wardrobe (in the draft).
    func resetToBasic() {
        guard !choice.isBasic else { return }
        focus = nil
        say(FlameyClosetCopy.basicLines[nextSeed() % FlameyClosetCopy.basicLines.count])
        edit(.basic, toast: "Trying basic \(displayName)")
    }

    /// An outfit chip: its look goes into the DRAFT (Save wears it), less
    /// anything no longer owned.
    func tryOn(_ outfit: FlameyOutfit) {
        let next = wearable(outfit)
        focus = nil
        say(FlameyClosetCopy.outfitLines[nextSeed() % FlameyClosetCopy.outfitLines.count])
        let missing = unavailableItems(in: outfit).count
        let text: String
        if missing == 1 {
            text = "\(outfit.name) on — 1 item isn't unlocked"
        } else if missing > 1 {
            text = "\(outfit.name) on — \(missing) items aren't unlocked"
        } else if !outfit.ownedOK {
            text = "\(outfit.name) on — some items aren't unlocked"
        } else {
            text = "Trying on \(outfit.name)"
        }
        edit(next, toast: text)
    }

    /// Undo the last change — within the draft.
    func undo() {
        guard let previous = toast?.undo else { return }
        toast = nil
        focus = nil
        choice = previous
    }

    func clearToast(_ id: UUID) {
        if toast?.id == id { toast = nil }
    }

    // MARK: Save / discard

    /// Save: the draft becomes what he wears everywhere.
    func saveDraft() {
        guard hasUnsavedChanges else { return }
        savedChoice = choice
        onChoiceChange(choice)
        say(FlameyClosetCopy.savedLines[nextSeed() % FlameyClosetCopy.savedLines.count])
        toast = FlameyClosetToast(text: "Saved \(possessiveName) look", undo: nil)
    }

    /// Discard: back to what's saved.
    func discardDraft() {
        guard hasUnsavedChanges else { return }
        choice = savedChoice
        focus = nil
        toast = FlameyClosetToast(text: "Changes discarded", undo: nil)
    }

    /// The way out of the Closet (Done, a "where to earn it" button): asks
    /// first when the draft isn't saved.
    func leave(_ action: @escaping () -> Void) {
        if hasUnsavedChanges {
            leavePrompt = FlameyLeavePrompt(then: action)
        } else {
            action()
        }
    }

    /// "Save changes?" answered.
    func answerLeave(_ answer: FlameyLeavePrompt.Answer) {
        guard let prompt = leavePrompt else { return }
        leavePrompt = nil
        switch answer {
        case .save:
            saveDraft()
            prompt.then()
        case .discard:
            choice = savedChoice
            prompt.then()
        case .keepEditing:
            break
        }
    }

    /// The walkthrough's "Save this look": its picks are saved at once.
    func commit(_ next: FlameyLookChoice) {
        choice = next
        guard next != savedChoice else { return }
        savedChoice = next
        onChoiceChange(next)
    }

    /// Picks shown in the Closet's draft, unsaved.
    func setDraft(_ next: FlameyLookChoice) { choice = next }

    /// The server's copy replaced ours (a 400 re-sync, another device).
    /// A draft in progress is kept.
    func adopt(choice: FlameyLookChoice, owned: Set<FlameyItem>? = nil) {
        if let owned { self.owned = owned.union(FlameyItem.allCases.filter { $0.unlock == .always }) }
        let editing = hasUnsavedChanges
        savedChoice = choice
        if !editing { self.choice = choice }
    }

    func earn(_ item: FlameyItem) {
        guard let route = FlameyEarnRoute.route(for: item), route.buttonTitle != nil else { return }
        // The card comes down first: "Save changes?" is drawn by the Closet
        // itself, and would sit hidden under the card's sheet.
        detail = nil
        leave { [weak self] in self?.onEarn?(route) }
    }

    func clearLine() { line = nil }

    /// Point the caption at an item (a deep link, a walkthrough tap).
    func setFocus(_ item: FlameyItem?) { focus = item }

    /// A plain line in the toast (no undo).
    func announce(_ text: String) {
        toast = FlameyClosetToast(text: text, undo: nil)
    }

    /// "Seen": the New dots go once the Closet closes.
    func markAllSeen() { newItems = [] }

    // MARK: His name

    /// Validates, then saves (nil / blank / "Flamey" = back to the default).
    /// The name changes here unless it was refused.
    func rename(_ raw: String?) async -> FlameySaveOutcome {
        var next: String? = nil
        if let raw, !FlameyNameRules.normalize(raw).isEmpty {
            switch FlameyNameRules.validate(raw) {
            case .success(let valid): next = valid == FlameyNameRules.fallback ? nil : valid
            case .failure(let issue): return .rejected(issue.message())
            }
        }
        guard next != name else { return .saved }
        let outcome = await onRename(next)
        if outcome.isRejected { return outcome }
        name = next
        return outcome
    }

    /// The server's name (a pull after another device renamed him).
    func adoptName(_ name: String?) { self.name = name }

    // MARK: Outfits, writing

    /// "Save as outfit": the DRAFT under `name`, appended — or in place of
    /// `replacing` when all five are taken.
    func saveOutfit(named raw: String, replacing: FlameyOutfit.ID? = nil) async -> FlameySaveOutcome {
        let name: String
        switch FlameyNameRules.validate(raw, maxLength: FlameyNameRules.outfitMaxLength) {
        case .success(let valid): name = valid
        case .failure(let issue): return .rejected(issue.message(maxLength: FlameyNameRules.outfitMaxLength))
        }
        var next = outfits
        if let replacing, let i = next.firstIndex(where: { $0.id == replacing }) {
            next[i].name = name
            next[i].look = choice
            next[i].ownedOK = true
        } else {
            guard next.count < FlameyOutfit.max else {
                return .rejected("All \(FlameyOutfit.max) outfit slots are full — pick one to replace.")
            }
            next.append(FlameyOutfit(name: name, look: choice))
        }
        let outcome = await writeOutfits(next)
        if !outcome.isRejected { say("Saved as \(name)!") }
        return outcome
    }

    func renameOutfit(_ id: FlameyOutfit.ID, to raw: String) async -> FlameySaveOutcome {
        guard let i = outfits.firstIndex(where: { $0.id == id }) else { return .saved }
        switch FlameyNameRules.validate(raw, maxLength: FlameyNameRules.outfitMaxLength) {
        case .success(let valid):
            guard valid != outfits[i].name else { return .saved }
            var next = outfits
            next[i].name = valid
            return await writeOutfits(next)
        case .failure(let issue):
            return .rejected(issue.message(maxLength: FlameyNameRules.outfitMaxLength))
        }
    }

    func deleteOutfit(_ id: FlameyOutfit.ID) async -> FlameySaveOutcome {
        await writeOutfits(outfits.filter { $0.id != id })
    }

    func moveOutfit(_ id: FlameyOutfit.ID, by offset: Int) async -> FlameySaveOutcome {
        guard let i = outfits.firstIndex(where: { $0.id == id }) else { return .saved }
        let j = i + offset
        guard outfits.indices.contains(j) else { return .saved }
        var next = outfits
        next.swapAt(i, j)
        return await writeOutfits(next)
    }

    /// The server's copy (with its ids) — after a save, or a pull.
    func adoptOutfits(_ list: [FlameyOutfit]) { outfits = list }

    /// Optimistic: the list changes now; a refusal puts it back.
    private func writeOutfits(_ next: [FlameyOutfit]) async -> FlameySaveOutcome {
        let previous = outfits
        outfits = next
        let outcome = await onOutfitsChange(next)
        if outcome.isRejected { outfits = previous }
        return outcome
    }

    // MARK: Private

    private func edit(_ next: FlameyLookChoice, toast text: String) {
        let previous = choice
        guard next != previous else {
            toast = FlameyClosetToast(text: text, undo: nil)
            return
        }
        choice = next
        toast = FlameyClosetToast(text: text, undo: previous)
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
