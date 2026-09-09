import UIKit

/// Hand a finished card to Instagram's story composer.
///
/// This is the deepest integration Instagram offers — there is no API that
/// posts on a user's behalf — and it is the same one Strava uses. The image
/// goes onto the general pasteboard under Meta's documented keys, then the
/// `instagram-stories://share` scheme opens the composer, which reads it.
///
/// Two shapes, and the difference matters:
///   * `.background` — our full 1080×1920 frame, edge to edge. One tap and
///     they're looking at a finished story.
///   * `.sticker` — a transparent PNG over a gradient we choose, which lands
///     draggable and resizable so they can place it on a story they were
///     already making.
enum InstagramStoryShare {

    private static let scheme = "instagram-stories"

    /// Meta's App ID, from `MADFacebookAppID` in Info.plist.
    ///
    /// Meta's docs specify an App ID for `source_application`. Until one is
    /// registered this returns nil and `isAvailable` is false, so the button
    /// hides itself — deliberately, because the failure mode of guessing is
    /// Instagram opening to an empty composer, which reads as the feature
    /// being broken rather than not yet set up.
    static var appID: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "MADFacebookAppID") as? String
        else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Is Instagram installed AND are we configured to hand off to it?
    ///
    /// `canOpenURL` needs `instagram-stories` declared in the Info.plist's
    /// `LSApplicationQueriesSchemes`, or it answers false however installed
    /// Instagram is.
    @MainActor
    static var isAvailable: Bool {
        guard appID != nil, let url = shareURL else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    private static var shareURL: URL? {
        guard let appID else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "share"
        components.queryItems = [URLQueryItem(name: "source_application", value: appID)]
        return components.url
    }

    enum Payload {
        /// A finished story frame, full bleed.
        case background(UIImage)
        /// A transparent sticker over a gradient of our choosing.
        case sticker(UIImage, top: UIColor, bottom: UIColor)
    }

    /// Returns false when the handoff couldn't even be attempted, so the caller
    /// can fall back to the system share sheet rather than leaving a dead tap.
    @MainActor
    @discardableResult
    static func share(_ payload: Payload) -> Bool {
        guard let url = shareURL, UIApplication.shared.canOpenURL(url) else { return false }

        var item: [String: Any] = [:]
        switch payload {
        case .background(let image):
            guard let data = image.pngData() else { return false }
            item["com.instagram.sharedSticker.backgroundImage"] = data
        case .sticker(let image, let top, let bottom):
            guard let data = image.pngData() else { return false }
            item["com.instagram.sharedSticker.stickerImage"] = data
            item["com.instagram.sharedSticker.backgroundTopColor"] = hex(top)
            item["com.instagram.sharedSticker.backgroundBottomColor"] = hex(bottom)
        }

        // Instagram reads this the moment it foregrounds. The expiry is Meta's
        // own guidance and it is also just hygiene — a walk's card has no
        // business sitting on the system pasteboard afterwards.
        UIPasteboard.general.setItems(
            [item],
            options: [.expirationDate: Date().addingTimeInterval(60 * 5)]
        )
        UIApplication.shared.open(url)
        return true
    }

    private static func hex(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let clamp: (CGFloat) -> Int = { Int((min(max($0, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }
}
