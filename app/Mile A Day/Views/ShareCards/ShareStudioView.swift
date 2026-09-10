import SwiftUI

// MARK: - Share Studio
//
// ONE share sheet for a walk, from every surface that shows one.
//
// The sheet asks TWO questions and says so on screen: what the card shows
// (Photo / Route / Streak) and what shape it arrives in (Full screen / Sticker).
// It used to ask them as ONE four-way rail — Photo | Route | Streak | Sticker —
// which is two axes crushed into one control: choosing "Sticker" threw away the
// design and choosing a design threw away the sticker, so neither choice ever
// stuck and there was no model of it to learn. Splitting them is the fix; both
// rows are labelled, and every combination renders.
//
// The Instagram button is ALWAYS offered. It used to be gated on
// `InstagramStoryShare.isAvailable`, which requires a Meta App ID that has never
// been filled in — so the marquee action of the whole feature rendered for
// nobody, and what a user actually met was a preview, some unexplained chips and
// two grey buttons. When the direct handoff isn't wired up it now falls back to
// saving the card and opening Instagram, which is a longer path but a real one.
//
// The preview is the real `MADStoryCard`, scaled — not an approximation of it —
// so what you tap Share on is what lands in the story.

struct ShareStudioView: View {
    let content: MADStoryContent
    /// The post's permalink, when it has one. Offered under "More" so a link
    /// share is still one tap away — it just isn't the same button as an image.
    var link: URL? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var design: MADStoryDesign
    @State private var format: MADStoryFormat = .story
    @State private var shareItems: ShareStudioItems?
    @State private var toast: String?
    @State private var instagramFailed = false

    init(content: MADStoryContent, link: URL? = nil) {
        self.content = content
        self.link = link
        _design = State(initialValue: content.defaultDesign)
    }

    private var designs: [MADStoryDesign] { content.availableDesigns }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                VStack(spacing: 0) {
                    preview
                    controls
                        .padding(.top, MADTheme.Spacing.md)
                    actions
                        .padding(.top, MADTheme.Spacing.md)
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.bottom, MADTheme.Spacing.lg)

                if let toast { toastView(toast) }
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Close")
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(item: $shareItems) { items in
                ActivityViewController(activityItems: items.items)
            }
            .alert("Couldn't open Instagram", isPresented: $instagramFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Try \"More…\" and pick Instagram from the share sheet instead.")
            }
        }
        .preferredColorScheme(.dark)
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
            // A sticker sits at ~72% of the story's width, roughly where a
            // thumb drops it.
            let target = format == .sticker ? frameWidth * 0.72 : frameWidth
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
                MADStoryCard(content: content, design: design, format: format)
                    .scaleEffect(scale)
                    .frame(width: card.width * scale, height: card.height * scale)
            }
            .frame(width: frameWidth, height: frameHeight)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
        }
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

    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: shareToInstagram) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 15, weight: .bold))
                        .accessibilityHidden(true)
                    Text("Instagram Stories")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
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

            HStack(spacing: 10) {
                actionButton(icon: "square.and.arrow.up", title: "More…", action: shareElsewhere)
                actionButton(icon: "arrow.down.to.line", title: "Save", action: saveToPhotos)
            }
        }
    }

    private func actionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

    private func toastView(_ text: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .accessibilityHidden(true)
                Text(text)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Capsule().fill(Color.black.opacity(0.85)))
            .padding(.horizontal, 24)
            .padding(.bottom, 150)
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    // MARK: Doing the thing

    private var stickerTop: Color { content.routeColor }
    private var stickerBottom: Color { Color(red: 0.17, green: 0.07, blue: 0.12) }

    private func render() -> UIImage? {
        MADStoryCard.render(content: content, design: design, format: format)
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

        // No direct handoff (no Meta App ID configured, or Instagram declined
        // the open). Saving the card and opening Instagram is a longer path but
        // a working one — and it is strictly better than the button not being
        // there at all, which is what shipped.
        if InstagramStoryShare.openApp(after: image) {
            MADHaptics.success()
            TelemetryService.record(ShareTelemetry.instagram)
            flash("Saved to Photos — pick it in Instagram")
        } else {
            instagramFailed = true
        }
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

    private func saveToPhotos() {
        guard let image = render() else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        MADHaptics.success()
        TelemetryService.record(ShareTelemetry.saved)
        flash("Saved to Photos")
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation { if toast == text { toast = nil } }
        }
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
