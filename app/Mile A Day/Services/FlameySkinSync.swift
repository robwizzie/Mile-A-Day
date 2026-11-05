import Foundation
import WidgetKit

/// Keeps Flamey's skins current. `GET /flamey/skins?format=<renderer>` answers
/// 304 until the server's set changes (its ETag is the set's version), so the
/// ~190 KB download happens once per change, not per launch. A good response
/// is parsed BEFORE it is saved: a bad payload never replaces a working cache.
/// Saved in the App Group container, where `FlameySkinCatalog` (app and
/// widgets) overlays it on the bundled copy.
enum FlameySkinSync {
    private static let etagKey = "flameySkinsETag"
    private static let lastCheckKey = "flameySkinsLastCheck"
    /// A skin set changes with a deploy, not by the minute.
    private static let minInterval: TimeInterval = 30 * 60

    static func syncIfNeeded(force: Bool = false) async {
        // Parse the catalog off the main thread before the first Flamey asks.
        _ = FlameySkinCatalog.shared
        // Background callers gate on tokens first (APIClient convention).
        guard TokenStore.hasTokens, let token = TokenStore.accessToken else { return }
        let defaults = UserDefaults.standard
        if !force, let last = defaults.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < minInterval {
            return
        }
        guard let url = URL(string: "\(AppConfig.baseURL)/flamey/skins?format=\(FlameySkinCatalog.format)"),
              let cacheURL = FlameySkinCatalog.cacheURL else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        if let etag = defaults.string(forKey: etagKey), FileManager.default.fileExists(atPath: cacheURL.path) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return }
        defaults.set(Date(), forKey: lastCheckKey)
        guard http.statusCode == 200 else { return } // 304: what we have is current

        // Parse into a scratch catalog first; only a payload that yields skins
        // is saved and applied.
        let probe = FlameySkinCatalog(bundled: false)
        guard probe.load(data, replacing: true) > 0 else { return }
        do {
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            return
        }
        if let etag = http.value(forHTTPHeaderField: "ETag") { defaults.set(etag, forKey: etagKey) }
        FlameySkinCatalog.shared.load(data, replacing: false)
        await MainActor.run {
            NotificationCenter.default.post(name: FlameySkinCatalog.didChange, object: nil)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "StreakFlameWidget")
    }
}
