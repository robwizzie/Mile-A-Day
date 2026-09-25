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
        case .color: return "Colour"
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
         buddyWalks, ghosts, stories, nudges, firsts, holidays, mood

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
        }
    }
}

// MARK: - Items

/// Everything he can wear. Raw values are the backend's catalog ids — STABLE,
/// stored in `users.flamey_look` and sent by shipped builds; never rename one.
/// The last three are MOOD dressing (automatic, never in the Closet, never on
/// the wire).
enum FlameyItem: String, CaseIterable, Codable, Hashable {
    // color
    case classic, ember, lime, ruby, lavender, sunflower, mint, sapphire, violet, rose, teal, arctic, midnight,
         sunset, aurora, ocean, lavaLamp = "lava_lamp", galaxy, candy, northernLights = "northern_lights",
         gold, prism, cosmic, eternal, phantom
    // head
    case sweatband, ballCap = "ball_cap", visor, beanie, bucketHat = "bucket_hat", safariHat = "safari_hat",
         cowboyHat = "cowboy_hat", aviatorCap = "aviator_cap", headlampHelmet = "headlamp_helmet", crown,
         laurelWreath = "laurel_wreath", vikingHelmet = "viking_helmet", directorsBeret = "directors_beret",
         santaHat = "santa_hat", heartBopper = "heart_bopper", leprechaunHat = "leprechaun_hat",
         bunnyEars = "bunny_ears", starHat = "star_hat", countdownHat = "countdown_hat"
    // eyes
    case starStickers = "star_stickers", roundSpecs = "round_specs", classicShades = "classic_shades",
         aviators, heartGlasses = "heart_glasses", cyberVisor = "cyber_visor", starGlasses = "star_glasses"
    // chest
    case bandana, bowTie = "bow_tie", finisherMedal = "finisher_medal", starBadge = "star_badge",
         championSash = "champion_sash", goldChain = "gold_chain", trophyPendant = "trophy_pendant",
         polaroid, holidayScarf = "holiday_scarf"
    // back
    case redCape = "red_cape", blueCape = "blue_cape", royalCape = "royal_cape", championCape = "champion_cape",
         victoryBanner = "victory_banner", goldenWings = "golden_wings", turkeyFeathers = "turkey_feathers"
    // feet
    case canvasSneakers = "canvas_sneakers", trainers, racingFlats = "racing_flats", neonSoles = "neon_soles",
         trackSpikes = "track_spikes", rocketBoots = "rocket_boots", lightningKicks = "lightning_kicks",
         wingedSandals = "winged_sandals"
    // costume
    case ghostSheet = "ghost_sheet", astronautHelmet = "astronaut_helmet", pumpkinSuit = "pumpkin_suit"
    // held
    case checkeredFlag = "checkered_flag", stopwatch, pomPoms = "pom_poms", foamFinger = "foam_finger",
         megaphone, confettiCannon = "confetti_cannon"
    // trail
    case emberSparks = "ember_sparks", dustPuffs = "dust_puffs", speedLines = "speed_lines", cometTail = "comet_tail",
         smokeRings = "smoke_rings", starTrail = "star_trail", rainbowStreak = "rainbow_streak",
         lightningTrail = "lightning_trail", fireworks, phoenixFeathers = "phoenix_feathers",
         auroraRibbon = "aurora_ribbon", meteorShower = "meteor_shower"
    // companion
    case spark, firefly, flameyJr = "flamey_jr", sparkTrio = "spark_trio", lantern, phoenixChick = "phoenix_chick",
         cometPup = "comet_pup", friendlyGhost = "friendly_ghost"
    // aura
    case spectralGlow = "spectral_glow", flicker, spotlight, paparazzi
    // bubble
    case classicBubble = "classic_bubble", comic, neon, pixel, goldBubble = "gold_bubble"
    // mood dressing — automatic, never listed, never sent
    case moodShades = "mood_shades", partyHat = "party_hat", nightcap

    /// Every Closet item, in catalog order (mood dressing excluded).
    static var closet: [FlameyItem] { allCases.filter { !$0.isMoodProp } }

    var isMoodProp: Bool { self == .moodShades || self == .partyHat || self == .nightcap }

    var slot: FlameySlot {
        switch self {
        case .classic, .ember, .lime, .ruby, .lavender, .sunflower, .mint, .sapphire, .violet, .rose, .teal,
             .arctic, .midnight, .sunset, .aurora, .ocean, .lavaLamp, .galaxy, .candy, .northernLights,
             .gold, .prism, .cosmic, .eternal, .phantom:
            return .color
        case .sweatband, .ballCap, .visor, .beanie, .bucketHat, .safariHat, .cowboyHat, .aviatorCap,
             .headlampHelmet, .crown, .laurelWreath, .vikingHelmet, .directorsBeret, .santaHat, .heartBopper,
             .leprechaunHat, .bunnyEars, .starHat, .countdownHat, .partyHat, .nightcap:
            return .head
        case .starStickers, .roundSpecs, .classicShades, .aviators, .heartGlasses, .cyberVisor, .starGlasses,
             .moodShades:
            return .eyes
        case .bandana, .bowTie, .finisherMedal, .starBadge, .championSash, .goldChain, .trophyPendant,
             .polaroid, .holidayScarf:
            return .chest
        case .redCape, .blueCape, .royalCape, .championCape, .victoryBanner, .goldenWings, .turkeyFeathers:
            return .back
        case .canvasSneakers, .trainers, .racingFlats, .neonSoles, .trackSpikes, .rocketBoots,
             .lightningKicks, .wingedSandals:
            return .feet
        case .ghostSheet, .astronautHelmet, .pumpkinSuit:
            return .costume
        case .checkeredFlag, .stopwatch, .pomPoms, .foamFinger, .megaphone, .confettiCannon:
            return .held
        case .emberSparks, .dustPuffs, .speedLines, .cometTail, .smokeRings, .starTrail, .rainbowStreak,
             .lightningTrail, .fireworks, .phoenixFeathers, .auroraRibbon, .meteorShower:
            return .trail
        case .spark, .firefly, .flameyJr, .sparkTrio, .lantern, .phoenixChick, .cometPup, .friendlyGhost:
            return .companion
        case .spectralGlow, .flicker, .spotlight, .paparazzi:
            return .aura
        case .classicBubble, .comic, .neon, .pixel, .goldBubble:
            return .bubble
        }
    }

    /// How it becomes his. Mirrors the backend catalog row for row.
    var unlock: FlameyUnlock {
        switch self {
        case .classic, .classicBubble, .moodShades, .partyHat, .nightcap: return .always
        case .ember: return .badge("consistency_3")
        case .lime: return .badge("consistency_5")
        case .ruby: return .badge("streak_7")
        case .lavender: return .badge("streak_10")
        case .sunflower: return .badge("streak_14")
        case .mint: return .badge("streak_21")
        case .sapphire: return .badge("streak_30")
        case .violet: return .badge("streak_45")
        case .rose: return .badge("streak_50")
        case .teal: return .badge("streak_60")
        case .arctic: return .badge("streak_75")
        case .midnight: return .badge("streak_90")
        case .sunset: return .badge("streak_100")
        case .aurora: return .badge("streak_120")
        case .ocean: return .badge("streak_150")
        case .lavaLamp: return .badge("streak_180")
        case .galaxy: return .badge("streak_200")
        case .candy: return .badge("streak_250")
        case .northernLights: return .badge("streak_300")
        case .gold: return .badge("streak_365")
        case .prism: return .badge("streak_500")
        case .cosmic: return .badge("streak_730")
        case .eternal: return .badge("streak_1000")
        case .phantom: return .badge("ghost_beat_50")
        case .sweatband: return .badge("special_first_mile")
        case .ballCap: return .badge("miles_25")
        case .visor: return .badge("miles_50")
        case .beanie: return .badge("miles_100")
        case .bucketHat: return .badge("miles_150")
        case .safariHat: return .badge("miles_200")
        case .cowboyHat: return .badge("miles_250")
        case .aviatorCap: return .badge("miles_500")
        case .headlampHelmet: return .badge("miles_750")
        case .crown: return .badge("miles_1000")
        case .laurelWreath: return .badge("miles_1500")
        case .vikingHelmet: return .badge("miles_2000")
        case .directorsBeret: return .badge("story_5")
        case .santaHat: return .badge(HolidayKey.christmas.badgeId)
        case .heartBopper: return .badge(HolidayKey.valentinesDay.badgeId)
        case .leprechaunHat: return .badge(HolidayKey.stPatricksDay.badgeId)
        case .bunnyEars: return .badge(HolidayKey.easter.badgeId)
        case .starHat: return .badge(HolidayKey.independenceDay.badgeId)
        case .countdownHat: return .badge(HolidayKey.newYearsEve.badgeId)
        case .starStickers: return .badge("challenge_1")
        case .roundSpecs: return .badge("challenge_5")
        case .classicShades: return .badge("challenge_10")
        case .aviators: return .badge("challenge_25")
        case .heartGlasses: return .badge("challenge_50")
        case .cyberVisor: return .badge("challenge_100")
        case .starGlasses: return .badge(HolidayKey.newYearsDay.badgeId)
        case .bandana: return .badge("special_first_week")
        case .bowTie: return .badge("weekly_1")
        case .finisherMedal: return .badge("weekly_5")
        case .starBadge: return .badge("weekly_10")
        case .championSash: return .badge("weekly_25")
        case .goldChain: return .badge("weekly_streak_4")
        case .trophyPendant: return .badge("weekly_streak_12")
        case .polaroid: return .badge("story_1")
        case .holidayScarf: return .badge(HolidayKey.christmasEve.badgeId)
        case .redCape: return .badge("comp_entered_1")
        case .blueCape: return .badge("comp_entered_10")
        case .royalCape: return .badge("comp_entered_50")
        case .championCape: return .badge("comp_won_1")
        case .victoryBanner: return .badge("comp_won_5")
        case .goldenWings: return .badge("comp_won_25")
        case .turkeyFeathers: return .badge(HolidayKey.thanksgiving.badgeId)
        case .canvasSneakers: return .badge("pace_12min")
        case .trainers: return .badge("pace_11min")
        case .racingFlats: return .badge("pace_10min")
        case .neonSoles: return .badge("pace_9min")
        case .trackSpikes: return .badge("pace_8min")
        case .rocketBoots: return .badge("pace_7min")
        case .lightningKicks: return .badge("pace_6min")
        case .wingedSandals: return .badge("pace_5min")
        case .ghostSheet: return .badge("ghost_beat_10")
        case .astronautHelmet: return .badge("miles_2500")
        case .pumpkinSuit: return .badge(HolidayKey.halloween.badgeId)
        case .checkeredFlag: return .badge("comp_started_1")
        case .stopwatch: return .badge("comp_started_10")
        case .pomPoms: return .badge("hype_1")
        case .foamFinger: return .badge("hype_25")
        case .megaphone: return .badge("hype_100")
        case .confettiCannon: return .badge("hype_500")
        case .emberSparks: return .badge("daily_2")
        case .dustPuffs: return .badge("daily_3")
        case .speedLines: return .badge("daily_5")
        case .cometTail: return .badge("daily_10k")
        case .smokeRings: return .badge("daily_8")
        case .starTrail: return .badge("daily_10")
        case .rainbowStreak: return .badge("daily_half")
        case .lightningTrail: return .badge("daily_15")
        case .fireworks: return .badge("daily_20")
        case .phoenixFeathers: return .badge("daily_marathon")
        case .auroraRibbon: return .badge("daily_50k")
        case .meteorShower: return .badge("daily_ultra")
        case .spark: return .badge("buddy_done_1")
        case .firefly: return .badge("buddy_done_10")
        case .flameyJr: return .badge("buddy_done_50")
        case .sparkTrio: return .badge("buddy_crew_3")
        case .lantern: return .badge("buddy_crew_10")
        case .phoenixChick: return .badge("buddy_won_1")
        case .cometPup: return .badge("buddy_won_10")
        case .friendlyGhost: return .badge("ghost_beat_1")
        case .spectralGlow: return .badge("ghost_margin_15")
        case .flicker: return .badge("ghost_margin_45")
        case .spotlight: return .badge("story_25")
        case .paparazzi: return .badge("story_100")
        case .comic: return .badge("nudge_1")
        case .neon: return .badge("nudge_25")
        case .pixel: return .badge("nudge_100")
        case .goldBubble: return .badge("nudge_500")
        }
    }

    var badgeId: String? {
        if case .badge(let id) = unlock { return id }
        return nil
    }

    /// The holiday this item is the outfit for — worn automatically on the
    /// day, owned or not. The scarf covers both Christmas Eve and Day.
    var holidays: [HolidayKey] {
        switch self {
        case .countdownHat: return [.newYearsEve]
        case .starGlasses: return [.newYearsDay]
        case .heartBopper: return [.valentinesDay]
        case .leprechaunHat: return [.stPatricksDay]
        case .bunnyEars: return [.easter]
        case .starHat: return [.independenceDay]
        case .pumpkinSuit: return [.halloween]
        case .turkeyFeathers: return [.thanksgiving]
        case .holidayScarf: return [.christmasEve, .christmas]
        case .santaHat: return [.christmas]
        default: return []
        }
    }

    var isHolidayOutfit: Bool { !holidays.isEmpty }

    /// Picked by the Closet's "Best look" action when owned. Holiday outfits
    /// are the calendar's to put on, costumes hide everything else, and
    /// Phantom is a spooky special rather than a rung on the streak ladder —
    /// all three only ever go on because you (or the day) chose them.
    var autoEligible: Bool {
        if isMoodProp || isHolidayOutfit { return false }
        switch slot {
        case .costume: return false
        default: return self != .phantom
        }
    }

    /// Order WITHIN a slot ("Best look" takes the highest owned). It is the
    /// difficulty of the medal behind it, so across families in one slot
    /// (a beret from five stories vs a beanie from 100 miles) the harder one
    /// wins.
    var tier: Int {
        switch self {
        // color — the streak ladder
        case .classic: return 0
        case .ember: return 3
        case .lime: return 5
        case .ruby: return 7
        case .lavender: return 10
        case .sunflower: return 14
        case .mint: return 21
        case .sapphire: return 30
        case .violet: return 45
        case .rose: return 50
        case .teal: return 60
        case .arctic: return 75
        case .midnight: return 90
        case .sunset: return 100
        case .aurora: return 120
        case .ocean: return 150
        case .lavaLamp: return 180
        case .galaxy: return 200
        case .candy: return 250
        case .northernLights: return 300
        case .gold: return 365
        case .prism: return 500
        case .cosmic: return 730
        case .eternal: return 1000
        case .phantom: return 95
        // head
        case .sweatband: return 1
        case .ballCap: return 10
        case .visor: return 20
        case .directorsBeret: return 25
        case .beanie: return 30
        case .bucketHat: return 40
        case .safariHat: return 50
        case .cowboyHat: return 60
        case .aviatorCap: return 70
        case .headlampHelmet: return 80
        case .crown: return 90
        case .laurelWreath: return 100
        case .vikingHelmet: return 110
        case .santaHat, .heartBopper, .leprechaunHat, .bunnyEars, .starHat, .countdownHat: return 5
        case .partyHat, .nightcap: return 0
        // eyes
        case .starStickers: return 10
        case .roundSpecs: return 20
        case .classicShades: return 30
        case .aviators: return 40
        case .heartGlasses: return 50
        case .cyberVisor: return 60
        case .starGlasses: return 5
        case .moodShades: return 0
        // chest
        case .bandana: return 5
        case .bowTie: return 10
        case .polaroid: return 12
        case .finisherMedal: return 20
        case .starBadge: return 30
        case .championSash: return 40
        case .goldChain: return 50
        case .trophyPendant: return 60
        case .holidayScarf: return 3
        // back
        case .redCape: return 10
        case .blueCape: return 20
        case .royalCape: return 30
        case .championCape: return 40
        case .victoryBanner: return 50
        case .goldenWings: return 60
        case .turkeyFeathers: return 3
        // feet — a FASTER mile is a higher rung
        case .canvasSneakers: return 10
        case .trainers: return 20
        case .racingFlats: return 30
        case .neonSoles: return 40
        case .trackSpikes: return 50
        case .rocketBoots: return 60
        case .lightningKicks: return 70
        case .wingedSandals: return 80
        // costume
        case .ghostSheet: return 10
        case .astronautHelmet: return 20
        case .pumpkinSuit: return 5
        // held
        case .pomPoms: return 10
        case .checkeredFlag: return 12
        case .foamFinger: return 20
        case .stopwatch: return 25
        case .megaphone: return 40
        case .confettiCannon: return 50
        // trail
        case .emberSparks: return 10
        case .dustPuffs: return 20
        case .speedLines: return 30
        case .cometTail: return 40
        case .smokeRings: return 50
        case .starTrail: return 60
        case .rainbowStreak: return 70
        case .lightningTrail: return 80
        case .fireworks: return 90
        case .phoenixFeathers: return 100
        case .auroraRibbon: return 110
        case .meteorShower: return 120
        // companion
        case .spark: return 10
        case .friendlyGhost: return 15
        case .firefly: return 20
        case .sparkTrio: return 25
        case .phoenixChick: return 30
        case .lantern: return 45
        case .flameyJr: return 50
        case .cometPup: return 60
        // aura
        case .spectralGlow: return 10
        case .spotlight: return 15
        case .flicker: return 20
        case .paparazzi: return 30
        // bubble
        case .classicBubble: return 0
        case .comic: return 10
        case .neon: return 20
        case .pixel: return 30
        case .goldBubble: return 40
        }
    }

    /// Slots this item covers up. A costume is worn INSTEAD of what it hides
    /// — the resolver takes those slots off, so the Closet can say so and a
    /// hat never pokes through a sheet. Checked with a resolve × render
    /// matrix, not by eye.
    var hides: Set<FlameySlot> {
        switch self {
        // Head to toe: its own eye holes, nothing above, round or under it.
        case .ghostSheet: return [.head, .eyes, .chest, .feet, .back, .held]
        // A fishbowl: no hat fits inside, and the collar sits on his chest.
        case .astronautHelmet: return [.head, .chest]
        // Sat in a pumpkin: its stem is his hat, it swallows his feet, his
        // middle and the arm a held item needs.
        case .pumpkinSuit: return [.head, .chest, .feet, .held]
        default: return []
        }
    }

    /// Holiday-specific clashes that aren't a whole slot: the star glasses'
    /// top points reach the brow line, so the sweatband comes off rather
    /// than poking through them.
    func clashes(with other: FlameyItem) -> Bool {
        (self == .starGlasses && other == .sweatband) || (self == .sweatband && other == .starGlasses)
    }

    /// Lifts him off the ground (a fraction of his body unit) on a full
    /// surface: the rocket jets and the winged hover. Suppressed on compact
    /// surfaces, where he stands on the ground like everyone else.
    var hoverLift: CGFloat {
        switch self {
        case .rocketBoots: return 0.13
        case .wingedSandals: return 0.08
        default: return 0
        }
    }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .ember: return "Ember"
        case .lime: return "Lime"
        case .ruby: return "Ruby"
        case .lavender: return "Lavender"
        case .sunflower: return "Sunflower"
        case .mint: return "Mint"
        case .sapphire: return "Sapphire"
        case .violet: return "Violet"
        case .rose: return "Rose"
        case .teal: return "Teal"
        case .arctic: return "Arctic"
        case .midnight: return "Midnight"
        case .sunset: return "Sunset"
        case .aurora: return "Aurora"
        case .ocean: return "Ocean"
        case .lavaLamp: return "Lava Lamp"
        case .galaxy: return "Galaxy"
        case .candy: return "Candy"
        case .northernLights: return "Northern Lights"
        case .gold: return "Gold"
        case .prism: return "Prism"
        case .cosmic: return "Cosmic"
        case .eternal: return "Eternal"
        case .phantom: return "Phantom"
        case .sweatband: return "Sweatband"
        case .ballCap: return "Ball Cap"
        case .visor: return "Visor"
        case .beanie: return "Beanie"
        case .bucketHat: return "Bucket Hat"
        case .safariHat: return "Safari Hat"
        case .cowboyHat: return "Cowboy Hat"
        case .aviatorCap: return "Aviator Cap"
        case .headlampHelmet: return "Headlamp Helmet"
        case .crown: return "Crown"
        case .laurelWreath: return "Laurel Wreath"
        case .vikingHelmet: return "Viking Helmet"
        case .directorsBeret: return "Director's Beret"
        case .santaHat: return "Santa Hat"
        case .heartBopper: return "Heart Bopper"
        case .leprechaunHat: return "Lucky Hat"
        case .bunnyEars: return "Bunny Ears"
        case .starHat: return "Star Hat"
        case .countdownHat: return "Countdown Hat"
        case .starStickers: return "Star Stickers"
        case .roundSpecs: return "Round Specs"
        case .classicShades: return "Classic Shades"
        case .aviators: return "Aviators"
        case .heartGlasses: return "Heart Glasses"
        case .cyberVisor: return "Cyber Visor"
        case .starGlasses: return "Star Glasses"
        case .bandana: return "Bandana"
        case .bowTie: return "Bow Tie"
        case .finisherMedal: return "Finisher Medal"
        case .starBadge: return "Star Badge"
        case .championSash: return "Champion Sash"
        case .goldChain: return "Gold Chain"
        case .trophyPendant: return "Trophy Pendant"
        case .polaroid: return "Polaroid"
        case .holidayScarf: return "Cozy Scarf"
        case .redCape: return "Red Cape"
        case .blueCape: return "Blue Cape"
        case .royalCape: return "Royal Cape"
        case .championCape: return "Champion Cape"
        case .victoryBanner: return "Victory Banner"
        case .goldenWings: return "Golden Wings"
        case .turkeyFeathers: return "Tail Feathers"
        case .canvasSneakers: return "Canvas Sneakers"
        case .trainers: return "Trainers"
        case .racingFlats: return "Racing Flats"
        case .neonSoles: return "Neon Soles"
        case .trackSpikes: return "Track Spikes"
        case .rocketBoots: return "Rocket Boots"
        case .lightningKicks: return "Lightning Kicks"
        case .wingedSandals: return "Winged Sandals"
        case .ghostSheet: return "Ghost Sheet"
        case .astronautHelmet: return "Astronaut Helmet"
        case .pumpkinSuit: return "Pumpkin Suit"
        case .checkeredFlag: return "Checkered Flag"
        case .stopwatch: return "Stopwatch"
        case .pomPoms: return "Pom-Poms"
        case .foamFinger: return "Foam Finger"
        case .megaphone: return "Megaphone"
        case .confettiCannon: return "Confetti Cannon"
        case .emberSparks: return "Ember Sparks"
        case .dustPuffs: return "Dust Puffs"
        case .speedLines: return "Speed Lines"
        case .cometTail: return "Comet Tail"
        case .smokeRings: return "Smoke Rings"
        case .starTrail: return "Star Trail"
        case .rainbowStreak: return "Rainbow Streak"
        case .lightningTrail: return "Lightning Trail"
        case .fireworks: return "Fireworks"
        case .phoenixFeathers: return "Phoenix Feathers"
        case .auroraRibbon: return "Aurora Ribbon"
        case .meteorShower: return "Meteor Shower"
        case .spark: return "Spark"
        case .firefly: return "Ember Dragon"
        case .flameyJr: return "Flamey Jr."
        case .sparkTrio: return "Spark Trio"
        case .lantern: return "Lantern"
        case .phoenixChick: return "Blaze Fox"
        case .cometPup: return "Comet Pup"
        case .friendlyGhost: return "Friendly Ghost"
        case .spectralGlow: return "Spectral Glow"
        case .flicker: return "Flicker"
        case .spotlight: return "Spotlight"
        case .paparazzi: return "Paparazzi"
        case .classicBubble: return "Classic"
        case .comic: return "Comic"
        case .neon: return "Neon"
        case .pixel: return "Pixel"
        case .goldBubble: return "Gold"
        case .moodShades: return "Shades"
        case .partyHat: return "Party Hat"
        case .nightcap: return "Nightcap"
        }
    }

    var family: FlameyFamily {
        if isMoodProp { return .mood }
        if isHolidayOutfit { return .holidays }
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

    /// "Run a sub-7 mile" — the how-to-unlock line, written from the medal.
    var unlockCopy: String {
        if isMoodProp { return "Worn with his mood" }
        switch unlock {
        case .always: return "Always his"
        case .purchase: return "In the shop"
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
    /// Reserved for a purchasable item (StoreKit product id). Nothing uses it
    /// yet; owned by nobody until a purchase ledger exists.
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
            case .purchase, .streak: return false
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
        if look.wears(.goldenWings) { return .wings }
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
