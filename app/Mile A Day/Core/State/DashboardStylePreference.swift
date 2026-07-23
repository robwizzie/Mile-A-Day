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

    static var current: DashboardStyle {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let style = DashboardStyle(rawValue: raw) else {
                return .modern
            }
            return style
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
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
