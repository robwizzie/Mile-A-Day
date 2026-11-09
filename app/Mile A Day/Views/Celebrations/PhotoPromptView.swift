import SwiftUI
import CoreLocation

/// THE photo prompt — "make it a post" — shared by the solo finale
/// (`PostRunPhotoPromptView`, a celebration) and the buddy walk's post step
/// (`BuddyPostWizardView`), so the two can never drift into two looks again:
/// a buddy walk used to get its own crew-and-routes screen that looked
/// nothing like the solo prompt.
///
/// It ASKS rather than demands (Nov 2026): the walk as friends will get it
/// on top (its privacy-trimmed route, or the snap taken out there), Flamey
/// asking in two chat bubbles whether they'd like to add a photo (with
/// today's `DailyPhotoTheme`), and the answers as buttons: camera, a photo
/// from this walk, or just the route. The camera then shows the theme and
/// the route badge (`MADCameraView.themeLabel`/`.companion`) so the shot is
/// framed knowing the route rides along.
///
/// This view owns the whole flow up to the composer (mid-run snaps, the snap
/// gallery, the library import, the composer itself with the buddy credits
/// when there is a crew) and reports ONE outcome. What a skip or a
/// story-only share MEANS — posting the route card, dismissing a celebration,
/// returning to the recap — is the caller's, which is the only thing the two
/// doors genuinely do differently.
struct PhotoPromptView: View {
    enum Outcome {
        case skipped
        case published(toFeed: Bool)
    }

    /// A buddy walk's crew: who's credited on the post, and the card that
    /// draws everyone's routes together.
    struct Crew {
        let sessionId: String
        let coauthorIds: [String]
        let coauthorNames: [String]
        /// The combined crew route card; nil (no lines yet) falls back to the
        /// stats card.
        let walkCard: AnyView?
        /// One line under the preview: who's on the post, who's still out.
        let note: String?
        /// The faces on the preview card's header — the poster first, then
        /// the crew in credit order.
        var faces: [RouteArtAvatar] = []
    }

    /// The walk this prompt is for. nil only on a buddy walk whose workout
    /// hasn't reached HealthKit yet — the composer re-resolves it at publish.
    let workoutId: String?
    let workoutType: String
    let stats: RunStatsInput
    var crew: Crew? = nil
    /// A buddy walk a friend ALREADY posted: the photo joins their card as
    /// this user's slide (`PUT /posts/:id/crew-photo`) instead of making a
    /// second post for the same walk.
    var joiningPostId: String? = nil
    var joiningAuthorName: String? = nil
    /// The quiet button. "Skip" on the solo finale, "Not now" on the buddy
    /// step (which returns to the recap rather than ending anything).
    var skipTitle: String = "Skip"
    /// One line under it saying what skipping does, when it does something.
    var skipNote: String? = nil
    /// A day with no qualifying workout has nothing to post a photo OF; the
    /// solo finale resolves itself straight away there. The buddy step is
    /// only ever opened from a recap that already checked.
    var resolvesWithoutPostingWindow: Bool = true
    /// The user reached for the camera, the library or a snap — the
    /// celebration queue must not pull the prompt out from under them.
    var onEngage: () -> Void = {}
    let onFinish: (Outcome) -> Void

    @ObservedObject private var freshWindow = FreshPostWindowManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var didAct = false
    /// Photos captured during the run via the tracking screen's camera button.
    @State private var midRunSnaps: [MidRunPhotoStash.Entry] = []
    /// Which snap the preview (and "Use this photo") is about.
    @State private var selectedSnap = 0
    /// Composer launch request — carries the tapped snap (nil = fresh camera).
    /// Item-based so the cover is always built from THIS value; the old
    /// isPresented + separate-selection pair could build the composer with a
    /// stale nil snap and wrongly launch the live camera.
    @State private var composerLaunch: ComposerLaunch?
    /// Full-screen review of the run's snaps (save / delete / pick one).
    @State private var showGallery = false
    @State private var galleryStartIndex = 0
    /// "Use this photo" chosen INSIDE the gallery — the composer presents
    /// after the gallery cover fully dismisses (two covers in one transaction
    /// race and drop, see .claude/rules/ios.md).
    @State private var pendingUse: ComposerLaunch?
    /// Import a photo taken on this walk/run from the library (time-windowed).
    @State private var showLibraryImport = false
    @State private var importError: String?

    /// The walk's real GPS trace for the preview card, when friends will
    /// actually get one (not Stealth, route maps on).
    @State private var routeCoords: [CLLocationCoordinate2D]?

    private var isWalk: Bool { workoutType == "walking" }
    private var isBuddyWalk: Bool { crew != nil || joiningPostId != nil }
    private var noun: String { isWalk ? "walk" : "run" }
    /// App-wide type language: walks blue, runs red.
    private var accent: Color { MADTheme.workoutColor(workoutType) }

    /// May a fresh shot still be taken for THIS run? Scoped to the workout so a
    /// later walk's window can't quietly re-offer the camera on an old prompt.
    private var cameraOpen: Bool {
        guard let workoutId else { return freshWindow.isCameraOpen }
        return freshWindow.isCameraOpen(forWorkout: workoutId)
    }

    /// Fun dashboard only — nil on Modern, where Flamey doesn't exist.
    private var flameyLook: FlameyLook? { FlameyFacts.look(mood: .done, detail: .compact) }

    /// The walk panel's header row. Fixed so the media can be sized from
    /// what's left; `madTypeCap` keeps the text inside it.
    private static let cardHeaderHeight: CGFloat = 52

    var body: some View {
        ZStack {
            backdrop
                // Snap review rides on the backdrop node — the composer
                // cover owns the ZStack, and two covers on one node drop one.
                .fullScreenCover(isPresented: $showGallery, onDismiss: {
                    // Refresh after deletions; a "Use this photo" choice made
                    // inside the gallery presents the composer only now, after
                    // this cover is fully gone (same-transaction covers race).
                    reloadSnaps()
                    if let launch = pendingUse {
                        pendingUse = nil
                        composerLaunch = launch
                    }
                }) {
                    SnapGalleryView(
                        title: "Your snaps",
                        initialIndex: galleryStartIndex,
                        onUse: { pendingUse = ComposerLaunch(entry: $0) },
                        onStashChanged: { reloadSnaps() }
                    )
                }

            VStack(spacing: 0) {
                // The walk itself first, as friends will get it: its route
                // (start and finish trimmed) or the snap they took out
                // there. Takes what height is left so the buttons never
                // scroll away.
                GeometryReader { geo in
                    walkPanel(in: geo.size)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .padding(.top, MADTheme.Spacing.md)
                .padding(.horizontal, MADTheme.Spacing.lg)

                if midRunSnaps.count > 1 {
                    snapPicker
                        .padding(.top, MADTheme.Spacing.sm)
                }

                flameyAsk
                    .padding(.top, MADTheme.Spacing.md)
                    .padding(.horizontal, MADTheme.Spacing.lg)

                actionBar
            }
            .madTypeCap(.madCardCap)
            // Import cover rides the content node — the backdrop owns the
            // gallery cover and the ZStack owns the composer cover; a third
            // cover on the ZStack would silently drop one (.claude/rules/ios.md).
            // Attached AFTER the type cap so the picker isn't capped with it.
            .fullScreenCover(isPresented: $showLibraryImport, onDismiss: {
                // Launch the composer only AFTER this cover is gone — a second
                // cover in the same dismiss transaction races and drops.
                if let launch = pendingUse {
                    pendingUse = nil
                    composerLaunch = launch
                }
            }) {
                WorkoutPhotoImportPicker(
                    windows: importWindows,
                    activityNoun: noun
                ) { result in
                    handleImportResult(result)
                    showLibraryImport = false
                }
            }
        }
        // Once they've reached for the camera, the library or a snap, this
        // prompt is theirs: nothing that arrives later may pull it out from
        // under them (CelebrationManager only preempts an untouched prompt).
        .onChange(of: composerLaunch != nil) { _, open in if open { onEngage() } }
        .onChange(of: showGallery) { _, open in if open { onEngage() } }
        .onChange(of: showLibraryImport) { _, open in if open { onEngage() } }
        .onAppear {
            reloadSnaps()
            // The solo prompt is the LAST celebration in the queue, so it can
            // easily outlast the 10-minute camera window. That doesn't mean
            // there's nothing to offer: the walk's own photos are still
            // postable, so the screen stays and swaps its primary button (see
            // `cameraOpen`). Only a day with no qualifying workout at all
            // resolves straight away (`resolvesWithoutPostingWindow`). Deferred
            // a tick because resolving a celebration from inside its own
            // onAppear mutates the manager mid-update.
            guard freshWindow.canPostToday || !resolvesWithoutPostingWindow else {
                DispatchQueue.main.async { skip() }
                return
            }
            // One settle-in, then still. There is deliberately no idle loop:
            // a bobbing Flamey and a breathing glow made the whole screen
            // look like it was wiggling.
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.35)) { appeared = true }
            }
        }
        .task { await loadRoutePreview() }
        .alert("Couldn't add that photo", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .fullScreenCover(item: $composerLaunch) { launch in
            PostComposerView(
                stats: stats,
                // A chosen mid-run snap goes straight onto the canvas; only a
                // fresh capture launches the camera.
                autoOpenCamera: launch.image == nil,
                initialImage: launch.image,
                initialSecondary: launch.secondary,
                initialPrimaryWasFront: launch.primaryWasFront,
                // Leaving returns to this prompt with the snaps intact —
                // "‹ Back", not "Cancel", so nobody fears losing photos.
                backNavigation: true,
                // A buddy walk's crew rides along exactly as the old wizard
                // handed it over; nil lets the composer resolve it itself.
                buddyCoauthorIds: crew?.coauthorIds ?? [],
                buddySessionId: crew?.sessionId,
                buddyCrewNames: crew?.coauthorNames
                    ?? joiningAuthorName.map { [$0] } ?? [],
                crewPhotoPostId: joiningPostId,
                cameraTheme: "\(DailyPhotoTheme.today.emoji) \(DailyPhotoTheme.today.title)",
                cameraCompanion: cameraBadge,
                cameraCompanionCaption: cameraBadgeCaption
            ) { outcome in
                composerLaunch = nil
                switch outcome {
                case .cancelled:
                    // Backed out — of the camera, the canvas or the share step.
                    // Nothing is finalized: this screen is still the decision,
                    // so they land back here to try again, pick another snap,
                    // or skip. (It used to post the route card and close when
                    // there were no snaps, so a camera opened by mistake and
                    // closed again had already published the walk.)
                    return
                case .published(let toFeed, _), .savedDraft(let toFeed, _):
                    // A draft is a post that hasn't left the phone yet — it
                    // goes out on its own, so the prompt is answered exactly
                    // as if it had (no auto card racing it to the feed).
                    guard !didAct else { return }
                    didAct = true
                    onFinish(.published(toFeed: toFeed))
                }
            }
        }
    }

    // MARK: - Background

    private var backdrop: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.04, blue: 0.09), .black],
                           startPoint: .top, endPoint: .bottom)
            // A soft glow in the activity colour behind the post.
            RadialGradient(colors: [accent.opacity(0.38), .clear],
                           center: .init(x: 0.5, y: 0.42),
                           startRadius: 10, endRadius: 360)
        }
        .ignoresSafeArea()
    }

    // MARK: - The ask

    /// Flamey ASKS, after the walk, instead of the screen demanding a photo:
    /// two short chat bubbles (well done + would you like to add one, with
    /// today's theme), answered by the buttons under them. It replaced a
    /// badge row, a two-line headline, a grey theme sentence, a post mock-up
    /// with a viewfinder, a tilted map tile and a who-sees-it footer, all at
    /// once, before anyone had said whether they even wanted to post.
    private var flameyAsk: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if let look = flameyLook {
                FlameyDressedFigure(look: look, health: .healthy, size: 46, scale: 1, mood: .done)
                    .frame(width: 46, height: 46)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                bubble {
                    Text(greeting)
                        .madFont(size: 16, weight: .bold, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white)
                        .madBodyLines(3)
                }
                if joiningPostId == nil { promptBubble }
            }
            Spacer(minLength: 0)
        }
        .opacity(appeared ? 1 : 0)
        .accessibilityElement(children: .combine)
    }

    private func bubble<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 18, bottomLeadingRadius: 6,
                    bottomTrailingRadius: 18, topTrailingRadius: 18,
                    style: .continuous)
                .fill(Color.white.opacity(0.09))
            )
    }

    /// Bubble one: well done, then the question, in one short line.
    private var greeting: String {
        if !midRunSnaps.isEmpty {
            return midRunSnaps.count == 1
                ? "Nice \(noun)! Want to post the photo you took?"
                : "Nice \(noun)! Want to post one of your \(midRunSnaps.count) photos?"
        }
        if let author = joiningAuthorName, joiningPostId != nil {
            return "\(author) posted your \(noun). Add your photo to it?"
        }
        if crew != nil { return crew?.note ?? "Nice \(noun), crew! Want to add a photo?" }
        if let streak = stats.streak, streak > 0 {
            return "Day \(streak) done! 🔥 Want to add a photo?"
        }
        return "Nice \(noun)! 🔥 Want to add a photo?"
    }

    /// Bubble two: today's prompt (`DailyPhotoTheme`, the same one the home
    /// page's card shows) as an idea, never a rule: the quieter line under
    /// it says anything goes.
    private var promptBubble: some View {
        let theme = DailyPhotoTheme.today
        return bubble {
            VStack(alignment: .leading, spacing: 3) {
                (Text("Today's prompt: ")
                    + Text("\(theme.title) \(theme.emoji)")
                        .foregroundColor(Color(red: 1, green: 0.66, blue: 0.3)))
                    .madFont(size: 16, weight: .bold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white)
                    .madBodyLines(2)
                Text("Or post anything you like.")
                    .madFont(size: 13, weight: .semibold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.6))
                    .madBodyLines(2)
            }
        }
    }

    // MARK: - The walk panel

    /// The walk as friends get it: a header (you / the crew / the post
    /// you're joining) over its route art (privacy-trimmed, the same line
    /// friends see) or, once there are snaps, the chosen snap.
    private func walkPanel(in available: CGSize) -> some View {
        // Up to the post's own 4:5, then centred in what's left.
        let mediaHeight = max(120, min(available.height - Self.cardHeaderHeight - 8, (available.width - 16) * 1.25))
        let mediaSize = CGSize(width: available.width - 16, height: mediaHeight)
        return VStack(spacing: 0) {
            cardHeader
                .frame(height: Self.cardHeaderHeight)
            Group {
                if let entry = selectedSnapEntry {
                    snapPreview(entry, size: mediaSize)
                } else {
                    walkCard
                        .frame(width: mediaSize.width, height: mediaSize.height)
                        // RouteArtView keeps the map it first drew, so a
                        // panel that settles to a new size would crop the
                        // line (seen on a 320pt phone): redraw per size.
                        .id("\(Int(mediaSize.width))x\(Int(mediaSize.height))")
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .frame(maxHeight: .infinity, alignment: .center)
        .opacity(appeared ? 1 : 0)
    }

    /// Said on the map so nobody wonders whether friends see where they
    /// live: the drawn line is `RoutePrivacyTrim.friendsView`, ends removed.
    @ViewBuilder
    private var trimmedChip: some View {
        if crew == nil, let coords = routeCoords, coords.count >= 2 {
            HStack(spacing: 4) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 10, weight: .bold))
                    .accessibilityHidden(true)
                Text("Ends hidden")
                    .madFont(size: 12, weight: .bold, design: .rounded, maxScale: 1.2)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.1)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your start and finish are hidden from friends")
        }
    }

    /// The walk's route as a square thumbnail for the camera's top-right
    /// corner and its prompt card (`MADCameraView.companion`); the caption
    /// under it on the card is `cameraBadgeCaption`.
    private var cameraBadge: AnyView {
        let scale: CGFloat = 0.4
        return AnyView(
            walkCard
                .frame(width: 140, height: 175)
                .scaleEffect(scale)
                .frame(width: 140 * scale, height: 175 * scale)
        )
    }

    private var cameraBadgeCaption: String {
        let distance = stats.distance > 0 ? stats.distance.distanceFormatted : (isWalk ? "Walk" : "Run")
        guard crew == nil, routeCoords != nil else { return distance }
        return "\(distance) · start and finish hidden"
    }

    // MARK: Card header — who it's from

    private var cardHeader: some View {
        HStack(spacing: 10) {
            headerAvatars
            VStack(alignment: .leading, spacing: 1) {
                Text(cardTitle)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(cardMeta)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            // On the header, never on the map, where it covered the line's
            // end marker on small phones.
            trimmedChip
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }

    /// The people on the card: you, or you and your crew overlapped.
    @ViewBuilder
    private var headerAvatars: some View {
        if let author = joiningAuthorName, joiningPostId != nil {
            AvatarView(name: author, imageURL: nil, size: 30)
        } else if let faces = crew?.faces, faces.count > 1 {
            HStack(spacing: -10) {
                ForEach(Array(faces.prefix(3).enumerated()), id: \.offset) { _, face in
                    AvatarView(name: face.name, imageURL: face.imageURL, size: 30)
                        .overlay(Circle().strokeBorder(Color.black, lineWidth: 2))
                }
            }
        } else {
            AvatarView(name: me.name, imageURL: me.profileImageUrl, size: 30)
        }
    }

    private var me: User { UserManager.shared.currentUser }

    private var cardTitle: String {
        if joiningPostId != nil {
            return joiningAuthorName.map { "\($0)'s post" } ?? "The walk's post"
        }
        if let crew {
            let others = crew.coauthorNames
            switch others.count {
            case 0: return me.name
            case 1: return "You & \(others[0])"
            case 2: return "You, \(others[0]) & \(others[1])"
            default: return "You, \(others[0]) + \(others.count - 1) more"
            }
        }
        return me.name
    }

    /// "Walk · 1.24 mi" — short enough to sit beside the "Ends hidden" tag
    /// on a 320pt phone.
    private var cardMeta: String {
        if joiningPostId != nil { return "Your photo becomes a slide on it" }
        let kind = isBuddyWalk
            ? (isWalk ? "Buddy walk" : "Buddy run")
            : (isWalk ? "Walk" : "Run")
        guard stats.distance > 0 else { return kind }
        return "\(kind) · \(stats.distance.distanceFormatted)"
    }

    // MARK: Card media — the hole their photo goes in

    /// A mid-run snap, in the post's own frame. Tapping it opens the full
    /// review (save / delete / pick); the primary button posts it.
    private func snapPreview(_ entry: MidRunPhotoStash.Entry, size: CGSize) -> some View {
        Button {
            MADHaptics.tap()
            galleryStartIndex = selectedSnap
            showGallery = true
        } label: {
            // Drawn as ONE photo, second frame inset — a front-and-back snap
            // that looks like an ordinary picture until it's published is a
            // surprise on the card, not a feature.
            DualPhotoFill(big: entry.image, small: entry.secondary)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text("Review")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .padding(10)
                }
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(ScaleButtonStyle())
        .id(entry.id)
        .transition(.opacity)
        .accessibilityLabel("Your photo")
        .accessibilityHint("Opens it full screen to review, save or delete")
    }

    // MARK: Mid-run snap picker

    private var selectedSnapEntry: MidRunPhotoStash.Entry? {
        guard midRunSnaps.indices.contains(selectedSnap) else { return midRunSnaps.first }
        return midRunSnaps[selectedSnap]
    }

    /// Two or more snaps: thumbnails under the card choose which one the
    /// preview (and the primary button) is about. Centred while they fit;
    /// a LAZY scroll once they don't — nothing caps how many there can be,
    /// and an eager stack decodes every one. Same thumbnails either way.
    private var snapPicker: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { snapThumbs }
                .padding(.horizontal, MADTheme.Spacing.lg)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) { snapThumbs }
                    .padding(.horizontal, MADTheme.Spacing.lg)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(height: 63)
    }

    private var snapThumbs: some View {
        ForEach(Array(midRunSnaps.enumerated()), id: \.element.id) { index, entry in
            snapThumb(index: index, entry: entry)
        }
    }

    private func snapThumb(index: Int, entry: MidRunPhotoStash.Entry) -> some View {
        let selected = index == selectedSnap
        return Button {
            MADHaptics.tap()
            withAnimation(.easeInOut(duration: 0.2)) { selectedSnap = index }
        } label: {
            Image(uiImage: entry.image)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 55)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(2)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(selected ? accent : Color.white.opacity(0.15),
                                      lineWidth: 2)
                )
                .opacity(selected ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Photo \(index + 1) of \(midRunSnaps.count)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - The walk's card

    /// The walk side of the post: its real route art with the feed's stats
    /// band when friends will get a route, else a stats card.
    @ViewBuilder
    private var walkCard: some View {
        if let crewCard = crew?.walkCard {
            crewCard
        } else if let coords = routeCoords, coords.count >= 2 {
            RouteArtView(
                coordinates: coords,
                routeColor: accent,
                authorAvatar: RouteArtAvatar(name: me.name, imageURL: me.profileImageUrl),
                showsMileMarkers: false
            )
        } else {
            statsCard
        }
    }

    /// Routeless walks (and the moment before the route loads).
    private var statsCard: some View {
        ZStack {
            LinearGradient(colors: [accent, accent.opacity(0.35), Color.black],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 2) {
                Image(systemName: isWalk ? "figure.walk" : "figure.run")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                Text(stats.distance.distanceText)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundColor(.white)
            }
            .padding(12)
            .offset(y: -10)
        }
    }

    // MARK: - Actions

    private enum PromptAction: Hashable {
        case useSnap, camera, library
    }

    /// First available of: post the chosen snap, take a photo, pick one from
    /// the walk. Everything after the first is a secondary button.
    private var actions: [PromptAction] {
        var out: [PromptAction] = []
        if selectedSnapEntry != nil { out.append(.useSnap) }
        if cameraOpen { out.append(.camera) }
        out.append(.library)
        return out
    }

    private func perform(_ action: PromptAction) {
        switch action {
        case .useSnap:
            if let entry = selectedSnapEntry { composerLaunch = ComposerLaunch(entry: entry) }
        case .camera:
            composerLaunch = ComposerLaunch(image: nil)
        case .library:
            showLibraryImport = true
        }
    }

    private func title(_ action: PromptAction, primary: Bool) -> String {
        switch action {
        case .useSnap: return midRunSnaps.count > 1 ? "Post this one" : "Yes, post it"
        case .camera: return primary ? "Yes, open the camera" : "New photo"
        case .library:
            return primary ? "Pick a photo from this \(noun)" : "Use a \(noun) photo"
        }
    }

    private func icon(_ action: PromptAction) -> String {
        switch action {
        case .useSnap: return "checkmark.circle.fill"
        case .camera: return "camera.fill"
        case .library: return "photo.on.rectangle.angled"
        }
    }

    private var actionBar: some View {
        let all = actions
        let primary = all[0]
        let rest = Array(all.dropFirst())
        // One secondary answer sits beside "just the route"; two (a snap,
        // a new photo AND the library) take the row and the skip drops
        // under it as text.
        let skipInRow = rest.count <= 1
        return VStack(spacing: 10) {
            Button {
                MADHaptics.action()
                perform(primary)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon(primary))
                        .font(.system(size: 17, weight: .bold))
                        .accessibilityHidden(true)
                    Text(title(primary, primary: true))
                        .madFont(size: 17, weight: .heavy, design: .rounded, maxScale: 1.3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Capsule().fill(MADTheme.Colors.madRed))
                .contentShape(Capsule())
            }
            .buttonStyle(ScaleButtonStyle())

            HStack(spacing: 10) {
                ForEach(rest, id: \.self) { action in
                    secondaryButton(title(action, primary: false)) {
                        MADHaptics.tap()
                        perform(action)
                    }
                }
                if skipInRow {
                    secondaryButton(skipTitle) { skip() }
                }
            }

            if !skipInRow {
                Button { skip() } label: {
                    Text(skipTitle)
                        .madFont(size: 15, weight: .semibold, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white.opacity(0.65))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // What skipping does, when the caller has something to say.
            if let skipNote {
                Text(skipNote)
                    .madFont(size: 12, weight: .medium, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .madBodyLines(2)
            }
        }
        .padding(.horizontal, MADTheme.Spacing.lg)
        .padding(.top, MADTheme.Spacing.md)
        .padding(.bottom, MADTheme.Spacing.xs)
        .opacity(appeared ? 1 : 0)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .madFont(size: 15, weight: .bold, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Capsule().fill(Color.white.opacity(0.09)))
                .contentShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private func reloadSnaps() {
        midRunSnaps = MidRunPhotoStash.entries()
        if !midRunSnaps.indices.contains(selectedSnap) { selectedSnap = 0 }
    }

    // MARK: - Route preview

    /// The route friends will actually get — none for a Stealth walk (the
    /// server never stores one) or when route maps are switched off, so the
    /// preview can't promise a map the post won't have.
    private func loadRoutePreview() async {
        guard crew == nil, routeCoords == nil,
              NotificationPreferences.load().shareRouteMaps,
              let workoutId,
              let workout = HealthKitManager.shared.todaysWorkouts
                .first(where: { $0.uuid.uuidString == workoutId }),
              !StealthModeStore.shared.isStealth(workout) else { return }
        let full = await WorkoutSyncService.shared.uploadableRoute(for: workout)
        guard let line = RoutePrivacyTrim.friendsView(full, workoutId: workoutId) else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            routeCoords = line
        }
    }

    // MARK: - Library import (photo taken on this walk/run)

    /// Accepted capture-time window from the workout's own start/end (HealthKit),
    /// with grace on both ends: a shot at the trailhead just before starting,
    /// or right after finishing before this prompt appeared, both count.
    ///
    /// When the just-finished workout hasn't synced into `todaysWorkouts` yet
    /// (async fetch / Watch lag), we do NOT fall back to the whole day — that
    /// would let an unrelated earlier photo pass. Instead we bound to a
    /// generous recent window (a daily mile is minutes; even a long hike fits
    /// 3h), so authenticity holds even without the exact workout.
    ///
    /// A mile walked in several goes accepts a photo from ANY of its legs
    /// (`RunPostService.photoWindows`) — the post is all of them.
    private var importWindows: [ClosedRange<Date>] {
        let now = Date()
        guard let workoutId,
              let windows = RunPostService.photoWindows(forWorkoutId: workoutId) else {
            return [now.addingTimeInterval(-3 * 60 * 60)...now.addingTimeInterval(2 * 60)]
        }
        return windows
    }

    private func handleImportResult(_ result: WorkoutPhotoImportResult) {
        switch result {
        case .accepted(let image):
            // Deferred to the import cover's onDismiss (composer is a second
            // cover — presenting it now would race this one's dismissal).
            pendingUse = ComposerLaunch(image: image)
        case .acceptedPair(let primary, let secondary, let primaryWasFront):
            pendingUse = ComposerLaunch(
                image: primary, secondary: secondary, primaryWasFront: primaryWasFront)
        case .failed:
            importError = "Couldn't load that photo. Try another one."
        case .cancelled:
            break
        }
    }

    private func skip() {
        guard !didAct else { return }
        didAct = true
        onFinish(.skipped)
    }
}

/// Identifiable wrapper for launching the composer, so the fullScreenCover is
/// built from the exact tapped value instead of separately-tracked state.
private struct ComposerLaunch: Identifiable {
    let id = UUID()
    /// The chosen mid-run snap; nil means open the live camera for a fresh shot.
    let image: UIImage?
    /// The other lens, when the chosen snap was a FRONT & BACK press. Carried
    /// all the way to the composer or the pair is lost between the gallery
    /// and the canvas — the post would publish whichever frame was showing
    /// and silently drop the other.
    let secondary: UIImage?
    let primaryWasFront: Bool

    init(image: UIImage?, secondary: UIImage? = nil, primaryWasFront: Bool = false) {
        self.image = image
        self.secondary = secondary
        self.primaryWasFront = primaryWasFront
    }

    /// Reads the ORIGINAL off disk, not the entry's display copy: `entries()`
    /// decodes at a thumbnail size so an uncapped walk's worth of snaps can
    /// be listed, and that is exactly the resolution a post must not inherit.
    /// Falls back to what's in hand if the file can't be re-read.
    init(entry: MidRunPhotoStash.Entry) {
        let full = MidRunPhotoStash.fullImage(for: entry)
        self.image = full?.primary ?? entry.image
        self.secondary = full?.secondary ?? entry.secondary
        self.primaryWasFront = entry.primaryWasFront
    }
}
