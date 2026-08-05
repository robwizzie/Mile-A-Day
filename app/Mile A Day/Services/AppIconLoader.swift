import Foundation
import SwiftUI

/// Fetches each partner app's real App Store icon.
///
/// The icons are pulled from Apple's public lookup endpoint rather than bundled
/// as image assets, for three reasons:
///
///  - **They stay right.** Vendors redesign their icons (and rebrand outright —
///    Fitbit became Google Health). A bundled PNG goes stale silently; a looked-
///    up one follows whatever is on the App Store today.
///  - **No third-party trademarks ship inside the app.** We display the
///    vendor's own store artwork to identify the app the user is connecting,
///    which is what the artwork is for — we don't redistribute it.
///  - **One request covers everything.** The endpoint takes a comma-separated
///    id list, so all thirteen icons come back in a single call, cached
///    afterwards.
///
/// Nothing here is load-bearing: every icon falls back to the platform's SF
/// Symbol, so a failed request, an offline device, or a retired app id just
/// leaves the previous look intact.
@Observable
final class AppIconLoader {
    static let shared = AppIconLoader()

    /// App Store id → artwork URL.
    private(set) var artwork: [String: URL] = [:]

    private static let cacheKey = "com.mileaday.appIconArtwork"
    private static let fetchedAtKey = "com.mileaday.appIconArtworkFetchedAt"
    /// Icons change rarely; a week keeps them current without chattiness.
    private static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    private var isLoading = false

    private init() {
        // Serve the cache immediately so rows render icons on first paint
        // rather than popping in after a round trip.
        if let stored = UserDefaults.standard.dictionary(forKey: Self.cacheKey)
            as? [String: String]
        {
            artwork = stored.compactMapValues(URL.init(string:))
        }
    }

    /// Fetch artwork for the given App Store ids, unless a fresh cache covers
    /// them already. Safe to call from every appearance.
    @MainActor
    func loadIfNeeded(for appStoreIds: [String]) async {
        guard !isLoading, !appStoreIds.isEmpty else { return }

        let fetchedAt = UserDefaults.standard.double(forKey: Self.fetchedAtKey)
        let age = Date().timeIntervalSince1970 - fetchedAt
        let covered = appStoreIds.allSatisfy { artwork[$0] != nil }
        if covered && age < Self.maxAge { return }

        isLoading = true
        defer { isLoading = false }

        guard
            let url = URL(
                string:
                    "https://itunes.apple.com/lookup?id=\(appStoreIds.joined(separator: ","))"
            )
        else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(LookupResponse.self, from: data)

            var merged = artwork
            for result in decoded.results {
                // artworkUrl100 is the largest size the lookup returns by
                // default and is plenty for a 36pt row icon on 3x.
                if let iconURL = URL(string: result.artworkUrl100) {
                    merged[String(result.trackId)] = iconURL
                }
            }
            artwork = merged

            UserDefaults.standard.set(
                merged.mapValues { $0.absoluteString }, forKey: Self.cacheKey)
            UserDefaults.standard.set(
                Date().timeIntervalSince1970, forKey: Self.fetchedAtKey)
        } catch {
            // Cosmetic only — the SF Symbol fallback already renders.
            print("[AppIconLoader] icon fetch failed: \(error.localizedDescription)")
        }
    }

    private struct LookupResponse: Decodable {
        let results: [Result]
        struct Result: Decodable {
            let trackId: Int
            let artworkUrl100: String
        }
    }
}

/// A partner app's icon: the real App Store artwork when we have it, the
/// platform's SF Symbol until then.
///
/// The symbol isn't just a spinner substitute — it's the permanent fallback for
/// offline devices and for HealthKit sources that aren't in our catalog at all,
/// so both looks have to be presentable.
struct PlatformIconView: View {
    let symbol: String
    let tint: Color
    /// Nil for a detected source we don't recognise — symbol only.
    let appStoreId: String?
    var size: CGFloat = 36

    private var iconURL: URL? {
        guard let appStoreId else { return nil }
        return AppIconLoader.shared.artwork[appStoreId]
    }

    var body: some View {
        Group {
            if let iconURL {
                AsyncImage(url: iconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        symbolIcon
                    }
                }
            } else {
                symbolIcon
            }
        }
        .frame(width: size, height: size)
        // App icons are squircles; matching the corner radius to the size keeps
        // the curve right whether this renders at 36pt or 48pt.
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    private var symbolIcon: some View {
        ZStack {
            tint.opacity(0.15)
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundColor(tint)
        }
    }
}
