import Foundation

/// Fun (Flamey) is the only dashboard. The Modern dashboard was retired: a
/// stored "modern" no longer decodes, so `enforceOffered()` moves it to Fun at
/// launch. Friends on older app versions can still report "modern", which is
/// why feed cards keep their author-styled plain variant.
enum DashboardStyle: String, CaseIterable, Identifiable {
    case fun

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fun: return "Fun"
        }
    }

    var subtitle: String {
        switch self {
        case .fun: return "Animated flame buddy"
        }
    }
}

enum DashboardStylePreference {
    static let key = "dashboardStyleV1"

    /// The styles users may run, first = the default. Fun is the only one.
    static let offered: [DashboardStyle] = [.fun]
    static var defaultStyle: DashboardStyle { offered[0] }

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
}
