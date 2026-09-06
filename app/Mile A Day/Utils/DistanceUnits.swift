import Foundation

/// The unit a distance is SHOWN in. Storage, sync, scoring and the goal are
/// miles everywhere (the server, HealthKit rollups, streak tolerance) and
/// stay miles: this is a display preference, resolved once at the formatter,
/// never a second number anything computes with.
enum DistanceUnit: String, CaseIterable, Identifiable {
    case miles
    case kilometers

    var id: String { rawValue }

    /// "mi" / "km"
    var abbreviation: String {
        switch self {
        case .miles: return "mi"
        case .kilometers: return "km"
        }
    }

    /// "/mi" / "/km"
    var paceSuffix: String { "/" + abbreviation }

    /// "miles" / "kilometers"
    var plural: String {
        switch self {
        case .miles: return "miles"
        case .kilometers: return "kilometers"
        }
    }

    /// "mile" / "kilometer"
    var singular: String {
        switch self {
        case .miles: return "mile"
        case .kilometers: return "kilometer"
        }
    }

    /// "Miles" / "Kilometers"
    var title: String { plural.capitalized }

    /// Multiply a MILES value by this to get the display value.
    var perMile: Double {
        switch self {
        case .miles: return 1
        case .kilometers: return 1.609344
        }
    }

    /// What the device is set to. `Locale.measurementSystem` is the user's
    /// own "Measurement System" setting (Settings ▸ General ▸ Language &
    /// Region), which is what a person who lives in kilometres has already
    /// told the phone once — so it's the default and never a guess from
    /// the region alone.
    static var systemDefault: DistanceUnit {
        Locale.current.measurementSystem == .us ? .miles : .kilometers
    }
}

/// The one place the preference is read and written.
enum DistanceUnits {
    /// Raw `DistanceUnit` value; absent = follow the device.
    static let key = "distanceUnitV1"
    /// Posted after `current` changes so a screen already on screen can
    /// redraw; most surfaces re-read on their next update anyway.
    static let didChange = Notification.Name("MAD_DistanceUnitDidChange")

    static var current: DistanceUnit {
        get {
            if let raw = UserDefaults.standard.string(forKey: key),
               let unit = DistanceUnit(rawValue: raw) {
                return unit
            }
            return DistanceUnit.systemDefault
        }
        set {
            let previous = current
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            if previous != newValue {
                NotificationCenter.default.post(name: didChange, object: nil)
            }
        }
    }

    /// True once the user has chosen (onboarding or Settings), as opposed
    /// to following the device.
    static var isChosen: Bool {
        UserDefaults.standard.string(forKey: key) != nil
    }

    /// Back to following the device.
    static func followDevice() {
        let previous = current
        UserDefaults.standard.removeObject(forKey: key)
        if previous != current {
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
}

// MARK: - Formatting (input is ALWAYS miles)

extension Double {
    /// This many miles, expressed in the display unit.
    var inDisplayUnit: Double { self * DistanceUnits.current.perMile }

    /// Two decimals, truncated, no unit — the display-unit twin of
    /// `milesText`. Truncation keeps the rule that a displayed "1.00" means
    /// the mile is actually there (see `milesFloor2`).
    var distanceText: String {
        String(format: "%.2f", inDisplayUnit.milesFloor2)
    }

    /// "1.61 km" / "1.00 mi" — the display-unit twin of `milesFormatted`.
    var distanceFormatted: String {
        "\(distanceText) \(DistanceUnits.current.abbreviation)"
    }

    /// One decimal, truncated, with the unit — for lifetime totals, where two
    /// decimals read as false precision ("412.3 mi").
    var distanceFormatted1: String {
        let v = (inDisplayUnit * 10.0 + 1e-6).rounded(.down) / 10.0
        return String(format: "%.1f %@", v, DistanceUnits.current.abbreviation)
    }

    /// Remaining-to-goal, CEILED in the display unit — never promise the goal
    /// is closer than it is (the rule every "to go" surface follows).
    var distanceToGoText: String {
        let v = (inDisplayUnit * 100.0 - 1e-6).rounded(.up) / 100.0
        return String(format: "%.2f", v)
    }
}

extension TimeInterval {
    /// Seconds per MILE → seconds per display unit (a kilometre is shorter,
    /// so the pace number gets smaller in km).
    var pacePerDisplayUnit: TimeInterval {
        self / DistanceUnits.current.perMile
    }
}
