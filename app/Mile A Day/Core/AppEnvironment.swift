import Foundation

/// App-wide configuration constants. Centralized so things like the backend
/// URL don't drift across service files.
enum AppConfig {
    /// REST API base URL. All services should build URLs against this rather
    /// than hardcoding the host.
    ///
    /// DEBUG builds only: set the "devBaseURLOverride" UserDefaults string
    /// (e.g. from a debugger pause or a dev menu) to point the app at a local
    /// `npm run dev` backend — where streak features are always enabled — and
    /// delete it to return to production. The override is compiled OUT of
    /// Release builds: TestFlight/App Store always talk to production.
    static let baseURL: String = {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "devBaseURLOverride"),
           !override.isEmpty {
            return override
        }
        #endif
        return "https://mad.mindgoblin.tech"
    }()
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

    static var apnsEnvironment: String {
        switch current {
        case .development:
            return "sandbox"
        case .production:
            return "production"
        }
    }
}
