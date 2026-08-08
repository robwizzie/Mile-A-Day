import Foundation

/// The real app icon for a fitness platform — Fitbit's, Strava's, Garmin's —
/// without shipping anybody's trademark in the binary.
///
/// `FitnessSourcePlatform.symbol` is an SF Symbol on purpose: bundling partner
/// logos as assets means shipping third-party trademarks we have no licence
/// for, which is an App Review risk (5.2.1) taken for decoration. But a generic
/// glyph is genuinely worse UI — "which app wrote this walk" is answered
/// instantly by an icon the user already recognises from their home screen, and
/// slowly by a waveform symbol they have to read a label to decode.
///
/// So the icon comes from Apple's own storefront, looked up by the App Store id
/// the catalog already stores for the "open in App Store" button. That is the
/// same artwork a Smart App Banner shows, sourced the same sanctioned way,
/// nothing bundled and nothing to licence. It also cannot go stale: if Fitbit
/// rebrands, the icon changes with them.
///
/// Everything about it degrades quietly. The lookup is one request per platform
/// for the lifetime of the install (the URL is persisted), the SF Symbol renders
/// immediately and stays until artwork arrives, and offline simply means the
/// symbol is what you get. No spinner, no gap, no layout shift — the artwork
/// occupies the symbol's slot at the same size.
@MainActor
final class FitnessSourceArtwork: ObservableObject {
    static let shared = FitnessSourceArtwork()

    private static let storageKey = "fitnessSourceArtworkV1"
    /// 60pt artwork: the chip draws it far smaller, and a 512pt icon for a
    /// 14pt slot is bandwidth spent on nothing.
    private static let artworkField = "artworkUrl60"

    /// App Store id → artwork URL string.
    @Published private(set) var artwork: [String: String]
    /// Ids currently in flight or already resolved-as-missing, so a row that
    /// re-renders sixty times doesn't fire sixty lookups.
    private var attempted: Set<String> = []

    private init() {
        artwork = UserDefaults.standard.dictionary(forKey: Self.storageKey)
            as? [String: String] ?? [:]
        attempted = Set(artwork.keys)
    }

    /// The icon URL if we have it, and a lookup kicked off if we don't.
    ///
    /// Safe to call from `body`: it returns synchronously and starts at most one
    /// request per app id.
    func url(forAppStoreId appStoreId: String) -> URL? {
        guard !appStoreId.isEmpty else { return nil }
        if let cached = artwork[appStoreId] { return URL(string: cached) }
        guard !attempted.contains(appStoreId) else { return nil }
        attempted.insert(appStoreId)
        Task { await fetch(appStoreId) }
        return nil
    }

    private func fetch(_ appStoreId: String) async {
        guard let endpoint = URL(
            string: "https://itunes.apple.com/lookup?id=\(appStoreId)&entity=software"
        ) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: endpoint)
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let results = json["results"] as? [[String: Any]],
                let icon = results.first?[Self.artworkField] as? String
            else {
                // A miss is remembered by `attempted`, so a delisted app costs
                // one request per launch rather than one per render.
                return
            }
            artwork[appStoreId] = icon
            UserDefaults.standard.set(artwork, forKey: Self.storageKey)
        } catch {
            // Offline, or the storefront is unreachable. The SF Symbol is
            // already on screen and stays there; allow a retry next launch.
            attempted.remove(appStoreId)
        }
    }
}
