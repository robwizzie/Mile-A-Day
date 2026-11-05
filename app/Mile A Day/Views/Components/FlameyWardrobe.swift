import SwiftUI

// FLAMEY'S WARDROBE — what he can wear, what he owns, and what he wears today.
//
// THIS FILE EXISTS TWICE, BYTE-IDENTICAL (and so do its three siblings,
// FlameyPalettes.swift, FlameyArt.swift and FlameyRender.swift):
//   app/Mile A Day/Views/Components/<file>   (the app)
//   app/MileADayWidgets/<file>                (widget extension)
// The widget extension can't see the app's files, so the ONE description of
// his look is compiled twice. Edit one, then `cp` it over the other — `cmp`
// every pair before committing. Nothing in here may depend on anything
// outside SwiftUI/Foundation (no MADTheme, no UserDefaults, no app models).
//
// Four ideas, kept separate on purpose:
//   - The CATALOG (`FlameyItem`) — string ids the backend validates against
//     (`backend/src/services/flameyCatalog.ts`); never rename one.
//   - OWNING an item is DERIVED from earned badge ids (+ `always`). Nothing
//     about ownership is stored, so it is retroactive by construction and no
//     style switch, reinstall or sign-out can take anything away.
//   - The user's CHOICE (`FlameyLookChoice`) — per slot, an item or nothing.
//     Nothing chosen = BASIC: he looks exactly as he did before the wardrobe
//     existed until the user picks something in the Closet. Owning an item
//     never puts it on him.
//   - The resolved `FlameyLook` — a pure value, one item per slot, what every
//     renderer draws.

// MARK: - Holidays

/// The holiday catalog. Raw values are the suffix of the backend's
/// `holiday_<key>` medal ids (`backend/src/services/holidays.ts`) and must
/// never be renamed — `user_badges` rows and shipped builds carry them.
enum HolidayKey: String, CaseIterable, Codable, Hashable {
    case newYearsDay = "new_years_day"
    case valentinesDay = "valentines_day"
    case stPatricksDay = "st_patricks_day"
    case easter
    case independenceDay = "independence_day"
    case halloween
    case thanksgiving
    case christmasEve = "christmas_eve"
    case christmas
    case newYearsEve = "new_years_eve"

    static let badgePrefix = "holiday_"

    var badgeId: String { Self.badgePrefix + rawValue }

    init?(badgeId: String) {
        guard badgeId.hasPrefix(Self.badgePrefix) else { return nil }
        self.init(rawValue: String(badgeId.dropFirst(Self.badgePrefix.count)))
    }

    var holidayName: String {
        switch self {
        case .newYearsDay: return "New Year's Day"
        case .valentinesDay: return "Valentine's Day"
        case .stPatricksDay: return "St. Patrick's Day"
        case .easter: return "Easter"
        case .independenceDay: return "Independence Day"
        case .halloween: return "Halloween"
        case .thanksgiving: return "Thanksgiving"
        case .christmasEve: return "Christmas Eve"
        case .christmas: return "Christmas"
        case .newYearsEve: return "New Year's Eve"
        }
    }

    /// The medal's name — mirrors `HOLIDAYS[].medalName` on the server.
    var medalName: String {
        switch self {
        case .newYearsDay: return "First Mile of the Year"
        case .valentinesDay: return "Sweetheart Mile"
        case .stPatricksDay: return "Lucky Mile"
        case .easter: return "Egg-cellent Mile"
        case .independenceDay: return "Freedom Mile"
        case .halloween: return "Spooky Mile"
        case .thanksgiving: return "Gobble Mile"
        case .christmasEve: return "Night Before Mile"
        case .christmas: return "Santa's Mile"
        case .newYearsEve: return "Last Mile of the Year"
        }
    }

    var medalDescription: String { "Walked or ran your mile on \(holidayName)." }

    /// SF Symbol for the medal — mirrors `HOLIDAYS[].icon` on the server. All
    /// exist in SF Symbols 4, i.e. on the iOS 17 floor.
    var medalIcon: String {
        switch self {
        case .newYearsDay: return "sparkles"
        case .valentinesDay: return "heart.fill"
        case .stPatricksDay: return "leaf.fill"
        case .easter: return "hare.fill"
        case .independenceDay: return "flag.fill"
        case .halloween: return "moon.stars.fill"
        case .thanksgiving: return "fork.knife"
        case .christmasEve: return "moon.fill"
        case .christmas: return "gift.fill"
        case .newYearsEve: return "party.popper.fill"
        }
    }
}

/// Which holiday a LOCAL calendar day is — the same rules as the server's
/// `holidaysInYear`, so the outfit he wears and the medal the walk earns are
/// decided by one calendar. Always GREGORIAN in the device's time zone:
/// `Calendar.current` can be Buddhist or Japanese, whose year numbers would
/// put Easter on the wrong Sunday.
enum HolidayCalendar {
    /// Western Easter Sunday — the anonymous Gregorian algorithm
    /// (Meeus/Jones/Butcher), exactly as `easterMonthDay` on the server.
    static func easter(year: Int) -> (month: Int, day: Int) {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return (month, day)
    }

    /// US Thanksgiving, the 4th Thursday of November — day of the month.
    static func thanksgivingDay(year: Int) -> Int {
        let nov1 = dayOfWeek(year: year, month: 11, day: 1) // 0 = Sunday
        let firstThursday = 1 + ((4 - nov1 + 7) % 7)
        return firstThursday + 21
    }

    /// Sakamoto's day-of-week, 0 = Sunday. Pure arithmetic, so no calendar or
    /// time zone can leak in.
    static func dayOfWeek(year: Int, month: Int, day: Int) -> Int {
        let t = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
        let y = month < 3 ? year - 1 : year
        return (y + y / 4 - y / 100 + y / 400 + t[month - 1] + day) % 7
    }

    static func holiday(year: Int, month: Int, day: Int) -> HolidayKey? {
        switch (month, day) {
        case (1, 1): return .newYearsDay
        case (2, 14): return .valentinesDay
        case (3, 17): return .stPatricksDay
        case (7, 4): return .independenceDay
        case (10, 31): return .halloween
        case (12, 24): return .christmasEve
        case (12, 25): return .christmas
        case (12, 31): return .newYearsEve
        default: break
        }
        let e = easter(year: year)
        if month == e.month, day == e.day { return .easter }
        if month == 11, day == thanksgivingDay(year: year) { return .thanksgiving }
        return nil
    }

    static func holiday(on date: Date, timeZone: TimeZone = .current) -> HolidayKey? {
        let c = components(of: date, timeZone: timeZone)
        return holiday(year: c.year, month: c.month, day: c.day)
    }

    static func components(of date: Date, timeZone: TimeZone = .current) -> (year: Int, month: Int, day: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    /// Is `date` the anniversary of `signup` — same month and day, at least a
    /// year later? A Feb 29 signup celebrates on Feb 28 in common years.
    static func isAnniversary(of signup: Date, on date: Date, timeZone: TimeZone = .current) -> Bool {
        let s = components(of: signup, timeZone: timeZone)
        let d = components(of: date, timeZone: timeZone)
        guard d.year > s.year else { return false }
        if s.month == d.month, s.day == d.day { return true }
        let leap = (d.year % 4 == 0 && d.year % 100 != 0) || d.year % 400 == 0
        return s.month == 2 && s.day == 29 && !leap && d.month == 2 && d.day == 28
    }

    /// Whole years since signup on `date` (for "Year 2!" copy); 0 if none.
    static func anniversaryYears(of signup: Date, on date: Date, timeZone: TimeZone = .current) -> Int {
        max(0, components(of: date, timeZone: timeZone).year - components(of: signup, timeZone: timeZone).year)
    }
}

// MARK: - Slots

/// Where on him an item goes. ONE item per slot — that is the whole of the
/// "never two hats" rule. Raw values are the backend's slot names.
///
/// Where each slot SITS, so two things never fight for one side:
///   back       behind him (capes, banner, wings, tail feathers)
///   trail      streams off to the viewer's LEFT, behind him
///   companion  stands on the viewer's RIGHT
///   held       in FRONT, at his side (the viewer's left, close to the body)
///   chest      flat, under the mouth only — there is no neck
///   aura       one effect around him (see `FlameyGlow`)
enum FlameySlot: String, CaseIterable, Codable, Hashable {
    case color, head, eyes, chest, back, feet, costume, held, trail, companion, aura, bubble

    var displayName: String {
        switch self {
        case .color: return "Color"
        case .head: return "Head"
        case .eyes: return "Eyes"
        case .chest: return "Chest"
        case .back: return "Back"
        case .feet: return "Feet"
        case .costume: return "Costume"
        case .held: return "Held"
        case .trail: return "Trail"
        case .companion: return "Companion"
        case .aura: return "Aura"
        case .bubble: return "Speech Bubble"
        }
    }

    /// Kept on a small surface (widgets, friend card, Live Activity,
    /// tracker). Everything else is too wide, too noisy, or unreadable there.
    var survivesCompact: Bool {
        switch self {
        case .color, .head, .eyes, .chest, .feet, .costume: return true
        case .back, .held, .trail, .companion, .aura, .bubble: return false
        }
    }
}

/// How much of his wardrobe a surface can carry. Decided by the SURFACE, not
/// by the look: the same person reads the same outfit everywhere, and a small
/// surface simply leaves off the pieces it has no room for.
enum FlameyRenderDetail: String, Codable, Hashable {
    /// Hero, share cards, the Closet: everything, including the rocket jets
    /// and the winged-sandal hover.
    case full
    /// Widgets, the friend card, the Live Activity, the tracker: colour,
    /// head, eyes, chest, feet and costume only — standing on the ground.
    case compact

    /// Below this footprint a surface is compact however it asks.
    static let compactThreshold: CGFloat = 100

    static func forSize(_ size: CGFloat) -> FlameyRenderDetail {
        size < compactThreshold ? .compact : .full
    }
}

// MARK: - Families (grouping + how-to-unlock copy)

/// What EARNS an item — one family per medal ladder. The Closet groups by it
/// and every "how to unlock" line is written from it.
enum FlameyFamily: String, CaseIterable, Hashable {
    case starter, streakDays, lifetimeMiles, pace, dailyChallenges, weeklyChallenges,
         competitionsEntered, competitionsWon, organizer, hypes, distanceInADay,
         buddyWalks, ghosts, stories, nudges, firsts, holidays, mood, plus, monthly

    var displayName: String {
        switch self {
        case .starter: return "Starter"
        case .streakDays: return "Streak Days"
        case .lifetimeMiles: return "Lifetime Miles"
        case .pace: return "Pace"
        case .dailyChallenges: return "Daily Challenges"
        case .weeklyChallenges: return "Weekly Challenges"
        case .competitionsEntered: return "Competitions Entered"
        case .competitionsWon: return "Competitions Won"
        case .organizer: return "Organizer"
        case .hypes: return "Hypes Given"
        case .distanceInADay: return "Distance in One Day"
        case .buddyWalks: return "Buddy Walks"
        case .ghosts: return "Ghost Races"
        case .stories: return "Stories"
        case .nudges: return "Nudges Sent"
        case .firsts: return "Firsts"
        case .holidays: return "Holidays"
        case .mood: return "Moods"
        case .plus: return "Mile A Day+"
        case .monthly: return "Monthly Flames"
        }
    }
}

// MARK: - Items

/// Everything he can wear. Raw values are the backend's catalog ids — STABLE,
/// stored in `users.flamey_look` and sent by shipped builds; never rename one.
///
/// An item is its SKIN (FlameySkin.swift, `backend/flamey-skins/<id>.json`):
/// slot, unlock, rules and art all come from the skin catalog, so a skin added
/// on the server after this build is an item here too. The named constants
/// below are the items the app's own logic refers to (mood dressing, holiday
/// outfits, the starter colour); `init(rawValue:)` accepts any id the catalog
/// has and nothing else, so an unknown id is dropped exactly as before.
struct FlameyItem: RawRepresentable, Hashable, Codable {
    let rawValue: String

    /// An id the catalog has (and this renderer can draw); nil otherwise.
    init?(rawValue: String) {
        guard let skin = FlameySkinCatalog.shared[rawValue], FlameySlot(rawValue: skin.slot) != nil else { return nil }
        self.rawValue = rawValue
    }

    /// The items this build names in code. Always in the bundled catalog.
    private init(known: String) { rawValue = known }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let item = FlameyItem(rawValue: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Unknown Flamey item \(raw)"))
        }
        self = item
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    static let classic = FlameyItem(known: "classic")
    static let ember = FlameyItem(known: "ember")
    static let lime = FlameyItem(known: "lime")
    static let ruby = FlameyItem(known: "ruby")
    static let lavender = FlameyItem(known: "lavender")
    static let sunflower = FlameyItem(known: "sunflower")
    static let mint = FlameyItem(known: "mint")
    static let sapphire = FlameyItem(known: "sapphire")
    static let violet = FlameyItem(known: "violet")
    static let rose = FlameyItem(known: "rose")
    static let teal = FlameyItem(known: "teal")
    static let arctic = FlameyItem(known: "arctic")
    static let midnight = FlameyItem(known: "midnight")
    static let sunset = FlameyItem(known: "sunset")
    static let aurora = FlameyItem(known: "aurora")
    static let ocean = FlameyItem(known: "ocean")
    static let lavaLamp = FlameyItem(known: "lava_lamp")
    static let galaxy = FlameyItem(known: "galaxy")
    static let candy = FlameyItem(known: "candy")
    static let northernLights = FlameyItem(known: "northern_lights")
    static let gold = FlameyItem(known: "gold")
    static let prism = FlameyItem(known: "prism")
    static let cosmic = FlameyItem(known: "cosmic")
    static let eternal = FlameyItem(known: "eternal")
    static let phantom = FlameyItem(known: "phantom")
    static let electric = FlameyItem(known: "electric")
    static let roseGold = FlameyItem(known: "rose_gold")
    static let obsidian = FlameyItem(known: "obsidian")
    static let tropic = FlameyItem(known: "tropic")
    static let frostbite = FlameyItem(known: "frostbite")
    static let sweetheart = FlameyItem(known: "sweetheart")
    static let luckyClover = FlameyItem(known: "lucky_clover")
    static let aprilShowers = FlameyItem(known: "april_showers")
    static let wildflower = FlameyItem(known: "wildflower")
    static let sunburst = FlameyItem(known: "sunburst")
    static let firecracker = FlameyItem(known: "firecracker")
    static let watermelon = FlameyItem(known: "watermelon")
    static let fallingLeaves = FlameyItem(known: "falling_leaves")
    static let jackOLantern = FlameyItem(known: "jack_o_lantern")
    static let sweaterWeather = FlameyItem(known: "sweater_weather")
    static let twinkleLights = FlameyItem(known: "twinkle_lights")
    static let sweatband = FlameyItem(known: "sweatband")
    static let ballCap = FlameyItem(known: "ball_cap")
    static let visor = FlameyItem(known: "visor")
    static let beanie = FlameyItem(known: "beanie")
    static let bucketHat = FlameyItem(known: "bucket_hat")
    static let safariHat = FlameyItem(known: "safari_hat")
    static let cowboyHat = FlameyItem(known: "cowboy_hat")
    static let aviatorCap = FlameyItem(known: "aviator_cap")
    static let headlampHelmet = FlameyItem(known: "headlamp_helmet")
    static let crown = FlameyItem(known: "crown")
    static let laurelWreath = FlameyItem(known: "laurel_wreath")
    static let vikingHelmet = FlameyItem(known: "viking_helmet")
    static let directorsBeret = FlameyItem(known: "directors_beret")
    static let santaHat = FlameyItem(known: "santa_hat")
    static let heartBopper = FlameyItem(known: "heart_bopper")
    static let leprechaunHat = FlameyItem(known: "leprechaun_hat")
    static let bunnyEars = FlameyItem(known: "bunny_ears")
    static let starHat = FlameyItem(known: "star_hat")
    static let countdownHat = FlameyItem(known: "countdown_hat")
    static let starStickers = FlameyItem(known: "star_stickers")
    static let roundSpecs = FlameyItem(known: "round_specs")
    static let classicShades = FlameyItem(known: "classic_shades")
    static let aviators = FlameyItem(known: "aviators")
    static let heartGlasses = FlameyItem(known: "heart_glasses")
    static let cyberVisor = FlameyItem(known: "cyber_visor")
    static let starGlasses = FlameyItem(known: "star_glasses")
    static let bandana = FlameyItem(known: "bandana")
    static let bowTie = FlameyItem(known: "bow_tie")
    static let finisherMedal = FlameyItem(known: "finisher_medal")
    static let starBadge = FlameyItem(known: "star_badge")
    static let championSash = FlameyItem(known: "champion_sash")
    static let goldChain = FlameyItem(known: "gold_chain")
    static let trophyPendant = FlameyItem(known: "trophy_pendant")
    static let polaroid = FlameyItem(known: "polaroid")
    static let holidayScarf = FlameyItem(known: "holiday_scarf")
    static let redCape = FlameyItem(known: "red_cape")
    static let blueCape = FlameyItem(known: "blue_cape")
    static let royalCape = FlameyItem(known: "royal_cape")
    static let championCape = FlameyItem(known: "champion_cape")
    static let victoryBanner = FlameyItem(known: "victory_banner")
    static let goldenWings = FlameyItem(known: "golden_wings")
    static let turkeyFeathers = FlameyItem(known: "turkey_feathers")
    static let canvasSneakers = FlameyItem(known: "canvas_sneakers")
    static let trainers = FlameyItem(known: "trainers")
    static let racingFlats = FlameyItem(known: "racing_flats")
    static let neonSoles = FlameyItem(known: "neon_soles")
    static let trackSpikes = FlameyItem(known: "track_spikes")
    static let rocketBoots = FlameyItem(known: "rocket_boots")
    static let lightningKicks = FlameyItem(known: "lightning_kicks")
    static let wingedSandals = FlameyItem(known: "winged_sandals")
    static let ghostSheet = FlameyItem(known: "ghost_sheet")
    static let astronautHelmet = FlameyItem(known: "astronaut_helmet")
    static let pumpkinSuit = FlameyItem(known: "pumpkin_suit")
    static let skeletonSuit = FlameyItem(known: "skeleton_suit")
    static let checkeredFlag = FlameyItem(known: "checkered_flag")
    static let stopwatch = FlameyItem(known: "stopwatch")
    static let pomPoms = FlameyItem(known: "pom_poms")
    static let foamFinger = FlameyItem(known: "foam_finger")
    static let megaphone = FlameyItem(known: "megaphone")
    static let confettiCannon = FlameyItem(known: "confetti_cannon")
    static let emberSparks = FlameyItem(known: "ember_sparks")
    static let dustPuffs = FlameyItem(known: "dust_puffs")
    static let speedLines = FlameyItem(known: "speed_lines")
    static let cometTail = FlameyItem(known: "comet_tail")
    static let smokeRings = FlameyItem(known: "smoke_rings")
    static let starTrail = FlameyItem(known: "star_trail")
    static let rainbowStreak = FlameyItem(known: "rainbow_streak")
    static let lightningTrail = FlameyItem(known: "lightning_trail")
    static let fireworks = FlameyItem(known: "fireworks")
    static let phoenixFeathers = FlameyItem(known: "phoenix_feathers")
    static let auroraRibbon = FlameyItem(known: "aurora_ribbon")
    static let meteorShower = FlameyItem(known: "meteor_shower")
    static let spark = FlameyItem(known: "spark")
    static let firefly = FlameyItem(known: "firefly")
    static let flameyJr = FlameyItem(known: "flamey_jr")
    static let sparkTrio = FlameyItem(known: "spark_trio")
    static let lantern = FlameyItem(known: "lantern")
    static let phoenixChick = FlameyItem(known: "phoenix_chick")
    static let cometPup = FlameyItem(known: "comet_pup")
    static let friendlyGhost = FlameyItem(known: "friendly_ghost")
    static let spectralGlow = FlameyItem(known: "spectral_glow")
    static let flicker = FlameyItem(known: "flicker")
    static let spotlight = FlameyItem(known: "spotlight")
    static let paparazzi = FlameyItem(known: "paparazzi")
    static let classicBubble = FlameyItem(known: "classic_bubble")
    static let comic = FlameyItem(known: "comic")
    static let neon = FlameyItem(known: "neon")
    static let pixel = FlameyItem(known: "pixel")
    static let goldBubble = FlameyItem(known: "gold_bubble")
    static let moodShades = FlameyItem(known: "mood_shades")
    static let partyHat = FlameyItem(known: "party_hat")
    static let nightcap = FlameyItem(known: "nightcap")

    /// Every item the catalog has, in Closet order (mood dressing included).
    static var allCases: [FlameyItem] {
        FlameySkinCatalog.shared.all.compactMap { FlameySlot(rawValue: $0.slot) == nil ? nil : FlameyItem(known: $0.id) }
    }

    /// Every Closet item, in catalog order (mood dressing excluded).
    static var closet: [FlameyItem] { allCases.filter { !$0.isMoodProp } }

    /// This item's skin: its art, rules and copy as data.
    var skin: FlameySkin? { FlameySkinCatalog.shared[rawValue] }

    var isMoodProp: Bool { skin?.moodProp ?? false }

    var slot: FlameySlot { skin.flatMap { FlameySlot(rawValue: $0.slot) } ?? .color }

    /// How it becomes his. Mirrors the backend catalog row for row (its CI
    /// check holds the skin files to it).
    var unlock: FlameyUnlock {
        guard let u = skin?.unlock else { return .always }
        if let s = u as? String {
            switch s {
            case "plus": return .plus
            default: return .always
            }
        }
        if let d = u as? [String: Any] {
            if let b = d["badge"] as? String { return .badge(b) }
            if let m = (d["month"] as? NSNumber)?.intValue { return .month(m) }
            if let p = d["purchase"] as? String { return .purchase(productId: p) }
        }
        return .always
    }

    var badgeId: String? {
        if case .badge(let id) = unlock { return id }
        return nil
    }

    /// The calendar month (1–12) a Monthly Flame belongs to; nil otherwise.
    var month: Int? {
        if case .month(let m) = unlock { return m }
        return nil
    }

    /// The twelve Monthly Flames, January first. Mirrors the backend's
    /// `MONTHLY_FLAMES` (monthlyFlames.ts).
    static var monthlyFlames: [FlameyItem] {
        (1...12).compactMap { m in allCases.first { $0.month == m } }
    }

    static func monthlyFlame(for month: Int) -> FlameyItem? {
        monthlyFlames.first { $0.month == month }
    }

    /// "October" — fixed English, like the rest of the closet's copy.
    static func monthName(_ month: Int) -> String {
        let names = ["January", "February", "March", "April", "May", "June", "July",
                     "August", "September", "October", "November", "December"]
        return (1...12).contains(month) ? names[month - 1] : ""
    }

    /// The holiday this item is the outfit for — worn automatically on the
    /// day, owned or not.
    var holidays: [HolidayKey] { (skin?.holidays ?? []).compactMap(HolidayKey.init(rawValue:)) }

    var isHolidayOutfit: Bool { !holidays.isEmpty }

    /// Picked by the Closet's "Best look" action when owned (the skin says;
    /// holiday outfits, costumes, Plus and Monthly items never are).
    var autoEligible: Bool {
        if let v = skin?.autoEligible { return v }
        if isMoodProp || isHolidayOutfit || slot == .costume || unlock == .plus || month != nil { return false }
        return true
    }

    /// Order WITHIN a slot ("Best look" takes the highest owned): the
    /// difficulty of the medal behind it.
    var tier: Int { skin?.tier ?? 0 }

    /// Slots this item covers up. A costume is worn INSTEAD of what it hides.
    var hides: Set<FlameySlot> { Set((skin?.ruleStrings("hides") ?? []).compactMap(FlameySlot.init(rawValue:))) }

    /// Clashes that aren't a whole slot (the star glasses and the sweatband).
    func clashes(with other: FlameyItem) -> Bool {
        (skin?.ruleStrings("clashes").contains(other.rawValue) ?? false)
            || (other.skin?.ruleStrings("clashes").contains(rawValue) ?? false)
    }

    /// Lifts him off the ground (a fraction of his body unit) on a full
    /// surface: the rocket jets and the winged hover.
    var hoverLift: CGFloat { CGFloat(skin?.rule("hover_lift") ?? 0) }

    var displayName: String { skin?.name ?? rawValue }

    var family: FlameyFamily {
        if let f = skin.flatMap({ FlameyFamily(rawValue: $0.family) }) { return f }
        if isMoodProp { return .mood }
        if isHolidayOutfit { return .holidays }
        if unlock == .plus { return .plus }
        if month != nil { return .monthly }
        guard let id = badgeId else { return .starter }
        if id.hasPrefix("streak_") || id.hasPrefix("consistency_") { return .streakDays }
        if id.hasPrefix("miles_") { return .lifetimeMiles }
        if id.hasPrefix("pace_") { return .pace }
        if id.hasPrefix("challenge_") { return .dailyChallenges }
        if id.hasPrefix("weekly_") { return .weeklyChallenges }
        if id.hasPrefix("comp_entered_") { return .competitionsEntered }
        if id.hasPrefix("comp_won_") { return .competitionsWon }
        if id.hasPrefix("comp_started_") { return .organizer }
        if id.hasPrefix("hype_") { return .hypes }
        if id.hasPrefix("daily_") { return .distanceInADay }
        if id.hasPrefix("buddy_") { return .buddyWalks }
        if id.hasPrefix("ghost_") { return .ghosts }
        if id.hasPrefix("story_") { return .stories }
        if id.hasPrefix("nudge_") { return .nudges }
        return .firsts
    }

    /// "Run a sub-7 mile" — the how-to-unlock line (the skin's, else written
    /// from the medal).
    var unlockCopy: String {
        if let copy = skin?.unlockCopy, !copy.isEmpty { return copy }
        if isMoodProp { return "Worn with his mood" }
        switch unlock {
        case .always: return "Always his"
        case .purchase: return "In the shop"
        case .plus: return "Included with Mile A Day+"
        case .month(let m): return "Walk your mile every day of \(FlameyItem.monthName(m))"
        case .badge(let id): return Self.unlockCopy(badgeId: id)
        case .streak(let days): return "Reach a \(days.formatted())-day streak"
        }
    }

    static func unlockCopy(badgeId id: String) -> String {
        func n(_ prefix: String) -> Int? { Int(id.dropFirst(prefix.count)) }
        func plural(_ count: Int, _ one: String, _ many: String) -> String {
            count == 1 ? one : "\(many.replacingOccurrences(of: "#", with: count.formatted()))"
        }
        if let key = HolidayKey(badgeId: id) { return "Walk your mile on \(key.holidayName)" }
        switch id {
        case "special_first_mile": return "Walk your first mile"
        case "special_first_week": return "Walk every day for a week"
        case "consistency_3": return "Walk 3 days in a row"
        case "consistency_5": return "Walk 5 days in a row"
        case "daily_2": return "Walk 2 miles in one day"
        case "daily_3": return "Cover a 5K in one day"
        case "daily_10k": return "Cover a 10K in one day"
        case "daily_half": return "Cover a half marathon in one day"
        case "daily_marathon": return "Cover a marathon in one day"
        case "daily_50k": return "Cover a 50K in one day"
        case "daily_ultra": return "Go ultra in one day"
        case "ghost_margin_15": return "Beat a ghost by 15 seconds"
        case "ghost_margin_45": return "Beat a ghost by 45 seconds"
        default: break
        }
        if id.hasPrefix("streak_"), let d = n("streak_") { return "Reach a \(d.formatted())-day streak" }
        if id.hasPrefix("miles_"), let m = n("miles_") { return "Walk \(m.formatted()) lifetime miles" }
        if id.hasPrefix("pace_"), let p = Int(id.dropFirst("pace_".count).dropLast("min".count)) { return "Run a sub-\(p) mile" }
        if id.hasPrefix("challenge_"), let c = n("challenge_") { return plural(c, "Complete a daily challenge", "Complete # daily challenges") }
        if id.hasPrefix("weekly_streak_"), let w = n("weekly_streak_") { return "Finish weekly challenges \(w) weeks in a row" }
        if id.hasPrefix("weekly_"), let w = n("weekly_") { return plural(w, "Complete a weekly challenge", "Complete # weekly challenges") }
        if id.hasPrefix("comp_entered_"), let c = n("comp_entered_") { return plural(c, "Enter a competition", "Enter # competitions") }
        if id.hasPrefix("comp_won_"), let c = n("comp_won_") { return plural(c, "Win a competition", "Win # competitions") }
        if id.hasPrefix("comp_started_"), let c = n("comp_started_") { return plural(c, "Start a competition", "Start # competitions") }
        if id.hasPrefix("hype_"), let h = n("hype_") { return plural(h, "Give a hype", "Give # hypes") }
        if id.hasPrefix("nudge_"), let h = n("nudge_") { return plural(h, "Send a nudge", "Send # nudges") }
        if id.hasPrefix("story_"), let s = n("story_") { return plural(s, "Post a story", "Post # stories") }
        if id.hasPrefix("daily_"), let d = n("daily_") { return "Walk \(d) miles in one day" }
        if id.hasPrefix("buddy_done_"), let b = n("buddy_done_") { return plural(b, "Finish a buddy walk", "Finish # buddy walks") }
        if id.hasPrefix("buddy_crew_"), let b = n("buddy_crew_") { return "Walk in a crew of \(b)" }
        if id.hasPrefix("buddy_won_"), let b = n("buddy_won_") { return plural(b, "Win a buddy race", "Win # buddy races") }
        if id.hasPrefix("ghost_beat_"), let g = n("ghost_beat_") { return plural(g, "Beat a ghost", "Beat # ghosts") }
        return "Earn the medal"
    }
}

/// How an item becomes his. Derived, never stored.
enum FlameyUnlock: Hashable {
    /// Always his (the starter colour and bubble, the mood dressing).
    case always
    /// His once this badge is earned.
    case badge(String)
    /// His while the user has Mile A Day+. Never derived locally: the
    /// server's `owned_item_ids` (which checks entitlement) is what grants it,
    /// so a lapse drops it everywhere at once.
    case plus
    /// A Monthly Flame: his once that calendar month (1–12) has been PERFECT
    /// — every day done, any year. Server-decided like `.plus`.
    case month(Int)
    /// Reserved for a one-off purchasable item (StoreKit product id). Nothing
    /// uses it yet; owned by nobody.
    case purchase(productId: String)
    /// Retired: streak gear used to unlock on the LONGEST streak alone. Kept
    /// so the shape can express it again; no item uses it.
    case streak(Int)
}

// MARK: - Ownership

enum FlameyWardrobe {
    /// Everything owned, from earned badge ids. Retroactive by construction:
    /// a medal earned before the wardrobe existed unlocks its item the moment
    /// this runs.
    static func owned(earnedBadgeIds: Set<String>) -> Set<FlameyItem> {
        Set(FlameyItem.allCases.filter { item in
            switch item.unlock {
            case .always: return true
            case .badge(let id): return earnedBadgeIds.contains(id)
            case .plus, .month, .purchase, .streak: return false
            }
        })
    }

    /// Every badge id the catalog depends on (what a widget mirror stores).
    static var catalogBadgeIds: Set<String> {
        Set(FlameyItem.allCases.compactMap(\.badgeId))
    }

    /// The streak-colour medals a LONGEST streak implies. The server awards
    /// them from the same figure, so this only ever fills a gap while the
    /// badge list is loading (and dresses a friend whose profile block
    /// carries the number but not the medals).
    static func impliedBadgeIds(longestStreak: Int) -> Set<String> {
        var ids = Set<String>()
        for item in FlameyItem.allCases where item.slot == .color {
            guard let id = item.badgeId else { continue }
            if id.hasPrefix("streak_"), let days = Int(id.dropFirst("streak_".count)), longestStreak >= days {
                ids.insert(id)
            }
            if id.hasPrefix("consistency_"), let days = Int(id.dropFirst("consistency_".count)), longestStreak >= days {
                ids.insert(id)
            }
        }
        return ids
    }

    /// The best owned item in `slot` (highest tier) — what the Closet's "Best
    /// look" action picks. Never applied on its own: nothing chosen is basic.
    static func best(in slot: FlameySlot, owned: Set<FlameyItem>) -> FlameyItem? {
        owned.filter { $0.slot == slot && $0.autoEligible }
            .max { ($0.tier, $0.rawValue) < ($1.tier, $1.rawValue) }
    }

    /// Closet items in `slot`, in tier order.
    static func items(in slot: FlameySlot) -> [FlameyItem] {
        FlameyItem.closet.filter { $0.slot == slot }.sorted { $0.tier < $1.tier }
    }
}

// MARK: - The user's choice (wire format)

/// What the user picked in the Closet: at most one item per slot. A slot with
/// nothing picked is BASIC — the bare figure (Classic colour, the classic
/// bubble, nothing worn) — and so is the whole look before the Closet is ever
/// opened. Owning something never dresses him in it.
///
/// The WIRE FORMAT is the backend's `users.flamey_look`: `{ "<slot>":
/// "<itemId>" }`. A missing slot and an explicit `null` (written by builds
/// that had an "auto" setting) both mean nothing; an id this build doesn't
/// know (a newer catalog) or one filed under the wrong slot is dropped, never
/// a failure; mood dressing never goes on the wire.
struct FlameyLookChoice: Hashable, Codable {
    private(set) var slots: [FlameySlot: FlameyItem] = [:]

    /// Nothing picked anywhere — how everyone starts.
    static let basic = FlameyLookChoice()

    init() {}

    subscript(slot: FlameySlot) -> FlameyItem? {
        get { slots[slot] }
        set {
            if let item = newValue, item.slot == slot, !item.isMoodProp {
                slots[slot] = item
            } else {
                slots[slot] = nil
            }
        }
    }

    var isBasic: Bool { slots.isEmpty }

    /// Every picked item, in slot order.
    var items: [FlameyItem] { FlameySlot.allCases.compactMap { slots[$0] } }

    /// From the wire dictionary (`[slot: id-or-nil]`).
    init(wire: [String: String?]) {
        for (key, value) in wire {
            guard let slot = FlameySlot(rawValue: key), let raw = value,
                  let item = FlameyItem(rawValue: raw), item.slot == slot, !item.isMoodProp else { continue }
            slots[slot] = item
        }
    }

    /// To the wire dictionary: only picked slots.
    var wire: [String: String?] {
        var out: [String: String?] = [:]
        for (slot, item) in slots { out[slot.rawValue] = .some(item.rawValue) }
        return out
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        // `null` (or anything but an object) for the whole look is basic,
        // like an empty object — never a failure.
        var wire: [String: String?] = [:]
        if let c = try? decoder.container(keyedBy: Key.self) {
            for key in c.allKeys {
                if let raw = try? c.decode(String.self, forKey: key) {
                    wire[key.stringValue] = .some(raw)
                }
            }
        }
        self.init(wire: wire)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        for slot in FlameySlot.allCases {
            guard let item = slots[slot] else { continue }
            try c.encode(item.rawValue, forKey: Key(stringValue: slot.rawValue))
        }
    }
}

// MARK: - The resolved look

/// Which ONE halo-class effect is on him. Only one at a time, or a legendary
/// colour + golden wings + an aura stack into noise.
///
/// Precedence: an aura you chose > golden wings > a legendary colour's own
/// halo/embers. The loser isn't gone — the colour still colours him, the
/// wings still draw — only its glow is withheld.
enum FlameyGlow: Hashable {
    case none
    case aura(FlameyItem)
    case wings
    case colorHalo
}

/// What Flamey is wearing — the ONE description every renderer draws. A pure
/// value: resolve it once, pass it everywhere.
struct FlameyLook: Equatable, Hashable, Codable {
    private(set) var worn: [FlameySlot: FlameyItem] = [:]
    /// Today's holiday, if any — for copy ("Boo!"), not drawing.
    var holiday: HolidayKey? = nil
    /// The anniversary of the day he met you.
    var isAnniversary: Bool = false
    /// The surface's size class (see `FlameyRenderDetail`).
    var detail: FlameyRenderDetail = .full
    /// The one halo-class effect (see `FlameyGlow`).
    var glow: FlameyGlow = .none

    static let plain = FlameyLook()

    var isPlain: Bool { worn.isEmpty }

    subscript(slot: FlameySlot) -> FlameyItem? { worn[slot] }

    /// Everything worn, in catalog slot order.
    var items: [FlameyItem] { FlameySlot.allCases.compactMap { worn[$0] } }

    func wears(_ item: FlameyItem) -> Bool { worn[item.slot] == item }

    /// Puts `item` in its slot, replacing whatever was there.
    mutating func wear(_ item: FlameyItem) { worn[item.slot] = item }

    mutating func takeOff(_ slot: FlameySlot) { worn[slot] = nil }

    /// The colour item he burns in (Classic = the figure's own palette).
    var color: FlameyItem { worn[.color] ?? .classic }

    /// The speech-bubble style (Classic when none or on a compact surface).
    var bubble: FlameyItem { detail == .full ? (worn[.bubble] ?? .classicBubble) : .classicBubble }

    /// How far off the ground he floats, as a fraction of his body unit. Zero
    /// on a compact surface: jets and hover are for the big screens.
    var hoverLift: CGFloat {
        guard detail == .full, let feet = worn[.feet] else { return 0 }
        return feet.hoverLift
    }

    /// The draw order for the front of him.
    var frontItems: [FlameyItem] {
        [FlameySlot.feet, .costume, .chest, .eyes, .head, .held].compactMap { worn[$0] }
    }

    /// Resolves the look for a day.
    ///
    /// Precedence, highest first, one item per slot:
    ///   1. TODAY's holiday outfit — on the day, owned or not, whatever you
    ///      chose (a chosen costume that would hide it comes off). The
    ///      sign-up anniversary puts the party hat on, below the holiday.
    ///   2. Mood dressing — HEAD only (nightcap at bedtime, party hat on a
    ///      milestone), and only when no costume is worn. The done-shades
    ///      only fill EYES when nothing is there.
    ///   3. Your choice — an owned item. An item you no longer own, and every
    ///      slot you never picked, is simply empty: nothing is worn that
    ///      wasn't chosen (or put on by the day or the mood).
    /// Colour is never overridden by a mood or a holiday. Then what worn
    /// items `hides` / clash with comes off, and a compact surface drops the
    /// slots it can't carry.
    static func resolve(
        owned: Set<FlameyItem>,
        choice: FlameyLookChoice = .basic,
        date: Date = Date(),
        mood: [FlameyItem] = [],
        signupDate: Date? = nil,
        detail: FlameyRenderDetail = .full,
        timeZone: TimeZone = .current
    ) -> FlameyLook {
        var look = FlameyLook()
        look.detail = detail
        let holiday = HolidayCalendar.holiday(on: date, timeZone: timeZone)
        let anniversary = signupDate.map {
            HolidayCalendar.isAnniversary(of: $0, on: date, timeZone: timeZone)
        } ?? false
        look.holiday = holiday
        look.isAnniversary = anniversary
        let owned = owned.union(FlameyItem.allCases.filter { $0.unlock == .always })

        // 3. The choice.
        for item in choice.items where owned.contains(item) {
            look.wear(item)
        }

        // 2. Mood: head only (and only uncostumed); shades only on bare eyes.
        for item in mood where item.isMoodProp {
            switch item.slot {
            case .head where look[.costume] == nil: look.wear(item)
            case .eyes where look[.eyes] == nil: look.wear(item)
            default: break
            }
        }

        // 1. The day itself.
        var dayItems: [FlameyItem] = []
        if anniversary { dayItems.append(.partyHat) }
        if let holiday {
            dayItems += FlameyItem.allCases.filter { $0.holidays.contains(holiday) }
        }
        for item in dayItems {
            if item.slot != .costume, let costume = look[.costume], costume.hides.contains(item.slot) {
                look.takeOff(.costume)
            }
            look.wear(item)
        }
        let dayWorn = Set(dayItems.filter { look.wears($0) })

        // What the outfit covers up. Colour is never hidden: a costume
        // covers his body, and what peeks out (the sheet's tip, the bowl) is
        // still his colour.
        let hidden = look.items.reduce(into: Set<FlameySlot>()) { $0.formUnion($1.hides) }
        for slot in hidden where slot != .color { look.takeOff(slot) }
        for a in look.items {
            for b in look.items where a != b && a.clashes(with: b) {
                // The day's item wins a clash; otherwise the eyes do.
                let loser = dayWorn.contains(a) ? b : (dayWorn.contains(b) ? a : (a.slot == .eyes ? b : a))
                look.takeOff(loser.slot)
            }
        }

        if detail == .compact {
            for slot in FlameySlot.allCases where !slot.survivesCompact { look.takeOff(slot) }
        }

        look.glow = glow(for: look)
        return look
    }

    private static func glow(for look: FlameyLook) -> FlameyGlow {
        let colorHalo = FlameyPalette.palette(for: look.color)?.hasHalo ?? false
        if let aura = look[.aura] { return .aura(aura) }
        if look.items.contains(where: { $0.skin?.ruleString("glow") == "wings" }) { return .wings }
        if colorHalo { return .colorHalo }
        return .none
    }

    // Codable by raw strings, dropping ids this build doesn't know, so a look
    // written by a newer build never fails to decode.
    private enum CodingKeys: String, CodingKey { case worn, holiday, isAnniversary, detail }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent([String: String].self, forKey: .worn) ?? [:]
        for (_, value) in raw {
            if let item = FlameyItem(rawValue: value) { worn[item.slot] = item }
        }
        if let rawHoliday = try? c.decodeIfPresent(String.self, forKey: .holiday) {
            holiday = HolidayKey(rawValue: rawHoliday)
        }
        if let flag = try? c.decodeIfPresent(Bool.self, forKey: .isAnniversary) {
            isAnniversary = flag
        }
        if let rawDetail = try? c.decodeIfPresent(String.self, forKey: .detail),
           let parsed = FlameyRenderDetail(rawValue: rawDetail) {
            detail = parsed
        }
        glow = Self.glow(for: self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        var raw: [String: String] = [:]
        for (slot, item) in worn { raw[slot.rawValue] = item.rawValue }
        try c.encode(raw, forKey: .worn)
        try c.encodeIfPresent(holiday?.rawValue, forKey: .holiday)
        try c.encode(isAnniversary, forKey: .isAnniversary)
        try c.encode(detail.rawValue, forKey: .detail)
    }
}
