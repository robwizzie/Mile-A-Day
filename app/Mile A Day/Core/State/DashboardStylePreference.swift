import Foundation

enum DashboardStyle: String, CaseIterable, Identifiable {
    case fun
    case modern

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fun: return "Fun"
        case .modern: return "Modern"
        }
    }

    var subtitle: String {
        switch self {
        case .fun: return "Animated flame buddy"
        case .modern: return "Calm, focused layout"
        }
    }
}

enum DashboardStylePreference {
    static let key = "dashboardStyleV1"
    static let hasChosenKey = "dashboardStyleChosenV1"

    /// The styles users may run, first = the default. Fun (Flamey) is the only
    /// one for now: the Modern dashboard's code stays so a future style can be
    /// offered again by adding it here — with more than one entry the first-run
    /// chooser, the Settings picker and the Customize "Look" tiles come back.
    static let offered: [DashboardStyle] = [.fun]
    static var defaultStyle: DashboardStyle { offered[0] }
    static var offersChoice: Bool { offered.count > 1 }

    static var current: DashboardStyle {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let style = DashboardStyle(rawValue: raw),
                  offered.contains(style) else {
                return defaultStyle
            }
            return style
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            // Mirror into the App Group so the Streak Flame widget can match the
            // chosen style (widgets can't see UserDefaults.standard).
            WidgetDataStore.save(dashboardStyle: newValue.rawValue)
            Task { @MainActor in DashboardStyleReporter.report() }
        }
    }

    /// Moves a stored style that is no longer offered (e.g. "modern") onto the
    /// default. Run at launch, before any view reads `key` through
    /// `@AppStorage`; the setter mirrors it to the widget and reports it to the
    /// server so friends see Flamey too.
    static func enforceOffered() {
        if let raw = UserDefaults.standard.string(forKey: key),
           let stored = DashboardStyle(rawValue: raw), offered.contains(stored) { return }
        current = defaultStyle
    }

    static var hasChosen: Bool {
        UserDefaults.standard.bool(forKey: hasChosenKey)
    }

    static func choose(_ style: DashboardStyle) {
        current = style
        markChosen()
    }

    static func markChosen() {
        UserDefaults.standard.set(true, forKey: hasChosenKey)
    }
}
