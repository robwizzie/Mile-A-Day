import SwiftUI

// MARK: - Share Studio
//
// THE share surface — walks, the day, the streak and the week all open it.
//
// What it is, and why (the Strava / Duolingo lesson): a CAROUSEL of finished
// cards, one page per template, each a live preview of exactly what will
// post. You swipe to the one you like and tap where it goes. The old studio
// was two rows of labelled controls over one preview, which made the walker
// assemble the card in their head from the labels; the carousel shows every
// option at once, and "what will this look like?" is never a question.
//
// Layout, top to bottom:
//   * family chips (Picture · Route · Streak · Flamey · Sticker, or Week) —
//     one tap jumps the carousel to that family; they also say at a glance
//     what kinds of card this walk can make;
//   * the carousel — paged, the focused card full size and its neighbours
//     peeking smaller and dimmer, with page dots and the card's name under it;
//   * options for the FOCUSED card only, and only where they mean something:
//     Story vs Sticker for a card that renders both, and a Strava-style stat
//     toggle for a card with a stat rail;
//   * destinations — a big "Instagram Stories" button, then Instagram,
//     Messages, Save, Copy link, More.
//
// Preview == render. Every page draws the real `ShareCardView` (scaled), and
// the exported image is `ImageRenderer` of the same view — never an
// approximation. The card's asynchronous inputs (the avatar picture, the
// photo wash, the dark map snapshot) are resolved HERE before anything bakes,
// because `ImageRenderer` runs no view lifecycle: anything a card fetched for
// itself would bake as its fallback.
//
// Performance: only the focused page and its two neighbours are live views;
// a page further away shows the image it was last rendered as (cached when
// it was focused) or a quiet placeholder. The pages are big composited
// views — flame figures, route art, photos — and a dozen of them live at
// once is a dozen of the dashboard hero.
//
// Instagram: with a Meta App ID in `MADFacebookAppID` (Mile-A-Day-Info.plist)
// the big button hands the card straight to Instagram's story composer
// (`InstagramStoryShare` — a full frame as `backgroundImage`, a sticker as
// `stickerImage` over this sheet's own gradient). Without one that handoff is
// impossible (Meta requires `source_application`), so the button opens the
// system share sheet, where Instagram's own extension takes the image into
// its composer. Filling the ID lights the direct path with no code change.

struct ShareStudioView: View {
    let content: MADStoryContent
    /// The post's permalink, when it has one. Rides with the image to
    /// Messages and the share sheet, and backs "Copy link".
    var link: URL? = nil
    /// Where the carousel opens (a milestone celebration opens on the
    /// milestone). Falls back to a sibling in the same family, then the best
    /// available.
    var initialTemplate: ShareTemplate? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let templates: [ShareTemplate]
    @State private var selection: ShareTemplate?
    @State private var format: MADStoryFormat = .story
    @State private var statKinds: [ShareStatKind] = ShareStatKind.defaultSelection

    // Resolved once, before anything renders — see `resolveAssets`.
    @State private var avatarImage: UIImage?
    @State private var photoWash: UIImage?
    @State private var mapUnderlay: RouteMapSnapshot?
    /// Bumped whenever an asynchronous input lands, so a cached render of a
    /// page made before it arrived is never reused.
    @State private var assetsVersion = 0

    @State private var renderCache: [String: UIImage] = [:]
    @State private var shareItems: ShareStudioItems?
    @State private var messageItem: ShareMessageItem?
    @State private var toast: String?
    @State private var busy = false

    init(content: MADStoryContent, link: URL? = nil, initialTemplate: ShareTemplate? = nil) {
        self.content = content
        self.link = link
        self.initialTemplate = initialTemplate
        let available = ShareTemplate.available(for: content)
        self.templates = available
        let start = ShareTemplate.preferred(initialTemplate, in: available)
        _selection = State(initialValue: start)
        _format = State(initialValue: start.formats.first ?? .story)
    }

    private var current: ShareTemplate { selection ?? templates.first ?? .flameyMile }
    private var currentIndex: Int { templates.firstIndex(of: current) ?? 0 }

    private func effectiveFormat(_ template: ShareTemplate) -> MADStoryFormat {
        template.formats.contains(format) ? format : (template.formats.first ?? .story)
    }

    /// The content the cards actually draw: the caller's, plus what could
    /// only be resolved asynchronously.
    private var cardContent: MADStoryContent {
        var resolved = content
        resolved.avatarImage = avatarImage
        resolved.photoWash = photoWash
        resolved.mapUnderlay = mapUnderlay
        return resolved
    }

    private var availableStats: [ShareStatKind] { ShareStatKind.available(in: content) }

    private var families: [ShareTemplateFamily] {
        var seen: [ShareTemplateFamily] = []
        for template in templates where !seen.contains(template.family) { seen.append(template.family) }
        return seen
    }

    // MARK: Body

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if families.count > 1 {
                    familyChips
                        .padding(.top, 2)
                }
                carousel
                    .padding(.top, 10)
                pageCaption
                    .padding(.top, 10)
                options
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                destinations
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                    // Its own node: two presentations on one view race.
                    .sheet(item: $messageItem) { item in
                        MessageComposeSheet(image: item.image, link: link) { messageItem = nil }
                            .ignoresSafeArea()
                    }
            }

            if let toast {
                VStack {
                    Text(toast)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.8)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                        .padding(.top, 54)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .preferredColorScheme(.dark)
        .task { await resolveAssets() }
        .onChange(of: selection) { _, newValue in
            MADHaptics.tap()
            if let newValue { cacheRender(of: newValue) }
        }
        .sheet(item: $shareItems) { items in
            ActivityViewController(activityItems: items.items)
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text(content.week != nil ? "Share your week" : "Share")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.62))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.13)))
                        .frame(width: 44, height: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 44)
    }

    private var familyChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(families) { family in
                    let selected = current.family == family
                    Button {
                        guard let first = templates.first(where: { $0.family == family }) else { return }
                        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) {
                            selection = first
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: family.icon)
                                .font(.system(size: 11, weight: .bold))
                                .accessibilityHidden(true)
                            Text(family.title)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .foregroundColor(selected ? .black : .white.opacity(0.75))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: Carousel

    private var carousel: some View {
        GeometryReader { geo in
            let pageHeight = geo.size.height
            let pageWidth = max(120, min(geo.size.width * 0.78, pageHeight * 9.0 / 16.0))
            let margin = max(0, (geo.size.width - pageWidth) / 2)
            // Captured: the transition closure is nonisolated.
            let neighbourScale: CGFloat = reduceMotion ? 1 : 0.88

            ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(Array(templates.enumerated()), id: \.element) { index, template in
                        page(template, index: index, width: pageWidth)
                            .frame(width: pageWidth, height: pageWidth * 16.0 / 9.0)
                            .scrollTransition(.interactive, axis: .horizontal) { view, phase in
                                view
                                    .scaleEffect(phase.isIdentity ? 1 : neighbourScale)
                                    .opacity(phase.isIdentity ? 1 : 0.5)
                            }
                            .onTapGesture {
                                guard template != current else { return }
                                withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) {
                                    selection = template
                                }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(template.title)
                            .accessibilityAddTraits(template == current ? [.isSelected, .isImage] : [.isButton])
                    }
                }
                .scrollTargetLayout()
                .frame(height: pageHeight)
            }
            .contentMargins(.horizontal, margin, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selection)
            .onAppear {
                // `scrollPosition(id:)` doesn't reliably honour its INITIAL
                // value on a lazy stack — open on the requested card
                // explicitly (a milestone celebration opens on the milestone).
                proxy.scrollTo(current, anchor: .center)
            }
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func page(_ template: ShareTemplate, index: Int, width: CGFloat) -> some View {
        let live = abs(index - currentIndex) <= 1
        let pageFormat = effectiveFormat(template)
        ZStack {
            if live {
                preview(template, format: pageFormat, width: width)
            } else if let cached = renderCache[cacheKey(template, format: pageFormat)] {
                cachedPreview(cached, format: pageFormat, template: template, width: width)
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(template == current ? 0.16 : 0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 22, x: 0, y: 12)
    }

    /// The real card, scaled — layout is the card's own; only pixels shrink.
    private func preview(_ template: ShareTemplate, format: MADStoryFormat, width: CGFloat) -> some View {
        let card = format.size
        let target = format == .sticker ? width * 0.80 : width
        let scale = target / card.width
        return ZStack {
            if format == .sticker { stickerBackdrop(for: template) }
            ShareCardView(template: template, content: cardContent, format: format, stats: statKinds)
                .frame(width: card.width, height: card.height)
                .scaleEffect(scale)
                .frame(width: card.width * scale, height: card.height * scale)
        }
        .frame(width: width, height: width * 16.0 / 9.0)
        // A format or stat change SWAPS the card rather than cross-fading two
        // identities (ios.md: the flame ghosting through a photo).
        .id("\(template.rawValue)-\(format.rawValue)-\(statKey)-\(assetsVersion)")
        .transition(.identity)
    }

    private func cachedPreview(_ image: UIImage, format: MADStoryFormat,
                               template: ShareTemplate, width: CGFloat) -> some View {
        let target = format == .sticker ? width * 0.80 : width
        return ZStack {
            if format == .sticker { stickerBackdrop(for: template) }
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: target)
        }
        .frame(width: width, height: width * 16.0 / 9.0)
    }

    /// A sticker previews on the gradient it will land on in Instagram — the
    /// same two colours ride the story payload.
    private func stickerBackdrop(for template: ShareTemplate) -> some View {
        LinearGradient(colors: [stickerTop(template), stickerBottom],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var pageCaption: some View {
        VStack(spacing: 8) {
            if templates.count > 1 {
                HStack(spacing: 5) {
                    ForEach(templates) { template in
                        Capsule()
                            .fill(Color.white.opacity(template == current ? 0.9 : 0.22))
                            .frame(width: template == current ? 16 : 6, height: 6)
                    }
                }
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: current)
                .accessibilityHidden(true)
            }
            Text(current.title)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .id(current)
                .transition(.opacity)
        }
    }

    // MARK: Options

    @ViewBuilder
    private var options: some View {
        let showsShape = current.formats.count > 1
        let showsStats = current.usesStatToggle && availableStats.count > 1
        VStack(spacing: 10) {
            if showsShape {
                HStack(spacing: 8) {
                    ForEach(current.formats) { option in
                        segment(title: option.title, icon: option.icon,
                                selected: option == effectiveFormat(current)) {
                            format = option
                            cacheRender(of: current)
                        }
                    }
                }
            }
            if showsStats {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(availableStats) { kind in
                            statChip(kind)
                        }
                    }
                }
            }
            if effectiveFormat(current) == .sticker {
                // "Sticker" names a FILE property (a see-through edge) no
                // preview can show — so the sheet says what it does.
                Text(MADStoryFormat.sticker.explainer)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func statChip(_ kind: ShareStatKind) -> some View {
        let on = statKinds.contains(kind)
        return Button {
            if on {
                // Never an empty rail: the last one stays.
                guard statKinds.count > 1 else { return }
                statKinds.removeAll { $0 == kind }
            } else {
                statKinds.append(kind)
            }
            MADHaptics.tap()
            cacheRender(of: current)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: on ? "checkmark" : "plus")
                    .font(.system(size: 10, weight: .black))
                    .accessibilityHidden(true)
                Text(kind.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundColor(on ? .white : .white.opacity(0.55))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule().fill(on ? Color.white.opacity(0.18) : Color.clear))
            .overlay(Capsule().strokeBorder(Color.white.opacity(on ? 0.28 : 0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(kind.title) \(on ? "shown" : "hidden")")
    }

    private func segment(title: String, icon: String, selected: Bool,
                         action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86)) { action() }
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
            .padding(.vertical, 9)
            .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.1)))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Destinations

    private var destinationButtons: [ShareDestination] {
        var out: [ShareDestination] = [.instagramFeed]
        if MessageComposeSheet.canSend { out.append(.messages) }
        out.append(.save)
        if link != nil { out.append(.copyLink) }
        out.append(.more)
        return out
    }

    private var destinations: some View {
        VStack(spacing: 14) {
            Button(action: shareToInstagramStories) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.square.on.square")
                        .font(.system(size: 15, weight: .bold))
                        .accessibilityHidden(true)
                    Text("Instagram Stories")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color(red: 0.51, green: 0.23, blue: 0.71),
                                     Color(red: 0.87, green: 0.20, blue: 0.47),
                                     Color(red: 0.97, green: 0.52, blue: 0.20)],
                            startPoint: .leading, endPoint: .trailing))
                )
            }
            .buttonStyle(.plain)
            .disabled(busy)

            HStack(alignment: .top, spacing: 0) {
                ForEach(destinationButtons) { destination in
                    Button {
                        perform(destination)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: destination.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 50, height: 50)
                                .background(Circle().fill(Color.white.opacity(0.1)))
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                            Text(destination.title)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }
            }
        }
    }

    // MARK: Doing the thing

    private var statKey: String { statKinds.map(\.rawValue).joined(separator: ",") }

    private func cacheKey(_ template: ShareTemplate, format: MADStoryFormat) -> String {
        "\(template.rawValue)|\(format.rawValue)|\(statKey)|\(assetsVersion)"
    }

    /// The image for the focused card, from the cache when it's current.
    private func renderCurrent() -> UIImage? {
        let pageFormat = effectiveFormat(current)
        let key = cacheKey(current, format: pageFormat)
        if let cached = renderCache[key] { return cached }
        let image = ShareCardView.render(template: current, content: cardContent,
                                         format: pageFormat, stats: statKinds)
        if let image { renderCache[key] = image }
        return image
    }

    /// Render a page once it has SETTLED as the focus, so a far-away page can
    /// later show its picture instead of a live view. Deferred a beat: a
    /// fling past six cards must not bake six of them.
    private func cacheRender(of template: ShareTemplate) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard selection == template else { return }
            let pageFormat = effectiveFormat(template)
            let key = cacheKey(template, format: pageFormat)
            guard renderCache[key] == nil else { return }
            if let image = ShareCardView.render(template: template, content: cardContent,
                                                format: pageFormat, stats: statKinds) {
                renderCache[key] = image
            }
        }
    }

    private func recordShare(_ destinationKey: String) {
        TelemetryService.record(destinationKey)
        TelemetryService.record(current.family.telemetryKey)
        if current.family == .week { TelemetryService.record(ShareTelemetry.weeklyRecapShared) }
    }

    private func shareToInstagramStories() {
        guard let image = renderCurrent() else { return }
        MADHaptics.action()
        recordShare(ShareTelemetry.instagram)
        if InstagramStoryShare.isAvailable {
            let payload: InstagramStoryShare.Payload = effectiveFormat(current).isTransparent
                ? .sticker(image, top: UIColor(stickerTop(current)), bottom: UIColor(stickerBottom))
                : .background(image)
            if InstagramStoryShare.share(payload) { return }
        }
        // No Meta App ID yet (or Instagram declined the open): the system share
        // sheet, where Instagram's own extension takes the image into its
        // story composer — no App ID needed, and no hunting the camera roll.
        shareItems = ShareStudioItems(items: [image])
    }

    private func perform(_ destination: ShareDestination) {
        switch destination {
        case .instagramFeed:
            guard let image = renderCurrent() else { return }
            MADHaptics.action()
            recordShare(ShareTelemetry.instagramFeed)
            // Instagram's share extension offers Feed / Story / Message.
            shareItems = ShareStudioItems(items: [image])
        case .messages:
            guard let image = renderCurrent() else { return }
            MADHaptics.action()
            recordShare(ShareTelemetry.messages)
            messageItem = ShareMessageItem(image: image)
        case .save:
            guard let image = renderCurrent() else { return }
            busy = true
            Task {
                let outcome = await SharePhotoSaver.save(image)
                busy = false
                switch outcome {
                case .saved:
                    MADHaptics.success()
                    recordShare(ShareTelemetry.saved)
                    showToast("Saved to Photos")
                case .denied:
                    showToast("Allow Photos access in Settings to save")
                case .failed:
                    showToast("Couldn't save — try More")
                }
            }
        case .copyLink:
            guard let link else { return }
            UIPasteboard.general.url = link
            MADHaptics.success()
            recordShare(ShareTelemetry.link)
            showToast("Link copied")
        case .more:
            guard let image = renderCurrent() else { return }
            recordShare(ShareTelemetry.sheet)
            // The image leads and the link rides with it: a picture is what
            // gets posted, but the link is what a friend can actually open.
            var items: [Any] = [image]
            if let link { items.append(link) }
            shareItems = ShareStudioItems(items: items)
        }
    }

    private func showToast(_ text: String) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            guard toast == text else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { toast = nil }
        }
    }

    // MARK: Assets

    private func resolveAssets() async {
        if avatarImage == nil, let key = content.avatar?.imageURL, !key.isEmpty {
            avatarImage = await RouteAvatarImageLoader.loadImage(for: key)
            if avatarImage != nil { assetsVersion += 1 }
        }
        if photoWash == nil, let photo = content.photo {
            photoWash = MADStoryCard.wash(from: photo)
            assetsVersion += 1
        }
        if mapUnderlay == nil, templates.contains(.routeMap) {
            mapUnderlay = await RouteMapSnapshot.generate(coordinates: content.coordinates,
                                                          size: MapRouteShareCard.artSize)
            if mapUnderlay != nil { assetsVersion += 1 }
        }
        cacheRender(of: current)
    }

    // MARK: Sticker gradient

    /// The gradient a sticker stands on — in the preview AND, because these
    /// two colours ride the Instagram payload, in the story it lands in.
    /// The accent taken DEEP so it reads as a ground and the sticker is the
    /// thing you see (full strength it was the loudest thing on screen).
    private func stickerTop(_ template: ShareTemplate) -> Color {
        let accent: Color = template.family == .week || template.family == .streak
            ? MADTheme.Colors.madRed : content.routeColor
        return Self.deepened(accent, amount: 0.65)
    }

    /// Near-black, a shade warm — the app's own floor.
    private var stickerBottom: Color { Color(red: 0.055, green: 0.031, blue: 0.043) }

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
}

/// `.sheet(item:)` needs identity, and `[Any]` has none.
struct ShareStudioItems: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// The feature keys the share flow reports. Mirrors the backend's
/// `TRACKED_FEATURES` allowlist (telemetryService.ts) — an off-list key is
/// dropped server-side, so these two lists must move together. A FIXED set:
/// never interpolate a template id into a key.
enum ShareTelemetry {
    static let opened = "share_opened"
    static let instagram = "share_instagram"
    static let sheet = "share_sheet"
    static let saved = "share_saved"
    static let instagramFeed = "share_instagram_feed"
    static let messages = "share_messages"
    static let link = "share_link"

    static let familyPicture = "share_family_picture"
    static let familyRoute = "share_family_route"
    static let familyStreak = "share_family_streak"
    static let familyFlamey = "share_family_flamey"
    static let familyStats = "share_family_stats"
    static let familyWeek = "share_family_week"

    static let weeklyRecapOpened = "weekly_recap_opened"
    static let weeklyRecapShared = "weekly_recap_shared"
}
