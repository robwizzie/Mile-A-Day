import Foundation

/// How a treat shows up on Flamey: three families, so a new treat is a glyph
/// plus one of these rather than a whole new pose.
enum TreatEffect {
    /// Rosy, swaying, hiccuping. Cartoon-tipsy only — never sick, never out.
    case tipsy
    /// Belly grows, cheeks puff, crumbs on the ground.
    case stuffed
    /// Wide eyes, jitter, steam.
    case wired
}

/// The treats calories can be translated into. `kcalPerUnit` are round,
/// everyday figures (a 5 oz glass of wine, a 12 oz beer, a fast-food
/// cheeseburger, a slice of pizza, a glazed donut, a 16 oz latte) — this is a
/// fun equivalence, not nutrition, and the sheet says so.
enum CalorieTreat: String, CaseIterable, Identifiable, Codable {
    case wine
    case beer
    case cheeseburger
    case pizza
    case donut
    case coffee

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wine: return "Wine"
        case .beer: return "Beer"
        case .cheeseburger: return "Burgers"
        case .pizza: return "Pizza"
        case .donut: return "Donuts"
        case .coffee: return "Lattes"
        }
    }

    var kcalPerUnit: Double {
        switch self {
        case .wine: return 125
        case .beer: return 150
        case .cheeseburger: return 300
        case .pizza: return 285
        case .donut: return 250
        case .coffee: return 190
        }
    }

    var effect: TreatEffect {
        switch self {
        case .wine, .beer: return .tipsy
        case .cheeseburger, .pizza, .donut: return .stuffed
        case .coffee: return .wired
        }
    }

    var emoji: String {
        switch self {
        case .wine: return "🍷"
        case .beer: return "🍺"
        case .cheeseburger: return "🍔"
        case .pizza: return "🍕"
        case .donut: return "🍩"
        case .coffee: return "☕️"
        }
    }

    /// "glass of wine" / "glasses of wine" — singular only when the DISPLAYED
    /// number is exactly 1, so "1.0" and "1" agree with their noun.
    func unitName(count: Double) -> String {
        let singular = TreatFormat.count(count) == "1"
        switch self {
        case .wine: return singular ? "glass of wine" : "glasses of wine"
        case .beer: return singular ? "beer" : "beers"
        case .cheeseburger: return singular ? "cheeseburger" : "cheeseburgers"
        case .pizza: return singular ? "slice of pizza" : "slices of pizza"
        case .donut: return singular ? "donut" : "donuts"
        case .coffee: return singular ? "latte" : "lattes"
        }
    }

    /// One curve for tipsiness / fullness / buzz: 1 unit ≈ 0.27, 4 ≈ 0.63,
    /// 12+ = 1. Logarithmic so a week's worth is visibly different from a
    /// day's, and an all-time thousand doesn't need a new pose.
    static func level(for count: Double) -> Double {
        min(1, log2(1 + max(0, count)) / log2(13))
    }

    /// The feature's name everywhere a user sees it. "Treats" said what the
    /// glyphs were, not what they MEANT: these are what your miles have
    /// earned — the framing that makes Flamey eating them the reward, not the
    /// consequence.
    static let featureName = "Well Earned"

    /// "A mile earns about 0.8 glasses of wine." — the empty-state nudge and
    /// the one sentence that explains the whole mechanic. ~100 kcal per mile
    /// of walking is a round figure; the sheet says every number is rough.
    var perMileHint: String {
        let units = 100.0 / kcalPerUnit
        return "A mile earns about \(TreatFormat.count(units)) \(unitName(count: units))."
    }

    static let key = "calorieTreatV1"

    /// A retired raw value decodes nil ⇒ the default, so nothing stays stuck
    /// on a treat that no longer exists (PostGridFilter precedent).
    static var current: CalorieTreat {
        get { CalorieTreat(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .wine }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

/// Which stretch of walks & runs the treats are counted over.
enum TreatPeriod: String, CaseIterable, Identifiable {
    case today
    case week
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .week: return "This Week"
        case .allTime: return "All Time"
        }
    }

    /// Lower-case, mid-sentence form.
    var caption: String {
        switch self {
        case .today: return "today"
        case .week: return "this week"
        case .allTime: return "all time"
        }
    }

    static let key = "calorieTreatPeriodV1"

    /// Default is the WEEK: one mile ≈ 100 kcal ≈ 0.8 of a glass, which is a
    /// dull number; a week is ~6 and Flamey is visibly tipsy.
    static var current: TreatPeriod {
        get { TreatPeriod(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .week }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

enum TreatFormat {
    /// One decimal under 10 ("6.2", but "6" when it lands exactly), whole
    /// numbers from 10 up — the second decimal of a burger is noise.
    static func count(_ value: Double) -> String {
        let clamped = max(0, value)
        if clamped >= 10 { return String(Int(clamped.rounded())) }
        let oneDecimal = (clamped * 10).rounded() / 10
        if oneDecimal == oneDecimal.rounded() { return String(Int(oneDecimal)) }
        return String(format: "%.1f", oneDecimal)
    }

    /// "780", "1.2k", "12k".
    static func kcal(_ value: Double) -> String {
        let clamped = max(0, value)
        if clamped >= 10_000 { return String(format: "%.0fk", clamped / 1000) }
        if clamped >= 1000 { return String(format: "%.1fk", clamped / 1000) }
        return String(Int(clamped.rounded()))
    }
}
