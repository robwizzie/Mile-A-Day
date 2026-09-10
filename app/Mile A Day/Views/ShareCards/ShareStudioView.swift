import SwiftUI

// MARK: - Share Studio
//
// ONE share sheet for a walk, from every surface that shows one.
//
// The sheet asks TWO questions and says so on screen: what the card shows
// (Photo / Route / Streak) and what shape it arrives in (Full story / Sticker).
// It used to ask them as ONE four-way rail — Photo | Route | Streak | Sticker —
// which is two axes crushed into one control: choosing "Sticker" threw away the
// design and choosing a design threw away the sticker, so neither choice ever
// stuck and there was no model of it to learn. Splitting them is the fix; both
// rows are labelled, and every combination renders.
//
// TWO actions, not three. Instagram Stories, More… and Save sat side by side
// once, which is a menu on a screen whose job is a decision. Save went first and
// cost nothing — the system share sheet behind the second button carries Save
// Image itself, so it was a second door to a room already on the way.
//
// The Instagram button is ALWAYS offered. It used to be gated on
// `InstagramStoryShare.isAvailable`, which requires a Meta App ID that has never
// been filled in — so the marquee action of the whole feature rendered for
// nobody. Without that ID the direct pasteboard handoff is impossible (Meta
// requires `source_application`), so the button opens the SYSTEM SHARE SHEET,
// where Instagram's own extension takes the image into its story composer. That
// needs no App ID. It used to save the card and open Instagram's camera, which
// left the walker hunting their camera roll for a picture we were holding.
//
// The preview is the real `MADStoryCard`, scaled — not an approximation of it —
// so what you tap Share on is what lands in the story. It carries the card's
// asynchronous inputs (`cardContent`) because `ImageRenderer` runs no view
// lifecycle: anything a subview would fetch for itself bakes as its fallback.

struct ShareStudioView: View {
    let content: MADStoryContent
    /// The post's permalink, when it has one. Offered under "More" so a link
    /// share is still one tap away — it just isn't the same button as an image.
    var link: URL? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var design: MADStoryDesign
    @State private var format: MADStoryFormat = .story
    @State private var shareItems: ShareStudioItems?
    /// Resolved once, before anything renders — see the `.task` in `body`.
    @State private var avatarImage: UIImage?
    @State private var photoWash: UIImage?

    init(content: MADStoryContent, link: URL? = nil) {
        self.content = content
        self.link = link
        _design = State(initialValue: content.defaultDesign)
    }

    private var designs: [MADStoryDesign] { content.availableDesigns }

    /// The content the card actually draws: whatever the caller handed us, plus
    /// the two things that can only be resolved asynchronously. Both are set on
    /// a copy rather than fetched inside the card, because the card is rendered
    /// by `ImageRenderer` for the real share and that runs no view lifecycle.
    private var cardContent: MADStoryContent {
        var resolved = content
        resolved.avatarImage = avatarImage
        resolved.photoWash = photoWash
        return resolved
    }

    private func loadAvatar() async {
        guard avatarImage == nil,
              let key = content.avatar?.imageURL, !key.isEmpty else { return }
        avatarImage = await RouteAvatarImageLoader.loadImage(for: key)
    }

    private func buildWash() {
        guard photoWash == nil, let photo = content.photo else { return }
        photoWash = MADStoryCard.wash(from: photo)
    }

    var body: some View {
        // No NavigationStack: its bar wanted an opaque background of its own,
        // which put a black slab across the top of a card screen whose whole
        // point is one continuous ground. The header below is 44pt of the same
        // gradient with a real close button in it.
        ZStack {
            MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                preview
                controls
                actions
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .preferredColorScheme(.dark)
        .task {
            // Both of these have to exist BEFORE the first render: ImageRenderer
            // runs no view lifecycle, so anything a subview would fetch for
            // itself bakes as its fallback (initials, in the avatar's case).
            await loadAvatar()
            buildWash()
        }
        .sheet(item: $shareItems) { items in
            ActivityViewController(activityItems: items.items)
        }
    }

    private var header: some View {
        ZStack {
            Text("Share your walk")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            HStack {
                // A 28pt disc inside a 44pt target. It was a 34pt disc carrying
                // a black-weight glyph at 90% white — heavy enough to read as
                // the most emphatic thing in the header, next to a title it is
                // supposed to sit quietly beside, and still under the 44pt
                // minimum. Lighter glyph, smaller disc, bigger tap area.
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.62))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.13)))
                        // Leading, so the disc lines up with the content margin
                        // the preview and controls share; the extra tap area
                        // grows inward where there is nothing to hit.
                        .frame(width: 44, height: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                Spacer()
            }
        }
        .frame(height: 44)
    }

    // MARK: Preview

    /// The real card, scaled to fit. `.scaleEffect` over a frame of the scaled
    /// size, so the layout is the design's and only the pixels shrink —
    /// re-laying the card out at preview size would let it diverge from the
    /// image that actually gets shared.
    private var preview: some View {
        GeometryReader { geo in
            // Every format previews inside a 9:16 frame, the sticker included —
            // it is going onto a story, so showing it at its own aspect would
            // preview it at a size nobody will ever see it at.
            let frameHeight = geo.size.height
            let frameWidth = min(geo.size.width, frameHeight * 9.0 / 16.0)
            let card = format.size
            // A sticker sits at ~80% of the story's width, roughly where a
            // thumb drops it. It previewed at 72%, which on top of a loud
            // backdrop left it looking like a small thing lost on a big one.
            let target = format == .sticker ? frameWidth * 0.80 : frameWidth
            let scale = target / card.width

            ZStack {
                if format == .sticker {
                    // Instagram puts a sticker on a gradient of our choosing, so
                    // the preview stands it on the same one rather than on a
                    // neutral the user will never see.
                    LinearGradient(
                        colors: [stickerTop, stickerBottom],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
                MADStoryCard(content: cardContent, design: design, format: format)
                    .scaleEffect(scale)
                    .frame(width: card.width * scale, height: card.height * scale)
            }
            .frame(width: frameWidth, height: frameHeight)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            // The card SWAPS, it does not cross-fade. `artZone` is a switch, so
            // each design is a different view identity — animating the change
            // dissolves one into the other, and a screenshot taken during it
            // shows the streak's flame and day count ghosting through a photo.
            .id("\(design.rawValue)-\(format.rawValue)")
            .transition(.identity)
            .shadow(color: .black.opacity(0.6), radius: 24, x: 0, y: 14)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 12) {
            // Only worth a row when there's a real choice — a walk with one
            // drawable design shouldn't be handed a picker of one.
            if designs.count > 1 {
                labelledRow("SHOW") {
                    HStack(spacing: 8) {
                        ForEach(designs) { option in
                            segment(
                                title: option.title,
                                icon: option.icon,
                                selected: option == design
                            ) { design = option }
                        }
                    }
                }
            }
            labelledRow("SHAPE") {
                HStack(spacing: 8) {
                    ForEach(MADStoryFormat.allCases) { option in
                        segment(
                            title: option.title,
                            icon: option.icon,
                            selected: option == format
                        ) { format = option }
                    }
                }
            }
            // "Sticker" is the one word here nobody can infer — it names a
            // FILE PROPERTY (a transparent edge), not something visible in a
            // preview that necessarily shows it standing on some background.
            // So the sheet says what the selected shape actually does.
            Text(format.explainer)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 4)
    }

    private func labelledRow<Row: View>(
        _ title: String,
        @ViewBuilder row: () -> Row
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.6)
                .foregroundColor(.white.opacity(0.4))
            row()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func segment(
        title: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { action() }
            MADHaptics.tap()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundColor(selected ? .black : .white.opacity(0.75))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(selected ? Color.white : Color.white.opacity(0.1))
            )
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    /// ONE primary action and one way out of it.
    ///
    /// There were three side by side — Instagram Stories, More…, Save — which
    /// is two too many for a screen whose job is "post this". Save was the
    /// first to go and cost nothing: the system share sheet behind "Other apps"
    /// carries Save Image itself, so the button was a second door to a room
    /// that was already on the way. What's left reads as a decision (post it)
    /// and an escape hatch (everything else), not a menu.
    private var actions: some View {
        VStack(spacing: 2) {
            Button(action: shareToInstagram) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 15, weight: .bold))
                        .accessibilityHidden(true)
                    Text("Share to Instagram")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.76, green: 0.23, blue: 0.55),
                                         Color(red: 0.96, green: 0.42, blue: 0.20)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                )
            }
            .buttonStyle(.plain)

            Button(action: shareElsewhere) {
                Text("Other apps, or save…")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.62))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 14)
    }

    // MARK: Doing the thing

    /// The gradient a sticker stands on — in the preview AND, because these two
    /// colours ride the Instagram payload, in the story it lands in.
    ///
    /// The top was `content.routeColor` at full strength, which is an accent
    /// colour asked to cover a whole 9:16 frame: walk blue became a bright slab
    /// that was the loudest thing on the screen, made the sticker look small and
    /// lost on it, and ran through muddy purple on its way to a maroon floor.
    /// Taken deep it does the opposite job — it reads as a ground, and the
    /// sticker is the thing you see.
    private var stickerTop: Color {
        Self.deepened(content.routeColor, amount: 0.65)
    }

    /// Near-black, a shade warm, so the gradient lands on the app's own floor
    /// rather than on a second colour competing with the top.
    private var stickerBottom: Color { Color(red: 0.055, green: 0.031, blue: 0.043) }

    /// Mix a colour toward the card's dark ground. Keeps the hue, drops the
    /// brightness — a darkened accent still says "walk", a flat one doesn't.
    private static func deepened(_ color: Color, amount: CGFloat) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return color }
        let floor: (CGFloat, CGFloat, CGFloat) = (0.051, 0.027, 0.035)
        return Color(
            red: Double(r + (floor.0 - r) * amount),
            green: Double(g + (floor.1 - g) * amount),
            blue: Double(b + (floor.2 - b) * amount),
            opacity: Double(a)
        )
    }

    private func render() -> UIImage? {
        MADStoryCard.render(content: cardContent, design: design, format: format)
    }

    private func shareToInstagram() {
        guard let image = render() else { return }

        if InstagramStoryShare.isAvailable {
            let payload: InstagramStoryShare.Payload = format.isTransparent
                ? .sticker(image, top: UIColor(stickerTop), bottom: UIColor(stickerBottom))
                : .background(image)
            if InstagramStoryShare.share(payload) {
                MADHaptics.action()
                TelemetryService.record(ShareTelemetry.instagram)
                return
            }
        }

        // No direct handoff — `isAvailable` needs a Meta App ID in
        // `MADFacebookAppID` and there isn't one yet.
        //
        // The SYSTEM SHARE SHEET is the best path that exists without it, and
        // it needs no App ID at all: Instagram ships a share extension that
        // appears there and takes the image straight into its own story
        // composer. What this used to do was save the card to Photos and open
        // Instagram's CAMERA, which leaves the walker hunting their own camera
        // roll for a picture the app was already holding — the longest version
        // of the shortest job on this screen.
        MADHaptics.action()
        TelemetryService.record(ShareTelemetry.instagram)
        shareItems = ShareStudioItems(items: [image])
    }

    private func shareElsewhere() {
        guard let image = render() else { return }
        // The image leads and the link rides with it: a picture is what gets
        // posted, but the link is what a friend in Messages can actually open.
        var items: [Any] = [image]
        if let link { items.append(link) }
        shareItems = ShareStudioItems(items: items)
        TelemetryService.record(ShareTelemetry.sheet)
    }

}

/// `.sheet(item:)` needs identity, and `[Any]` has none.
struct ShareStudioItems: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// The feature keys the share flow reports. Mirrors the backend's
/// `TRACKED_FEATURES` allowlist — an off-list key is dropped server-side, so
/// these two lists must move together.
enum ShareTelemetry {
    static let opened = "share_opened"
    static let instagram = "share_instagram"
    static let sheet = "share_sheet"
    static let saved = "share_saved"
}
