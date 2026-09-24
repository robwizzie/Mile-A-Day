import SwiftUI

// FLAMEY'S WARDROBE — what he can wear, when he wears it, and how it's drawn.
//
// THIS FILE EXISTS TWICE, BYTE-IDENTICAL:
//   app/Mile A Day/Views/Components/FlameyWardrobe.swift   (the app)
//   app/MileADayWidgets/FlameyWardrobe.swift                (widget extension)
// The widget extension can't see the app's files and new files can't be added
// to its target from here except in its own synchronized folder, so the ONE
// description of his look is compiled twice. Edit one, then `cp` it over the
// other — `cmp` the pair before committing. Nothing in here may depend on
// anything outside SwiftUI/Foundation (no MADTheme, no UserDefaults, no app
// models): it is the shared contract, and every renderer — the Fun hero, the
// flame widget, the Flamey share cards, and next a friend's profile, the
// tracker and the Live Activity — draws from `FlameyLook` alone.
//
// Three ideas, kept separate on purpose:
//   - OWNING an item (`FlameyUnlock`) is DERIVED from durable facts — the
//     longest streak, earned badges. Nothing about ownership is stored, so no
//     style switch, reinstall or sign-out can take anything away.
//   - WEARING an item on a given day (`FlameySeason`) is a calendar fact: the
//     holiday outfits go on automatically ON the day, owned or not.
//   - The resolved `FlameyLook` is a pure value: slot → item, one item per
//     slot, so he can never wear two hats.

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

// MARK: - Slots and items

/// Where on him an item goes. ONE item per slot — that is the whole of the
/// "never two hats" rule. Declared in DRAW order.
enum FlameySlot: String, CaseIterable, Codable, Hashable {
    /// Behind the body (turkey tail feathers).
    case back
    case feet
    case neck
    /// Over the lower body — a whole-outfit piece (the pumpkin).
    case costume
    case cheeks
    case brow
    case face
    /// Every hat, crown and pair of ears.
    case head

    var drawsBehindBody: Bool { self == .back }
}

/// Everything he can wear. Raw values are STABLE ids (they will be stored by
/// the wardrobe and may travel to a server); never rename one.
enum FlameyItem: String, CaseIterable, Codable, Hashable {
    // Mood props — always his, worn by how the day is going.
    case shades
    case partyHat = "party_hat"
    case nightcap
    // Streak gear — owned for good once the LONGEST streak reaches it.
    case bandana
    case sweatband
    case sneakers
    case crown
    // Holiday outfits — worn on the day; owned via that holiday's medal.
    case pumpkinSuit = "pumpkin_suit"
    case santaHat = "santa_hat"
    case holidayScarf = "holiday_scarf"
    case starGlasses = "star_glasses"
    case heartBopper = "heart_bopper"
    case blush
    case leprechaunHat = "leprechaun_hat"
    case bunnyEars = "bunny_ears"
    case starHat = "star_hat"
    case turkeyFeathers = "turkey_feathers"
    case countdownHat = "countdown_hat"

    var slot: FlameySlot {
        switch self {
        case .shades, .starGlasses: return .face
        case .partyHat, .nightcap, .crown, .santaHat, .heartBopper, .leprechaunHat,
             .bunnyEars, .starHat, .countdownHat:
            return .head
        case .bandana, .holidayScarf: return .neck
        case .sweatband: return .brow
        case .sneakers: return .feet
        case .pumpkinSuit: return .costume
        case .blush: return .cheeks
        case .turkeyFeathers: return .back
        }
    }

    /// Slots this item covers up. The pumpkin is a whole outfit — its stem is
    /// his hat, and it swallows his feet and anything round his middle — and
    /// a costume is worn INSTEAD of gear, so the 30-day sweatband comes off
    /// with it (it drew as a gym band over a pumpkin). The star glasses' top
    /// points reach the brow line, so they take the sweatband off too rather
    /// than poking through it. Checked against every holiday × gear × mood
    /// combination a resolve can produce (render matrix, not by eye).
    var hides: Set<FlameySlot> {
        switch self {
        case .pumpkinSuit: return [.feet, .neck, .head, .brow]
        case .starGlasses: return [.brow]
        default: return []
        }
    }
}

/// How an item becomes his for good. Derived, never stored.
enum FlameyUnlock: Hashable {
    /// Always his (the mood props).
    case always
    /// His once the LONGEST streak reaches this many days — never the current
    /// one, so a broken streak can't take the crown back.
    case streak(Int)
    /// His once this badge is earned (`holiday_<key>` for holiday outfits).
    case badge(String)
    /// Reserved for a purchasable item (StoreKit product id). Nothing uses it
    /// yet; it is here so the wardrobe can list priced items without a model
    /// change.
    case purchase(productId: String)
}

/// When an item goes on BY ITSELF, owned or not.
enum FlameySeason: Hashable {
    /// On the holiday's local calendar day.
    case holidayDay(HolidayKey)
    /// For a whole month (1-12) — the Santa hat is all December.
    case month(Int)
    /// On the anniversary of the day he met you.
    case signupAnniversary

    /// Higher wins when two seasons want the same slot: the exact day beats
    /// the anniversary beats the month (Christmas Day's outfit over December's,
    /// a mid-December anniversary's party hat over the Santa hat).
    var rank: Int {
        switch self {
        case .month: return 1
        case .signupAnniversary: return 2
        case .holidayDay: return 3
        }
    }
}

/// A catalog entry: an item plus its name, how it's owned and when it's worn.
struct FlameyCosmetic: Identifiable, Hashable {
    let item: FlameyItem
    let name: String
    let unlock: FlameyUnlock
    var seasons: [FlameySeason] = []

    var id: String { item.rawValue }
    var slot: FlameySlot { item.slot }

    func isUnlocked(longestStreak: Int, earnedBadgeIds: Set<String>) -> Bool {
        switch unlock {
        case .always: return true
        case .streak(let days): return longestStreak >= days
        case .badge(let id): return earnedBadgeIds.contains(id)
        case .purchase: return false
        }
    }

    /// The whole wardrobe, in display order.
    static let catalog: [FlameyCosmetic] = [
        // Mood props
        FlameyCosmetic(item: .shades, name: "Shades", unlock: .always),
        FlameyCosmetic(item: .partyHat, name: "Party Hat", unlock: .always, seasons: [.signupAnniversary]),
        FlameyCosmetic(item: .nightcap, name: "Nightcap", unlock: .always),
        // Streak gear — the ladder
        FlameyCosmetic(item: .bandana, name: "Lucky Bandana", unlock: .streak(7)),
        FlameyCosmetic(item: .sweatband, name: "Sweatband", unlock: .streak(30)),
        FlameyCosmetic(item: .sneakers, name: "Sneakers", unlock: .streak(100)),
        FlameyCosmetic(item: .crown, name: "Crown", unlock: .streak(365)),
        // Holiday outfits — each owned via that holiday's medal
        FlameyCosmetic(item: .countdownHat, name: "Countdown Hat",
                       unlock: .badge(HolidayKey.newYearsEve.badgeId), seasons: [.holidayDay(.newYearsEve)]),
        FlameyCosmetic(item: .starGlasses, name: "Star Glasses",
                       unlock: .badge(HolidayKey.newYearsDay.badgeId), seasons: [.holidayDay(.newYearsDay)]),
        FlameyCosmetic(item: .heartBopper, name: "Heart Bopper",
                       unlock: .badge(HolidayKey.valentinesDay.badgeId), seasons: [.holidayDay(.valentinesDay)]),
        FlameyCosmetic(item: .blush, name: "Rosy Cheeks",
                       unlock: .badge(HolidayKey.valentinesDay.badgeId), seasons: [.holidayDay(.valentinesDay)]),
        FlameyCosmetic(item: .leprechaunHat, name: "Lucky Hat",
                       unlock: .badge(HolidayKey.stPatricksDay.badgeId), seasons: [.holidayDay(.stPatricksDay)]),
        FlameyCosmetic(item: .bunnyEars, name: "Bunny Ears",
                       unlock: .badge(HolidayKey.easter.badgeId), seasons: [.holidayDay(.easter)]),
        FlameyCosmetic(item: .starHat, name: "Star Hat",
                       unlock: .badge(HolidayKey.independenceDay.badgeId), seasons: [.holidayDay(.independenceDay)]),
        FlameyCosmetic(item: .pumpkinSuit, name: "Pumpkin Suit",
                       unlock: .badge(HolidayKey.halloween.badgeId), seasons: [.holidayDay(.halloween)]),
        FlameyCosmetic(item: .turkeyFeathers, name: "Tail Feathers",
                       unlock: .badge(HolidayKey.thanksgiving.badgeId), seasons: [.holidayDay(.thanksgiving)]),
        FlameyCosmetic(item: .holidayScarf, name: "Cozy Scarf",
                       unlock: .badge(HolidayKey.christmasEve.badgeId),
                       seasons: [.holidayDay(.christmasEve), .holidayDay(.christmas)]),
        FlameyCosmetic(item: .santaHat, name: "Santa Hat",
                       unlock: .badge(HolidayKey.christmas.badgeId), seasons: [.month(12)]),
    ]

    static func cosmetic(for item: FlameyItem) -> FlameyCosmetic? {
        catalog.first { $0.item == item }
    }

    /// Everything owned — what the wardrobe will list.
    static func unlocked(longestStreak: Int, earnedBadgeIds: Set<String>) -> [FlameyCosmetic] {
        catalog.filter { $0.isUnlocked(longestStreak: longestStreak, earnedBadgeIds: earnedBadgeIds) }
    }
}

// MARK: - The look

/// What Flamey is wearing — the ONE description every renderer draws. A pure
/// value: resolve it once, pass it everywhere.
struct FlameyLook: Equatable, Hashable, Codable {
    private(set) var worn: [FlameySlot: FlameyItem] = [:]
    /// Today's holiday, if any — for copy ("Boo!"), not drawing.
    var holiday: HolidayKey? = nil
    /// The anniversary of the day he met you.
    var isAnniversary: Bool = false

    static let plain = FlameyLook()

    var isPlain: Bool { worn.isEmpty }

    subscript(slot: FlameySlot) -> FlameyItem? { worn[slot] }

    /// Everything worn, in draw order.
    var items: [FlameyItem] { FlameySlot.allCases.compactMap { worn[$0] } }

    func wears(_ item: FlameyItem) -> Bool { worn[item.slot] == item }

    /// Puts `item` in its slot, replacing whatever was there.
    mutating func wear(_ item: FlameyItem) { worn[item.slot] = item }

    mutating func takeOff(_ slot: FlameySlot) { worn[slot] = nil }

    /// Resolves the look for a day. Every layer REPLACES the one below it,
    /// slot by slot, so there is never more than one item per slot:
    ///
    ///   1. streak gear — the best rung the LONGEST streak reached, per slot
    ///   2. `equipped`  — the wardrobe's manual picks (owned items only; the
    ///                    next phase — pass [:] until then)
    ///   3. `moodProps` — the day's mood (shades when done, party hat on a
    ///                    milestone, nightcap at bedtime)
    ///   4. seasons     — month < anniversary < the holiday itself
    ///
    /// then anything a worn item `hides` comes off. Mood-free callers (the
    /// widget) pass no `moodProps` and get gear + today's outfit.
    static func resolve(
        longestStreak: Int,
        earnedBadgeIds: Set<String>,
        signupDate: Date?,
        date: Date = Date(),
        moodProps: [FlameyItem] = [],
        equipped: [FlameySlot: FlameyItem] = [:],
        timeZone: TimeZone = .current
    ) -> FlameyLook {
        var look = FlameyLook()
        let holiday = HolidayCalendar.holiday(on: date, timeZone: timeZone)
        let anniversary = signupDate.map {
            HolidayCalendar.isAnniversary(of: $0, on: date, timeZone: timeZone)
        } ?? false
        look.holiday = holiday
        look.isAnniversary = anniversary

        // 1. Streak gear: the highest rung per slot.
        var bestRung: [FlameySlot: Int] = [:]
        for cosmetic in FlameyCosmetic.catalog {
            guard case .streak(let days) = cosmetic.unlock, longestStreak >= days else { continue }
            if days > bestRung[cosmetic.slot, default: -1] {
                bestRung[cosmetic.slot] = days
                look.wear(cosmetic.item)
            }
        }

        // 2. Manual picks — only what is actually owned.
        for (_, item) in equipped.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            guard let cosmetic = FlameyCosmetic.cosmetic(for: item),
                  cosmetic.isUnlocked(longestStreak: longestStreak, earnedBadgeIds: earnedBadgeIds)
            else { continue }
            look.wear(item)
        }

        // 3. The mood's props.
        for item in moodProps { look.wear(item) }

        // 4. Seasons, lowest rank first so the day itself lands last.
        let month = HolidayCalendar.components(of: date, timeZone: timeZone).month
        let seasonal: [(rank: Int, item: FlameyItem)] = FlameyCosmetic.catalog.compactMap { cosmetic in
            let live = cosmetic.seasons.filter { season in
                switch season {
                case .holidayDay(let key): return key == holiday
                case .month(let m): return m == month
                case .signupAnniversary: return anniversary
                }
            }
            guard let best = live.map(\.rank).max() else { return nil }
            return (best, cosmetic.item)
        }
        for entry in seasonal.sorted(by: { $0.rank < $1.rank }) { look.wear(entry.item) }

        // Finally, what the outfit covers up.
        let hidden = look.items.reduce(into: Set<FlameySlot>()) { $0.formUnion($1.hides) }
        for slot in hidden { look.takeOff(slot) }
        return look
    }

    // Codable by raw strings, dropping ids this build doesn't know, so a look
    // written by a newer build (or a server) never fails to decode.
    private enum CodingKeys: String, CodingKey { case worn, holiday, isAnniversary }

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
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        var raw: [String: String] = [:]
        for (slot, item) in worn { raw[slot.rawValue] = item.rawValue }
        try c.encode(raw, forKey: .worn)
        try c.encodeIfPresent(holiday?.rawValue, forKey: .holiday)
        try c.encode(isAnniversary, forKey: .isAnniversary)
    }
}

// MARK: - Drawing

/// Draws a `FlameyLook` on the figure, in `FlameBuddyFigure`'s own geometry:
/// the figure fills a `size` square, his body is scaled by `scale` about the
/// bottom edge, the face sits 0.32·size·scale above the bottom, the eyes
/// ±0.145·size·scale either side, the tip 0.98·size·scale up. Every prop is
/// placed from those, so gear stays on him as he burns down through the day.
///
/// ONE layer draws one side of him: `.behind` goes before the figure in the
/// caller's ZStack (tail feathers), `.front` after it. Drawn with `Canvas` —
/// no per-frame work: the only motion is the heart bopper's sway, a
/// `repeatForever` transform started once, and none at all when `still`.
///
/// Reports a `size × size` layout footprint (the drawing overflows it, like
/// the figure's glow), so adding it to a ZStack never moves anything.
struct FlameyOutfitLayer: View {
    enum Side { case behind, front }

    let look: FlameyLook
    let size: CGFloat
    /// The body scale the figure is drawn at right now.
    var scale: CGFloat = 1
    var side: Side = .front
    /// A still frame: share cards, widgets, Reduce Motion.
    var still: Bool = false

    @State private var sway = false

    private var drawn: [FlameyItem] {
        look.items.filter { ($0.slot.drawsBehindBody) == (side == .behind) }
    }

    var body: some View {
        let items = drawn
        let size = self.size
        let scale = self.scale
        ZStack {
            if !items.isEmpty {
                let staticItems = items.filter { $0 != .heartBopper }
                Canvas { context, canvas in
                    context.translateBy(x: canvas.width / 2, y: canvas.height / 2)
                    for item in staticItems {
                        FlameyArt.draw(item, in: &context, size: size, scale: scale)
                    }
                }
                .frame(width: size * 2.4, height: size * 2.4)
                if items.contains(.heartBopper) {
                    heartBopper
                }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { startSway() }
        .onChange(of: look) { _, _ in startSway() }
    }

    /// Idempotent: re-assigning an already-true phase is a no-op, so a
    /// re-fired appear can't stack a second repeat.
    private func startSway() {
        guard !still, drawn.contains(.heartBopper), !sway else { return }
        // Off the appear commit — a repeatForever started inside onAppear
        // attaches to the view's first transaction (see FlameBuddyView).
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { sway = true }
        }
    }

    /// Valentine's bopper sways from its base on the tip.
    private var heartBopper: some View {
        let size = self.size
        let scale = self.scale
        let base = FlameyArt.anchors(size: size, scale: scale)
        return Canvas { context, canvas in
            context.translateBy(x: canvas.width / 2, y: canvas.height / 2)
            FlameyArt.drawHeartBopper(in: &context, u: size * scale)
        }
        .frame(width: size * scale * 0.5, height: size * scale * 0.5)
        .rotationEffect(.degrees(still ? 0 : (sway ? 7 : -7)), anchor: .center)
        .offset(y: base.topY + 0.03 * size * scale)
    }
}

/// The prop drawings. Coordinates are offsets from the centre of the figure's
/// `size` square (SwiftUI's frame centre), in points — the same space the
/// mood props use — so a Canvas translated to its centre draws them 1:1.
/// `u` = size × scale, the unit every prop is measured in so it scales with
/// him.
enum FlameyArt {
    struct Anchors {
        let bottom: CGFloat
        let faceY: CGFloat
        let eyeX: CGFloat
        let topY: CGFloat
    }

    static func anchors(size: CGFloat, scale: CGFloat) -> Anchors {
        Anchors(bottom: size / 2,
                faceY: size / 2 - 0.32 * size * scale,
                eyeX: 0.145 * size * scale,
                topY: size / 2 - 0.98 * size * scale)
    }

    static func draw(_ item: FlameyItem, in ctx: inout GraphicsContext, size s: CGFloat, scale k: CGFloat) {
        let a = anchors(size: s, scale: k)
        let u = s * k
        switch item {
        case .shades: shades(&ctx, a, u, s)
        case .partyHat: partyHat(&ctx, a, u)
        case .nightcap: nightcap(&ctx, a, u)
        case .bandana: bandana(&ctx, a, u)
        case .sweatband: sweatband(&ctx, a, u)
        case .sneakers: sneakers(&ctx, a, u)
        case .crown: crown(&ctx, a, u, s)
        case .pumpkinSuit: pumpkin(&ctx, a, u)
        case .santaHat: santaHat(&ctx, a, u)
        case .holidayScarf: scarf(&ctx, a, u)
        case .starGlasses: starGlasses(&ctx, a, u)
        case .heartBopper:
            var sub = ctx
            sub.translateBy(x: 0, y: a.topY + 0.03 * u)
            drawHeartBopper(in: &sub, u: u)
        case .blush: blush(&ctx, a, u)
        case .leprechaunHat: leprechaunHat(&ctx, a, u)
        case .bunnyEars: bunnyEars(&ctx, a, u)
        case .starHat: starHat(&ctx, a, u)
        case .turkeyFeathers: turkeyFeathers(&ctx, a, u)
        case .countdownHat: countdownHat(&ctx, a, u)
        }
    }

    // MARK: Helpers

    private static func rgb(_ hex: UInt32, _ opacity: Double = 1) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255).opacity(opacity)
    }

    /// A sub-context moved to (x, y) and turned by `degrees` — SVG's
    /// `translate(x,y) rotate(r)`.
    private static func placed(_ ctx: GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ degrees: Double = 0) -> GraphicsContext {
        var sub = ctx
        sub.translateBy(x: x, y: y)
        if degrees != 0 { sub.rotate(by: .degrees(degrees)) }
        return sub
    }

    private static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    private static func ellipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2))
    }

    private static func star(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, inner: CGFloat = 0.45) -> Path {
        var p = Path()
        for i in 0..<10 {
            let rr = i % 2 == 1 ? r * inner : r
            let angle = -Double.pi / 2 + Double(i) * Double.pi / 5
            let pt = CGPoint(x: cx + rr * CGFloat(cos(angle)), y: cy + rr * CGFloat(sin(angle)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    private static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    // MARK: Mood props

    /// Mile banked: the mood layer's shades, ported 1:1.
    private static func shades(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat, _ s: CGFloat) {
        let g = placed(ctx, 0, a.faceY - 0.005 * u)
        let lw = 0.20 * u, lh = 0.185 * u
        let frame = Color(red: 0.18, green: 0.16, blue: 0.20)
        for side in [-1.0, 1.0] as [CGFloat] {
            let rect = CGRect(x: side * a.eyeX - lw / 2, y: -lh / 2, width: lw, height: lh)
            let lens = Path(roundedRect: rect, cornerRadius: lh * 0.45, style: .continuous)
            g.fill(lens, with: .color(Color(red: 0.08, green: 0.07, blue: 0.10)))
            g.fill(lens, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.28), .clear]),
                                               startPoint: rect.origin, endPoint: pt(rect.midX, rect.midY)))
            g.stroke(lens, with: .color(frame), lineWidth: max(1, s * 0.006))
        }
        let bridgeW = max(2, a.eyeX * 2 - lw + s * 0.02)
        let bridgeH = max(1.5, s * 0.012)
        g.fill(Path(roundedRect: CGRect(x: -bridgeW / 2, y: -bridgeH / 2, width: bridgeW, height: bridgeH),
                    cornerRadius: bridgeH / 2), with: .color(frame))
        for side in [-1.0, 1.0] as [CGFloat] {
            let armW = 0.06 * u
            let cx = side * (a.eyeX + lw / 2 + 0.025 * u)
            g.fill(Path(roundedRect: CGRect(x: cx - armW / 2, y: -lh * 0.15 - bridgeH / 2, width: armW, height: bridgeH),
                        cornerRadius: bridgeH / 2), with: .color(frame))
        }
    }

    /// Milestone / anniversary: the mood layer's striped cone, measured off
    /// the BODY (`u`) rather than the frame — the mood layer's own copy is
    /// sized off `size` and floats beside a flame burnt down to a wisp.
    private static func partyHat(_ ctx: inout GraphicsContext, _ a: Anchors, _ s: CGFloat) {
        let w = s * 0.22, h = s * 0.24
        let g = placed(ctx, s * 0.06, a.topY - h * 0.35, 14)
        var cone = Path()
        cone.move(to: pt(0, -h / 2)); cone.addLine(to: pt(w / 2, h / 2)); cone.addLine(to: pt(-w / 2, h / 2)); cone.closeSubpath()
        g.fill(cone, with: .linearGradient(
            Gradient(colors: [Color(red: 1.0, green: 0.42, blue: 0.62), Color(red: 0.55, green: 0.42, blue: 1.0)]),
            startPoint: pt(0, -h / 2), endPoint: pt(0, h / 2)))
        g.stroke(cone, with: .color(.white.opacity(0.35)), lineWidth: max(1, s * 0.006))
        var stripes = g
        stripes.clip(to: cone)
        for i in 0..<2 {
            let y = -h * 0.05 + CGFloat(i) * h * 0.28
            stripes.fill(Path(CGRect(x: -w / 2, y: y - h * 0.04, width: w, height: h * 0.08)),
                         with: .color(.white.opacity(0.28)))
        }
        g.fill(circle(0, -h / 2, s * 0.025), with: .color(Color(red: 1.0, green: 0.9, blue: 0.45)))
    }

    /// Bedtime: a soft blue cap with a drooping tip and a pom-pom.
    private static func nightcap(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let w = 0.30 * u, h = 0.28 * u
        let g = placed(ctx, 0.02 * u, a.topY + 0.02 * u, -4)
        var cap = Path()
        cap.move(to: pt(-w * 0.46, h * 0.28))
        cap.addQuadCurve(to: pt(w * 0.10, -h * 0.45), control: pt(-w * 0.30, -h * 0.40))
        cap.addQuadCurve(to: pt(w * 0.70, h * 0.25), control: pt(w * 0.55, -h * 0.50))
        cap.addQuadCurve(to: pt(w * 0.18, -h * 0.10), control: pt(w * 0.42, -h * 0.18))
        cap.addQuadCurve(to: pt(w * 0.46, h * 0.28), control: pt(w * 0.35, h * 0.10))
        cap.closeSubpath()
        g.fill(cap, with: .color(rgb(0x5B6FD6)))
        for (x, y) in [(-0.2, 0.0), (0.05, -0.25), (0.3, -0.2), (0.2, 0.1)] as [(CGFloat, CGFloat)] {
            g.fill(circle(x * w, y * h, 0.012 * u), with: .color(.white.opacity(0.85)))
        }
        g.fill(Path(roundedRect: CGRect(x: -w * 0.54, y: h * 0.18, width: w * 1.08, height: h * 0.20),
                    cornerRadius: h * 0.10), with: .color(rgb(0xE8ECFF)))
        g.fill(circle(w * 0.72, h * 0.30, 0.04 * u), with: .color(rgb(0xE8ECFF)))
    }

    // MARK: Streak gear

    /// 7 days: a blue polka-dot bandana knotted under his grin.
    private static func bandana(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let w = 0.58 * u, h = 0.05 * u
        let g = placed(ctx, 0, a.bottom - 0.095 * u)
        let blue = rgb(0x2563EB)
        g.fill(band(w: w, h: h, sag: 0.4), with: .color(blue))
        var tri = Path()
        tri.move(to: pt(-w * 0.16, h * 0.7)); tri.addLine(to: pt(w * 0.16, h * 0.7)); tri.addLine(to: pt(0, h * 3.1)); tri.closeSubpath()
        g.fill(tri, with: .color(blue))
        for (x, y) in [(-0.3, 0.1), (-0.1, 0.6), (0.12, 0.6), (0.32, 0.1), (0, 1.6), (-0.04, 2.3)] as [(CGFloat, CGFloat)] {
            g.fill(circle(x * w, y * h, 0.011 * u), with: .color(.white))
        }
    }

    /// A band that curves like it wraps a round body: top edge sags by `sag`
    /// of its height, bottom edge by one more.
    private static func band(w: CGFloat, h: CGFloat, sag: CGFloat) -> Path {
        var p = Path()
        p.move(to: pt(-w / 2, -h / 2))
        p.addQuadCurve(to: pt(w / 2, -h / 2), control: pt(0, h * sag))
        p.addLine(to: pt(w / 2, h / 2))
        p.addQuadCurve(to: pt(-w / 2, h / 2), control: pt(0, h * (sag + 1)))
        p.closeSubpath()
        return p
    }

    /// 30 days: a terry sweatband across the forehead.
    private static func sweatband(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let w = 0.50 * u, h = 0.06 * u
        let g = placed(ctx, -0.005 * u, a.faceY - 0.135 * u)
        g.fill(band(w: w, h: h, sag: 0.9), with: .color(rgb(0xF4F4F6)))
        var stripe = Path()
        stripe.move(to: pt(-w / 2, -h * 0.05))
        stripe.addQuadCurve(to: pt(w / 2, -h * 0.05), control: pt(0, h * 1.35))
        g.stroke(stripe, with: .color(rgb(0xE8384F)), lineWidth: h * 0.28)
    }

    /// 100 days: a pair of red-soled sneakers poking out under him.
    private static func sneakers(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let w = 0.19 * u, h = 0.085 * u
        let red = rgb(0xE8384F)
        for side in [-1.0, 1.0] as [CGFloat] {
            var g = placed(ctx, side * 0.14 * u, a.bottom - h * 0.35)
            g.scaleBy(x: side, y: 1)
            var upper = Path()
            upper.move(to: pt(-w * 0.5, h * 0.35))
            upper.addLine(to: pt(-w * 0.5, -h * 0.1))
            upper.addQuadCurve(to: pt(-w * 0.15, -h * 0.5), control: pt(-w * 0.45, -h * 0.5))
            upper.addLine(to: pt(w * 0.05, -h * 0.45))
            upper.addQuadCurve(to: pt(w * 0.45, h * 0.02), control: pt(w * 0.2, -h * 0.05))
            upper.addQuadCurve(to: pt(w * 0.5, h * 0.35), control: pt(w * 0.55, h * 0.1))
            upper.closeSubpath()
            g.fill(upper, with: .color(rgb(0xFAFAFA)))
            g.fill(Path(roundedRect: CGRect(x: -w * 0.52, y: h * 0.22, width: w * 1.04, height: h * 0.28),
                        cornerRadius: h * 0.14), with: .color(red))
            var swoosh = Path()
            swoosh.move(to: pt(-w * 0.3, -h * 0.05))
            swoosh.addQuadCurve(to: pt(w * 0.25, -h * 0.02), control: pt(-w * 0.05, h * 0.2))
            g.stroke(swoosh, with: .color(red), style: StrokeStyle(lineWidth: h * 0.14, lineCap: .round))
        }
    }

    /// 365 days: a jewelled crown perched on the tip.
    private static func crown(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat, _ s: CGFloat) {
        let w = 0.24 * u, h = 0.15 * u
        let gold = rgb(0xFFCF40), dark = rgb(0xC98A12)
        let g = placed(ctx, 0.02 * u, a.topY + 0.06 * u, -8)
        var body = Path()
        let points: [(CGFloat, CGFloat)] = [(-0.5, 0.5), (-0.5, -0.05), (-0.3, 0.12), (-0.16, -0.5), (0, 0.02),
                                            (0.16, -0.5), (0.3, 0.12), (0.5, -0.05), (0.5, 0.5)]
        for (i, p) in points.enumerated() {
            let point = pt(p.0 * w, p.1 * h)
            if i == 0 { body.move(to: point) } else { body.addLine(to: point) }
        }
        body.closeSubpath()
        g.fill(body, with: .color(gold))
        g.stroke(body, with: .color(dark), style: StrokeStyle(lineWidth: max(1, 0.012 * s), lineJoin: .round))
        var bandCtx = g
        bandCtx.clip(to: body)
        bandCtx.fill(Path(CGRect(x: -w / 2, y: h * 0.22, width: w, height: h * 0.28)), with: .color(dark.opacity(0.55)))
        g.fill(circle(0, h * 0.36, 0.022 * u), with: .color(rgb(0xE8384F)))
        g.fill(circle(-w * 0.3, h * 0.36, 0.016 * u), with: .color(rgb(0x4FB8FF)))
        g.fill(circle(w * 0.3, h * 0.36, 0.016 * u), with: .color(rgb(0x4FB8FF)))
        g.fill(circle(-w * 0.16, -h / 2, 0.018 * u), with: .color(gold))
        g.fill(circle(w * 0.16, -h / 2, 0.018 * u), with: .color(gold))
    }

    // MARK: Holiday outfits

    /// Halloween: sat in a carved pumpkin, with its stem on his tip.
    private static func pumpkin(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let w = 0.84 * u, h = 0.25 * u
        let top = a.bottom - 0.135 * u
        let g = placed(ctx, 0, top + h / 2)
        var shell = Path()
        shell.move(to: pt(-w * 0.5, 0))
        shell.addCurve(to: pt(0, -h * 0.42), control1: pt(-w * 0.5, -h * 0.62), control2: pt(-w * 0.16, -h * 0.56))
        shell.addCurve(to: pt(w * 0.5, 0), control1: pt(w * 0.16, -h * 0.56), control2: pt(w * 0.5, -h * 0.62))
        shell.addCurve(to: pt(0, h * 0.5), control1: pt(w * 0.5, h * 0.62), control2: pt(w * 0.2, h * 0.6))
        shell.addCurve(to: pt(-w * 0.5, 0), control1: pt(-w * 0.2, h * 0.6), control2: pt(-w * 0.5, h * 0.62))
        shell.closeSubpath()
        g.fill(shell, with: .color(rgb(0xF07B1A)))
        for f in [-0.28, 0, 0.28] as [CGFloat] {
            var rib = Path()
            rib.move(to: pt(f * w, -h * 0.45))
            rib.addQuadCurve(to: pt(f * w, h * 0.5), control: pt(f * w * 1.5, 0))
            g.stroke(rib, with: .color(rgb(0xC75A0D)), style: StrokeStyle(lineWidth: 0.012 * u, lineCap: .round))
        }
        var rim = Path()
        rim.move(to: pt(-w * 0.36, -h * 0.34))
        for i in 0...8 {
            rim.addLine(to: pt(-w * 0.36 + CGFloat(i) * w * 0.09, -h * 0.34 + (i % 2 == 1 ? h * 0.1 : 0)))
        }
        g.stroke(rim, with: .color(rgb(0x8A3A06)), style: StrokeStyle(lineWidth: 0.012 * u, lineJoin: .round))
        g.fill(ellipse(-w * 0.26, -h * 0.05, w * 0.07, h * 0.16), with: .color(rgb(0xFFB15C, 0.45)))

        // The stem is the costume's hat.
        let stem = placed(ctx, 0.01 * u, a.topY + 0.02 * u)
        var stalk = stem
        stalk.rotate(by: .degrees(10))
        stalk.fill(Path(roundedRect: CGRect(x: -0.025 * u, y: -0.09 * u, width: 0.05 * u, height: 0.10 * u),
                        cornerRadius: 0.015 * u), with: .color(rgb(0x4F7D2A)))
        var vine = Path()
        vine.move(to: pt(0, -0.04 * u))
        vine.addQuadCurve(to: pt(0.15 * u, -0.04 * u), control: pt(0.10 * u, -0.11 * u))
        stem.stroke(vine, with: .color(rgb(0x4F9D2A)), style: StrokeStyle(lineWidth: 0.018 * u, lineCap: .round))
    }

    /// December: a Santa hat slouched over the tip.
    private static func santaHat(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let w = 0.30 * u, h = 0.30 * u
        let g = placed(ctx, 0.03 * u, a.topY + 0.02 * u, -6)
        var hat = Path()
        hat.move(to: pt(-w * 0.46, h * 0.28))
        hat.addQuadCurve(to: pt(w * 0.12, -h * 0.52), control: pt(-w * 0.2, -h * 0.55))
        hat.addQuadCurve(to: pt(w * 0.62, -h * 0.05), control: pt(w * 0.5, -h * 0.5))
        hat.addQuadCurve(to: pt(w * 0.18, -h * 0.18), control: pt(w * 0.4, -h * 0.28))
        hat.addQuadCurve(to: pt(w * 0.46, h * 0.28), control: pt(w * 0.35, h * 0.05))
        hat.closeSubpath()
        g.fill(hat, with: .color(rgb(0xE0243A)))
        g.fill(Path(roundedRect: CGRect(x: -w * 0.56, y: h * 0.2, width: w * 1.12, height: h * 0.22),
                    cornerRadius: h * 0.11), with: .color(.white))
        g.fill(circle(w * 0.64, -h * 0.02, 0.045 * u), with: .color(.white))
    }

    /// Christmas Eve and Day: a striped scarf with a tail.
    private static func scarf(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let w = 0.66 * u, h = 0.065 * u
        let green = rgb(0x1F9D55), red = rgb(0xE0243A)
        let g = placed(ctx, 0, a.bottom - 0.085 * u)
        let shape = band(w: w, h: h, sag: 0.5)
        g.fill(shape, with: .color(green))
        var stripes = g
        stripes.clip(to: shape)
        for f in [-0.3, -0.1, 0.1, 0.3] as [CGFloat] {
            stripes.fill(Path(CGRect(x: f * w - w * 0.03, y: -h, width: w * 0.06, height: h * 3)), with: .color(red))
        }
        let tail = placed(g, w * 0.22, h * 0.6, -12)
        tail.fill(Path(roundedRect: CGRect(x: -h * 0.45, y: 0, width: h * 0.9, height: h * 1.9), cornerRadius: h * 0.2),
                  with: .color(green))
        tail.fill(Path(CGRect(x: -h * 0.45, y: h * 0.5, width: h * 0.9, height: h * 0.3)), with: .color(red))
        tail.fill(Path(CGRect(x: -h * 0.45, y: h * 1.2, width: h * 0.9, height: h * 0.3)), with: .color(red))
    }

    /// New Year's Day: gold star glasses.
    private static func starGlasses(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let gold = rgb(0xFFCF40), dark = rgb(0xB8860B)
        for side in [-1.0, 1.0] as [CGFloat] {
            let p = star(side * a.eyeX, a.faceY - 0.005 * u, 0.13 * u, inner: 0.5)
            ctx.fill(p, with: .color(gold))
            ctx.stroke(p, with: .color(dark), style: StrokeStyle(lineWidth: max(1, 0.006 * u), lineJoin: .round))
        }
        ctx.fill(Path(CGRect(x: -0.03 * u, y: a.faceY - 0.02 * u, width: 0.06 * u, height: 0.018 * u)), with: .color(dark))
    }

    /// Valentine's: a heart on a springy stalk, drawn around its base.
    static func drawHeartBopper(in ctx: inout GraphicsContext, u: CGFloat) {
        let hx = 0.07 * u, hy = -0.15 * u, r = 0.05 * u
        var stalk = Path()
        stalk.move(to: .zero)
        stalk.addQuadCurve(to: pt(hx, hy), control: pt(0.02 * u, hy + 0.06 * u))
        ctx.stroke(stalk, with: .color(rgb(0xFF8FB0)), style: StrokeStyle(lineWidth: 0.014 * u, lineCap: .round))
        var heart = Path()
        heart.move(to: pt(hx, hy + r * 0.9))
        heart.addCurve(to: pt(hx, hy - r * 0.45), control1: pt(hx - r * 1.6, hy - r * 0.2), control2: pt(hx - r * 0.9, hy - r * 1.4))
        heart.addCurve(to: pt(hx, hy + r * 0.9), control1: pt(hx + r * 0.9, hy - r * 1.4), control2: pt(hx + r * 1.6, hy - r * 0.2))
        heart.closeSubpath()
        ctx.fill(heart, with: .color(rgb(0xFF3B6B)))
        ctx.stroke(heart, with: .color(.white), lineWidth: max(0.8, 0.005 * u))
    }

    /// Valentine's: rosy cheeks.
    private static func blush(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        for side in [-1.0, 1.0] as [CGFloat] {
            ctx.fill(ellipse(side * (a.eyeX + 0.05 * u), a.faceY + 0.09 * u, 0.05 * u, 0.025 * u),
                     with: .color(rgb(0xFF5C8A, 0.55)))
        }
    }

    /// St. Patrick's: a little green buckled hat.
    private static func leprechaunHat(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let w = 0.22 * u, h = 0.20 * u
        let g = placed(ctx, 0.03 * u, a.topY, -8)
        g.fill(Path(roundedRect: CGRect(x: -w * 0.85, y: h * 0.32, width: w * 1.7, height: h * 0.16), cornerRadius: h * 0.08),
               with: .color(rgb(0x1C7A3A)))
        var crown = Path()
        crown.move(to: pt(-w / 2, h * 0.4)); crown.addLine(to: pt(-w * 0.42, -h * 0.5))
        crown.addLine(to: pt(w * 0.42, -h * 0.5)); crown.addLine(to: pt(w / 2, h * 0.4)); crown.closeSubpath()
        g.fill(crown, with: .color(rgb(0x23A04A)))
        g.fill(Path(CGRect(x: -w * 0.47, y: h * 0.05, width: w * 0.94, height: h * 0.2)), with: .color(rgb(0x1A1A1A)))
        g.stroke(Path(CGRect(x: -w * 0.1, y: h * 0.04, width: w * 0.2, height: h * 0.22)),
                 with: .color(rgb(0xFFCF40)), lineWidth: max(1, 0.014 * u))
    }

    /// Easter: bunny ears on a pink band.
    private static func bunnyEars(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        for side in [-1.0, 1.0] as [CGFloat] {
            let g = placed(ctx, side * 0.05 * u, a.topY + 0.06 * u, Double(side) * 16)
            let outer = ellipse(0, -0.11 * u, 0.05 * u, 0.13 * u)
            g.fill(outer, with: .color(rgb(0xFFF4F6)))
            g.stroke(outer, with: .color(rgb(0xE5C8CF)), lineWidth: max(0.8, 0.005 * u))
            g.fill(ellipse(0, -0.10 * u, 0.025 * u, 0.09 * u), with: .color(rgb(0xFF9FB5)))
        }
        var bandPath = Path()
        bandPath.move(to: pt(-0.1 * u, a.topY + 0.07 * u))
        bandPath.addQuadCurve(to: pt(0.1 * u, a.topY + 0.07 * u), control: pt(0, a.topY + 0.02 * u))
        ctx.stroke(bandPath, with: .color(rgb(0xFF9FB5)), style: StrokeStyle(lineWidth: 0.02 * u, lineCap: .round))
    }

    /// Independence Day: a striped top hat with a star.
    private static func starHat(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let w = 0.21 * u, h = 0.22 * u
        let blue = rgb(0x1F3F99), red = rgb(0xE0243A)
        let g = placed(ctx, 0.03 * u, a.topY - 0.01 * u, -8)
        g.fill(Path(roundedRect: CGRect(x: -w * 0.85, y: h * 0.34, width: w * 1.7, height: h * 0.15), cornerRadius: h * 0.07),
               with: .color(blue))
        let body = Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h * 0.9), cornerRadius: w * 0.08)
        g.fill(body, with: .color(.white))
        var inner = g
        inner.clip(to: body)
        for i in 0..<3 {
            inner.fill(Path(CGRect(x: -w / 2, y: -h / 2 + h * 0.1 + CGFloat(i) * h * 0.22, width: w, height: h * 0.1)),
                       with: .color(red))
        }
        inner.fill(Path(CGRect(x: -w / 2, y: h * 0.12, width: w, height: h * 0.24)), with: .color(blue))
        g.fill(star(0, h * 0.24, 0.05 * u), with: .color(.white))
    }

    /// Thanksgiving: a fan of tail feathers behind him.
    private static func turkeyFeathers(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let colors: [UInt32] = [0xC2410C, 0xEA8A1E, 0xE8384F, 0xEA8A1E, 0xC2410C, 0xA16207, 0xA16207]
        let angles: [Double] = [-70, -45, -20, 0, 20, 45, 70]
        let baseY = a.bottom - 0.28 * u
        for (i, angle) in angles.enumerated() {
            let g = placed(ctx, 0, baseY, angle)
            let feather = ellipse(0, -0.33 * u, 0.075 * u, 0.20 * u)
            g.fill(feather, with: .color(rgb(colors[i])))
            g.stroke(feather, with: .color(rgb(0x7C2D12)), lineWidth: max(0.8, 0.005 * u))
            g.fill(ellipse(0, -0.46 * u, 0.035 * u, 0.05 * u), with: .color(rgb(0xFDE68A, 0.8)))
        }
    }

    /// New Year's Eve: a black-and-gold countdown hat with a burst on top.
    private static func countdownHat(_ ctx: inout GraphicsContext, _ a: Anchors, _ s: CGFloat) {
        let w = s * 0.20, h = s * 0.26
        let gold = rgb(0xFFCF40)
        let g = placed(ctx, s * 0.05, a.topY - h * 0.35, 12)
        var cone = Path()
        cone.move(to: pt(0, -h / 2)); cone.addLine(to: pt(w / 2, h / 2)); cone.addLine(to: pt(-w / 2, h / 2)); cone.closeSubpath()
        g.fill(cone, with: .color(rgb(0x1A1A22)))
        var trim = Path()
        trim.move(to: pt(-w * 0.36, h * 0.22)); trim.addLine(to: pt(w * 0.36, h * 0.22))
        trim.addLine(to: pt(w * 0.43, h * 0.36)); trim.addLine(to: pt(-w * 0.43, h * 0.36)); trim.closeSubpath()
        g.fill(trim, with: .color(gold))
        var line = Path()
        line.move(to: pt(-w * 0.12, -h * 0.18)); line.addLine(to: pt(w * 0.12, -h * 0.18))
        g.stroke(line, with: .color(gold), lineWidth: max(1, s * 0.01))
        for i in 0..<6 {
            let ray = placed(g, 0, -h / 2, Double(i) * 60)
            ray.fill(Path(roundedRect: CGRect(x: -s * 0.005, y: -s * 0.05, width: s * 0.01, height: s * 0.05),
                          cornerRadius: s * 0.005), with: .color(gold))
        }
    }
}
