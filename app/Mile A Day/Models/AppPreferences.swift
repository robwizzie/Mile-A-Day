import Foundation

#if !os(watchOS)

struct AppPreferences: Codable {
    var useLocationBasedTimezone: Bool = false // Temporarily disabled due to performance issues
    var showTimezoneDebugInfo: Bool = false
    
    static let `default` = AppPreferences()
}

extension AppPreferences {
    private static let storageKey = "MAD_APP_PREFERENCES"
    
    /// Loads stored preferences or returns default values.
    static func load() -> AppPreferences {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let prefs = try? JSONDecoder().decode(AppPreferences.self, from: data)
        else {
            return .default
        }
        return prefs
    }
    
    /// Persists the current preferences to `UserDefaults`.
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
#endif
