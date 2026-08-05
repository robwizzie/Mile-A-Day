import SwiftUI

/// A third-party fitness platform users can feed into Mile A Day.
///
/// **There is no API integration behind any of these, and that is the design.**
/// Every one of them writes workouts into Apple Health, and the app reads
/// workouts from HealthKit with no source filter (see the queries in
/// `HealthKitManager`) — so the moment a user turns on that app's "write to
/// Apple Health" toggle, their runs and walks start counting here. No OAuth,
/// no partner approval, no tokens to refresh, and nothing that breaks when a
/// platform changes its API terms.
///
/// That last point is not hypothetical. Strava's API agreement forbids showing
/// a user's Strava data to anyone but that user, which a friends feed and a
/// leaderboard cannot honour; Garmin's developer program is closed to new
/// signups; Google Fit's API is being retired and its replacement is Android
/// only. Data that arrives through Apple Health carries none of those strings —
/// it's the user's own Health data by then, shared by the user, with Apple's
/// privacy model in front of it.
///
/// So a catalog entry is just **instructions plus a shortcut**: what to tap in
/// that app, and a button to get there.
struct FitnessSourcePlatform: Identifiable, Hashable {
    let id: String
    /// How the platform brands itself, for UI copy.
    let name: String
    /// SF Symbol. Deliberately not a partner logo — shipping third-party
    /// trademarks as bundled assets is an App Review risk we don't need.
    let symbol: String
    let tint: Color

    /// Fragments matched (case-insensitively, as substrings) against a
    /// HealthKit source's bundle identifier and display name.
    ///
    /// These are HINTS, never a requirement: detection shows every source
    /// HealthKit reports, using the name HealthKit gives it, whether or not it
    /// matches anything here. A stale or wrong fragment costs us a nice icon
    /// and a set of instructions — never a missing connection.
    let bundleHints: [String]
    let nameHints: [String]

    /// Numeric App Store id — the ONLY way this screen ever links to a partner
    /// app, and deliberately so.
    ///
    /// There used to be a `urlScheme` here too, tried first as a shortcut into
    /// the installed app. That is unsafe by construction: custom URL schemes are
    /// first-come-first-served and unverifiable, so ANY app can register
    /// `fitbit://`. One did — tapping Google Health opened an unrelated fitness
    /// app. A wrong scheme doesn't fail loudly, it silently hands the user to
    /// somebody else's software, which is far worse than an extra tap.
    ///
    /// An App Store id can't do that. It resolves to exactly one app, shows
    /// OPEN when it's already installed, and is verifiable — unlike a scheme,
    /// which nothing can validate from inside this app. Never reintroduce a
    /// scheme here without a way to prove it belongs to the vendor.
    let appStoreId: String

    /// Where the Apple Health toggle lives, in that app's own words.
    let setupSteps: [String]

    /// The thing that actually trips people up. Worth more than the steps.
    let caveat: String?

    static func == (a: FitnessSourcePlatform, b: FitnessSourcePlatform) -> Bool {
        a.id == b.id
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A platform that either can't reach Apple Health at all, or only reaches it
/// partially — and the honest reason why.
///
/// This exists because the failure is otherwise invisible and looks like OUR
/// bug: a Samsung Health user simply never sees their workouts appear and has
/// no way to find out that the iOS app has no Apple Health sync to give. Naming
/// the reason costs nothing and turns a mystery into a decision.
///
/// Where a platform offers a data export, the answer is not an apology — it's
/// the history importer, which recovers everything up to today.
struct FitnessSourceLimitation: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    /// Partial = it connects, but not for everything the user expects.
    let isPartial: Bool
    let reason: String
    let workaround: String
    /// Whether the workaround is "export your data and import it here".
    let offersImport: Bool
}

enum FitnessSourceCatalog {
    /// Apple's own sources (Watch, Fitness, the Health app itself). Grouped and
    /// labelled separately because there is nothing for the user to connect —
    /// these are already the baseline.
    static let applePrefixes = ["com.apple."]

    static let all: [FitnessSourcePlatform] = [
        FitnessSourcePlatform(
            id: "strava",
            name: "Strava",
            symbol: "figure.run",
            tint: Color(red: 0.98, green: 0.31, blue: 0.0),
            bundleHints: ["com.strava"],
            nameHints: ["strava"],
            appStoreId: "426826309",
            setupSteps: [
                "Open Strava and go to the You tab.",
                "Tap the settings gear, then Manage Apps and Devices.",
                "Choose Health, then turn on Send to Health.",
                "Allow Workouts and Routes on the permission screen.",
            ],
            caveat:
                "Strava only sends activities you recorded IN Strava. A run that "
                + "synced into Strava from a watch won't reach Apple Health — connect "
                + "that watch's own app instead."
        ),
        FitnessSourcePlatform(
            id: "garmin",
            name: "Garmin Connect",
            symbol: "applewatch",
            tint: Color(red: 0.0, green: 0.44, blue: 0.72),
            bundleHints: ["com.garmin"],
            nameHints: ["garmin"],
            appStoreId: "583446403",
            setupSteps: [
                "Open Garmin Connect and tap More in the bottom-right.",
                "Go to Settings, then Connected Apps.",
                "Select Apple Health, then tap Connect with Apple Health.",
                "Allow Workouts, Active Energy, Heart Rate and Steps.",
            ],
            caveat:
                "Garmin syncs one way, into Apple Health. That's all Mile A Day "
                + "needs — nothing is written back to your watch."
        ),
        FitnessSourcePlatform(
            id: "googlehealth",
            name: "Google Health (Fitbit)",
            symbol: "waveform.path.ecg",
            tint: Color(red: 0.0, green: 0.66, blue: 0.56),
            bundleHints: ["com.fitbit", "com.google.health"],
            nameHints: ["fitbit", "google health"],
            appStoreId: "462638897",
            setupSteps: [
                "Open Google Health (formerly the Fitbit app).",
                "Tap your profile icon in the top right.",
                "Choose Partner apps, then Apple Health.",
                "Follow the prompts and allow Exercise and Steps.",
            ],
            caveat:
                "Writing to Apple Health is new — if you don't see Partner apps, "
                + "update the app first. Older Fitbit builds could only read."
        ),
        FitnessSourcePlatform(
            id: "whoop",
            name: "WHOOP",
            symbol: "bolt.heart",
            tint: Color(red: 0.1, green: 0.1, blue: 0.1),
            bundleHints: ["whoop"],
            nameHints: ["whoop"],
            appStoreId: "933944389",
            setupSteps: [
                "Open WHOOP and tap More, then scroll to App Settings.",
                "Tap Integrations, then Apple Health at the top.",
                "Tap Connect and follow the prompts.",
                "Allow the data types you want WHOOP to share.",
            ],
            caveat: nil
        ),
        FitnessSourcePlatform(
            id: "oura",
            name: "Oura",
            symbol: "circle.circle",
            tint: Color(red: 0.4, green: 0.35, blue: 0.75),
            bundleHints: ["ouraring", "com.oura"],
            nameHints: ["oura"],
            appStoreId: "1043837948",
            setupSteps: [
                "Open Oura and tap the menu icon in the top-left.",
                "Tap Settings, then Apple Health under Data Sharing.",
                "Turn on Connect to Health.",
                "Allow Workouts and Steps when prompted.",
            ],
            caveat:
                "Oura's strength is recovery and sleep. It logs walks and workouts "
                + "but records no GPS, so those runs arrive without a route map."
        ),
        FitnessSourcePlatform(
            id: "peloton",
            name: "Peloton",
            symbol: "figure.indoor.cycle",
            tint: Color(red: 0.85, green: 0.15, blue: 0.25),
            bundleHints: ["onepeloton"],
            nameHints: ["peloton"],
            appStoreId: "792750948",
            setupSteps: [
                "Open Peloton and tap More.",
                "Under Account, tap Health App.",
                "Tap Connect to Health App.",
                "Turn on the workout categories, then tap Allow.",
            ],
            caveat:
                "Tread and outdoor runs count toward your mile. Cycling and "
                + "strength classes sync to Apple Health but aren't miles."
        ),
        FitnessSourcePlatform(
            id: "nikerunclub",
            name: "Nike Run Club",
            symbol: "figure.run.circle",
            tint: Color(red: 0.95, green: 0.35, blue: 0.1),
            bundleHints: ["com.nike"],
            nameHints: ["nike"],
            appStoreId: "387771637",
            setupSteps: [
                "Nike Run Club asks for Health access the first time you open it — tap Allow.",
                "To change it later, open the iPhone Settings app.",
                "Go to Privacy & Security, then Health, then Nike Run Club.",
                "Turn on Workouts so your runs are written to Apple Health.",
            ],
            caveat: nil
        ),
        FitnessSourcePlatform(
            id: "coros",
            name: "COROS",
            symbol: "applewatch.side.right",
            tint: Color(red: 0.9, green: 0.5, blue: 0.05),
            bundleHints: ["coros"],
            nameHints: ["coros"],
            appStoreId: "1277625343",
            setupSteps: [
                "Open the COROS app and go to the Profile page.",
                "Tap Setting, then 3rd Party Apps.",
                "Tap Data Sync, then Apple Health.",
                "Select the data types to sync, including Workouts.",
            ],
            caveat: nil
        ),
        FitnessSourcePlatform(
            id: "polar",
            name: "Polar Flow",
            symbol: "heart.circle",
            tint: Color(red: 0.0, green: 0.55, blue: 0.85),
            bundleHints: ["polar"],
            nameHints: ["polar"],
            appStoreId: "717172678",
            setupSteps: [
                "Open Polar Flow and tap More in the bottom-right.",
                "Go to General settings.",
                "Turn on the Apple Health toggle.",
                "Allow the categories you want Polar to share.",
            ],
            caveat: nil
        ),
        FitnessSourcePlatform(
            id: "suunto",
            name: "Suunto",
            symbol: "mountain.2",
            tint: Color(red: 0.15, green: 0.35, blue: 0.55),
            bundleHints: ["suunto", "amerbrands"],
            nameHints: ["suunto"],
            appStoreId: "1230327951",
            setupSteps: [
                "Open the Suunto app and tap the profile icon.",
                "Tap Settings and scroll to Save to Apple Health.",
                "Turn the toggle on, then tap Allow.",
                "Enable the activity categories so workouts sync.",
            ],
            caveat: nil
        ),
        FitnessSourcePlatform(
            id: "runna",
            name: "Runna",
            symbol: "figure.run.square.stack",
            tint: Color(red: 0.2, green: 0.45, blue: 0.95),
            bundleHints: ["runna"],
            nameHints: ["runna"],
            appStoreId: "1594204443",
            setupSteps: [
                "Open Runna and go to your Profile.",
                "Tap Connected Apps & Devices, then Apple Health.",
                "Turn on Sync Completed Workouts.",
                "Allow Runna to write Workouts when prompted.",
            ],
            caveat: nil
        ),
        FitnessSourcePlatform(
            id: "mapmyrun",
            name: "Map My Run",
            symbol: "map",
            tint: Color(red: 0.1, green: 0.6, blue: 0.85),
            bundleHints: ["mapmyrun", "mapmyfitness"],
            nameHints: ["mapmyrun", "map my run"],
            appStoreId: "291890420",
            setupSteps: [
                "Open Map My Run and tap the three-dot menu in the bottom-right.",
                "Tap Apps & Devices, then Apple Watch.",
                "Turn on the Apple Health toggle.",
                "Choose Turn All Categories On.",
            ],
            caveat: nil
        ),
        FitnessSourcePlatform(
            id: "adidasrunning",
            name: "adidas Running",
            symbol: "figure.run",
            tint: Color(red: 0.1, green: 0.1, blue: 0.1),
            bundleHints: ["runtastic", "adidas"],
            nameHints: ["adidas", "runtastic"],
            appStoreId: "336599882",
            setupSteps: [
                "Open adidas Running and go to your Profile.",
                "Tap the gear icon to open Settings.",
                "Tap Partner Accounts, then Apple Health.",
                "Tap Continue, then Share with Apple Health.",
            ],
            caveat: nil
        ),
    ]

    /// Platforms that can't fully bridge into Apple Health, with the reason.
    /// Kept factual — these are statements about what the software does, never
    /// a dig at a competitor, which is both fairer and safer in review.
    static let limitations: [FitnessSourceLimitation] = [
        FitnessSourceLimitation(
            id: "samsung",
            name: "Samsung Health",
            symbol: "iphone.slash",
            isPartial: false,
            reason:
                "Samsung Health doesn't sync to Apple Health. Its iPhone app has never "
                + "supported writing workouts there, so nothing it records can reach "
                + "Mile A Day automatically.",
            workaround:
                "Export your Samsung Health data and import it here — that brings across "
                + "everything up to today.",
            offersImport: true
        ),
        FitnessSourceLimitation(
            id: "googlefit",
            name: "Google Fit",
            symbol: "xmark.circle",
            isPartial: false,
            reason:
                "Google has retired the Google Fit APIs, and its replacement, Health "
                + "Connect, is Android-only — there's no iPhone version for us to read.",
            workaround:
                "If you use a Fitbit, the Google Health app now writes to Apple Health — "
                + "connect that instead. Otherwise, export and import your history.",
            offersImport: true
        ),
        FitnessSourceLimitation(
            id: "huawei",
            name: "Huawei Health",
            symbol: "iphone.slash",
            isPartial: false,
            reason:
                "Huawei Health doesn't write workouts to Apple Health on iPhone.",
            workaround: "Export your activities and import them here.",
            offersImport: true
        ),
        FitnessSourceLimitation(
            id: "strava-partial",
            name: "Strava",
            symbol: "exclamationmark.triangle",
            isPartial: true,
            reason:
                "Strava connects, but it only sends activities you recorded IN Strava. A "
                + "run that synced into Strava from a watch never reaches Apple Health — "
                + "which is why your Strava feed can look fuller than your streak here.",
            workaround:
                "Connect your watch's own app (Garmin Connect, COROS, Polar) as well. "
                + "That's the copy that carries the workout.",
            offersImport: false
        ),
        FitnessSourceLimitation(
            id: "peloton-partial",
            name: "Peloton",
            symbol: "exclamationmark.triangle",
            isPartial: true,
            reason:
                "Peloton connects fully, but only running and walking count toward a mile. "
                + "Cycling and strength classes still reach Apple Health — they just "
                + "aren't miles.",
            workaround: "Tread runs and outdoor runs count normally.",
            offersImport: false
        ),
    ]

    /// Best catalog match for a HealthKit source, or nil when we don't know it.
    ///
    /// Bundle id is checked before display name: a name like "Health" is shared
    /// by too many things to key on first.
    static func match(bundleIdentifier: String, sourceName: String) -> FitnessSourcePlatform? {
        let bundle = bundleIdentifier.lowercased()
        let name = sourceName.lowercased()

        if let byBundle = all.first(where: { platform in
            platform.bundleHints.contains { bundle.contains($0) }
        }) {
            return byBundle
        }
        return all.first { platform in
            platform.nameHints.contains { name.contains($0) }
        }
    }

    static func isAppleSource(bundleIdentifier: String) -> Bool {
        let bundle = bundleIdentifier.lowercased()
        return applePrefixes.contains { bundle.hasPrefix($0) }
    }
}
