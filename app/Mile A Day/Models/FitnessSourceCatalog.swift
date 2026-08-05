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

    /// Optimistic deep link into the installed app. Wrong or missing schemes
    /// degrade gracefully — `FitnessSourceLauncher` falls back to the App Store.
    let urlScheme: String?

    /// Where the Apple Health toggle lives, in that app's own words.
    let setupSteps: [String]

    /// The thing that actually trips people up. Worth more than the steps.
    let caveat: String?

    static func == (a: FitnessSourcePlatform, b: FitnessSourcePlatform) -> Bool {
        a.id == b.id
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
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
            urlScheme: "strava://",
            setupSteps: [
                "Open Strava and go to the You tab.",
                "Tap the settings gear, then Manage Apps and Devices.",
                "Choose Health, then turn on Send to Health.",
                "Make sure Workouts and Routes are enabled on the permission screen.",
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
            urlScheme: "garminconnectmobile://",
            setupSteps: [
                "Open Garmin Connect and tap More in the bottom-right.",
                "Go to Settings, then Connected Apps.",
                "Select Apple Health and tap Connect with Apple Health.",
                "Enable Workouts, Active Energy, Heart Rate and Steps.",
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
            urlScheme: "fitbit://",
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
            urlScheme: "whoop://",
            setupSteps: [
                "Open WHOOP and go to More, then App Settings.",
                "Choose Integrations, then Apple Health.",
                "Turn on the connection and allow Workouts.",
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
            urlScheme: "oura://",
            setupSteps: [
                "Open Oura and tap your profile icon.",
                "Go to App integrations, then Apple Health.",
                "Enable it and allow Workouts and Steps.",
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
            urlScheme: "peloton://",
            setupSteps: [
                "Open Peloton and tap your profile, then the settings gear.",
                "Choose Apple Health and turn on the connection.",
                "Allow Workouts when prompted.",
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
            urlScheme: "nikerunclub://",
            setupSteps: [
                "Open Nike Run Club and go to the Profile tab.",
                "Tap the settings gear, then Health.",
                "Turn on Write to Health and allow Workouts.",
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
            urlScheme: nil,
            setupSteps: [
                "Open the COROS app and go to the Profile tab.",
                "Tap Settings, then Apple Health.",
                "Enable the connection and allow Workouts.",
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
            urlScheme: nil,
            setupSteps: [
                "Open Polar Flow and tap the menu in the top left.",
                "Go to Settings, then Apple Health.",
                "Turn on the connection and allow Workouts.",
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
            urlScheme: nil,
            setupSteps: [
                "Open Suunto and go to the profile tab.",
                "Tap Settings, then Apple Health.",
                "Enable it and allow Workouts.",
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
            urlScheme: nil,
            setupSteps: [
                "Open Runna and go to the Profile tab.",
                "Tap Settings, then Apple Health.",
                "Allow Runna to write Workouts.",
            ],
            caveat: nil
        ),
        FitnessSourcePlatform(
            id: "mapmyrun",
            name: "MapMyRun",
            symbol: "map",
            tint: Color(red: 0.1, green: 0.6, blue: 0.85),
            bundleHints: ["mapmyrun", "mapmyfitness"],
            nameHints: ["mapmyrun", "map my run"],
            urlScheme: nil,
            setupSteps: [
                "Open MapMyRun and go to More, then Settings.",
                "Choose Apps & Devices, then Apple Health.",
                "Connect and allow Workouts.",
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
            urlScheme: nil,
            setupSteps: [
                "Open adidas Running and go to the Profile tab.",
                "Tap the settings gear, then Apple Health.",
                "Turn on the connection and allow Workouts.",
            ],
            caveat: nil
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
