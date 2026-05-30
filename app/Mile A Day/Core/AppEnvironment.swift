import Foundation

/// App-wide configuration constants. Centralized so things like the backend
/// URL don't drift across service files.
enum AppConfig {
    /// Production REST API base URL. All services should build URLs against
    /// this rather than hardcoding the host.
    static let baseURL = "https://mad.mindgoblin.tech"
}

/// Identifies which environment the app is running in.
///
/// Resolves from the build configuration: Debug builds report `.development`,
/// Release builds (TestFlight / App Store) report `.production`. Development-only
/// UI (debug menus, developer settings) should be gated on `isDevelopment`.
enum AppEnvironment {
    case development
    case production

    static var current: AppEnvironment {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }

    static var isDevelopment: Bool {
        current == .development
    }
}
