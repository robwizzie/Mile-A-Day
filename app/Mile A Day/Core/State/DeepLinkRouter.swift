import Foundation
import Combine

/// Holds deep-link targets that can arrive before the UI able to display
/// them exists (e.g. a cold launch from a universal link, where onOpenURL
/// fires while the splash/auth screens are still up). Views consume the
/// pending value once they're installed.
@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()

    /// Username from a profile link (mileaday.run/u/<username>), waiting for
    /// the Friends tab to resolve it and present the profile.
    @Published var pendingProfileUsername: String?

    private init() {}

    /// Extracts a username from a profile link in either form:
    /// - in-app scheme: mileaday://u/<username>  (what our QR codes encode)
    /// - web profile:   https://mileaday.run/u/<username>  (shared via text)
    /// Returns nil for anything that isn't a Mile A Day profile link.
    nonisolated func username(from url: URL) -> String? {
        let raw: String?
        if url.scheme == "mileaday", url.host == "u" {
            let candidate = url.lastPathComponent
            raw = candidate.isEmpty ? nil : candidate
        } else if url.scheme == "https",
                  let host = url.host?.lowercased(),
                  host == "mileaday.run" || host == "www.mileaday.run" {
            let parts = url.path.split(separator: "/").map(String.init)
            raw = (parts.count == 2 && parts[0] == "u") ? parts[1] : nil
        } else {
            raw = nil
        }
        guard let raw, !raw.isEmpty else { return nil }
        return raw.lowercased()
    }

    /// Parks a profile link's username for the Friends tab to resolve once it's
    /// installed. Returns true when the URL was a profile link.
    @discardableResult
    func handleProfileLink(_ url: URL) -> Bool {
        guard let username = username(from: url) else { return false }
        pendingProfileUsername = username
        return true
    }
}
