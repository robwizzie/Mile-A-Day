import SwiftUI

// MARK: - Share Studio
//
// ONE share sheet for a walk, from every surface that shows one.
//
// What it replaces: eighteen share entry points that agreed on nothing — a
// labelled "Share" on dashboards and celebrations, a bare unlabelled paperplane
// on feed cards that shared a route image on your own post and a link on
// anyone else's. Users can't learn a control that does two different things,
// and the card-builder they could learn was only reachable from the Dashboard,
// never from the moment right after a walk when somebody actually wants to post.
//
// The preview is the real `MADStoryCard`, scaled — not an approximation of it —
// so what you tap Share on is what lands in the story.

struct ShareStudioView: View {
    let content: MADStoryContent
    /// The post's permalink, when it has one. Offered under "More" so a link
    /// share is still one tap away — it just isn't the same button as an image.
    var link: URL? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var face: MADStoryFace
    @State private var shareItems: ShareStudioItems?
    @State private var savedFlash = false
    @State private var instagramFailed = false

    init(content: MADStoryContent, link: URL? = nil) {
        self.content = content
        self.link = link
        _face = State(initialValue: content.defaultFace)
    }

    private var faces: [MADStoryFace] { content.availableFaces }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                VStack(spacing: 0) {
                    preview
                    faceRail
                        .padding(.top, MADTheme.Spacing.md)
                    actions
                        .padding(.top, MADTheme.Spacing.md)
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.bottom, MADTheme.Spacing.lg)

                if savedFlash { savedToast }
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
            // Every face previews inside a 9:16 frame, the sticker included —
            // it is going onto a story, so showing it at its own aspect would
            // preview it at a size nobody will ever see it at.
            let frameHeight = geo.size.height
            let frameWidth = min(geo.size.width, frameHeight * 9.0 / 16.0)
            let design = face.designSize
            // The sticker sits at ~72% of the story's width, roughly where a
            // thumb drops it.
            let target = face.isTransparent ? frameWidth * 0.72 : frameWidth
            let scale = target / design.width

            ZStack {
                if face.isTransparent {
                    LinearGradient(
                        colors: [content.routeColor, Color(red: 0.17, green: 0.07, blue: 0.12)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
                MADStoryCard(content: content, face: face)
                    .scaleEffect(scale)
                    .frame(width: design.width * scale, height: design.height * scale)
            }
            .frame(width: frameWidth, height: frameHeight)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Face rail

    private var faceRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(faces) { option in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            face = option
                        }
                        MADHaptics.tap()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: option.icon)
                                .font(.system(size: 12, weight: .bold))
                                .accessibilityHidden(true)
                            Text(option.title)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(option == face ? .black : .white.opacity(0.75))
                        .padding(.horizontal, 15)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(option == face ? Color.white : Color.white.opacity(0.1))
                        )
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if InstagramStoryShare.isAvailable {
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
            }

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

    private var savedToast: some View {
        VStack {
            Spacer()
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .accessibilityHidden(true)
                Text("Saved to Photos")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Capsule().fill(Color.black.opacity(0.8)))
            .padding(.bottom, 130)
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    // MARK: Doing the thing

    private func shareToInstagram() {
        guard let image = MADStoryCard.render(content: content, face: face) else { return }
        let ok: Bool
        if face.isTransparent {
            ok = InstagramStoryShare.share(
                .sticker(image,
                         top: UIColor(content.routeColor),
                         bottom: UIColor(red: 0.17, green: 0.07, blue: 0.12, alpha: 1))
            )
        } else {
            ok = InstagramStoryShare.share(.background(image))
        }
        if ok {
            MADHaptics.action()
            TelemetryService.record(ShareTelemetry.instagram)
        } else {
            instagramFailed = true
        }
    }

    private func shareElsewhere() {
        guard let image = MADStoryCard.render(content: content, face: face) else { return }
        // The image leads and the link rides with it: a picture is what gets
        // posted, but the link is what a friend in Messages can actually open.
        var items: [Any] = [image]
        if let link { items.append(link) }
        shareItems = ShareStudioItems(items: items)
        TelemetryService.record(ShareTelemetry.sheet)
    }

    private func saveToPhotos() {
        guard let image = MADStoryCard.render(content: content, face: face) else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        MADHaptics.success()
        TelemetryService.record(ShareTelemetry.saved)
        withAnimation { savedFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { savedFlash = false }
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
