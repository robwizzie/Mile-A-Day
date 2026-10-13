import SwiftUI
import CoreLocation

/// THE photo prompt — "make it a post" — shared by the solo finale
/// (`PostRunPhotoPromptView`, a celebration) and the buddy walk's post step
/// (`BuddyPostWizardView`), so the two can never drift into two looks again:
/// a buddy walk used to get its own crew-and-routes screen that looked
/// nothing like the solo prompt.
///
/// The hero is a preview of the POST ITSELF, as friends will get it: who
/// it's from (you, or you and the crew), a camera viewfinder where the photo
/// goes with the walk's map tucked in its corner, and who sees it — friends,
/// once they've done their own mile. It replaced two small cards and a "+",
/// which explained the idea and never showed the thing being made. Mid-run
/// snaps drop straight into that frame. A sparkle burst marks the moment as
/// a reward; on the Fun dashboard the user's own Flamey peeks over the card.
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
    /// Drives the idle float/pulse. Started on the NEXT turn after appear and
    /// reset without animation on disappear (a `repeatForever` attached to the
    /// first commit leaks into every later layout change — ios.md).
    @State private var floating = false
    /// The one-shot sparkle burst off the card as it lands.
    @State private var burst = false
    @State private var didAct = false
    /// Photos captured during the run via the tracking screen's camera button.
    @State private var midRunSnaps: [MidRunPhotoStash.Entry] = []
    /// Which snap the preview (and "Use this photo") is about.
    @State private var selectedSnap = 0
    /// Only for the card's "who sees it" line — a throwaway instance, since
    /// the Friends tab's own may not exist yet (ios.md).
    @StateObject private var friendService = FriendService()
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

    /// The preview card's two fixed-height rows. Fixed so the photo area can
    /// be sized EXACTLY from what's left (a 4:5 frame, like the post), rather
    /// than predicted; `madTypeCap` keeps the text inside them.
    private static let cardHeaderHeight: CGFloat = 52
    private static let cardFooterHeight: CGFloat = 40

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
                header
                    .padding(.top, MADTheme.Spacing.md)
                    .padding(.horizontal, MADTheme.Spacing.lg)

                // The preview takes whatever height is left, so the post's
                // own 4:5 frame is as big as this phone allows and the
                // buttons never scroll away.
                GeometryReader { geo in
                    heroCard(in: geo.size)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .padding(.top, MADTheme.Spacing.md)
                .padding(.horizontal, MADTheme.Spacing.lg)

                if midRunSnaps.count > 1 {
                    snapPicker
                        .padding(.top, MADTheme.Spacing.sm)
                }

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
                    window: importWindow,
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
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { appeared = true }
            guard !reduceMotion else { return }
            // Loops and the one-shot burst start on the NEXT turn, inside
            // their own transactions (ios.md: a repeatForever attached to the
            // first commit leaks into every later layout change).
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.9).delay(0.15)) { burst = true }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    floating = true
                }
            }
        }
        .onDisappear {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { floating = false }
        }
        .task { await loadRoutePreview() }
        .task { try? await friendService.loadFriends() }
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
                crewPhotoPostId: joiningPostId
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
                case .published(let toFeed, _):
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
                .scaleEffect(floating ? 1.05 : 0.97)
        }
        .ignoresSafeArea()
    }

    // MARK: - Header

    /// The reward first ("WALK DONE · DAY 42"), then ONE line of what this
    /// screen is for. It used to be an eyebrow, a headline, a two-clause
    /// subheadline, a crew note, a countdown and its caption — six lines of
    /// grey before anyone saw what they were being asked to make.
    private var header: some View {
        VStack(spacing: 8) {
            achievementPill
                .scaleEffect(appeared ? 1 : 0.7)

            Text(headline)
                .madFont(size: 28, weight: .black, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text(subheadline)
                .madFont(size: 14, weight: .medium, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -8)
    }

    /// ✓ WALK DONE · 🔥 DAY 42 — the thing they just earned, said before the
    /// thing we're asking for.
    private var achievementPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .black))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(accent))
            Text(doneLabel)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundColor(.white)
                .lineLimit(1)
                .fixedSize()
            if let streak = stats.streak, streak > 0 {
                Text("·")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white.opacity(0.5))
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("DAY \(streak)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundColor(.orange)
            }
        }
        .padding(.leading, 5)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(Color.white.opacity(0.1))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(achievementSpoken)
    }

    private var doneLabel: String {
        isBuddyWalk
            ? (isWalk ? "BUDDY WALK" : "BUDDY RUN")
            : (isWalk ? "WALK DONE" : "RUN DONE")
    }

    private var achievementSpoken: String {
        let done = isBuddyWalk
            ? "Buddy \(noun) done"
            : "\(noun.capitalized) done"
        guard let streak = stats.streak, streak > 0 else { return done }
        return "\(done), day \(streak) of your streak"
    }

    private var headline: String {
        if !midRunSnaps.isEmpty {
            return midRunSnaps.count == 1 ? "Great shot. Post it?" : "Pick your best shot"
        }
        if joiningPostId != nil { return "Add your shot" }
        if crew != nil { return cameraOpen ? "Snap the crew" : "Add a photo of the crew" }
        return cameraOpen ? "Snap your \(noun)" : "Add a photo from your \(noun)"
    }

    private var subheadline: String {
        if !midRunSnaps.isEmpty {
            return midRunSnaps.count == 1
                ? "You took this one out there."
                : "You took \(midRunSnaps.count) photos out there — tap one to preview it."
        }
        if joiningPostId != nil {
            let whose = joiningAuthorName.map { "\($0)'s post" } ?? "the walk's post"
            return "It joins \(whose) as your slide — one card, everyone's photos."
        }
        if let note = crew?.note { return note }
        if crew != nil { return "One post for the whole walk, with everyone's routes on it." }
        return cameraOpen
            ? "Your photo leads the post. Your route and stats ride along."
            : "Any photo you took on this \(noun) can still go up today."
    }

    // MARK: - Hero: the post, as friends will see it

    /// A preview of the actual feed card — who it's from, the photo frame
    /// it's waiting for, and who'll see it — rather than a diagram of two
    /// small cards and a "+". What people didn't get was what they were
    /// making; this is that thing, with a hole where their photo goes.
    private func heroCard(in available: CGSize) -> some View {
        let chrome = Self.cardHeaderHeight + Self.cardFooterHeight
        // The photo area: 4:5 like the post, as big as the space allows,
        // never wider than a comfortable card on a Plus/Max phone.
        let mediaWidth = max(150, min(available.width - 16, (available.height - chrome) * 0.8, 300))
        let mediaSize = CGSize(width: mediaWidth, height: mediaWidth * 1.25)

        return VStack(spacing: 0) {
            cardHeader
                .frame(height: Self.cardHeaderHeight)
            media(size: mediaSize)
                .padding(.horizontal, 8)
            cardFooter
                .frame(height: Self.cardFooterHeight)
        }
        .frame(width: mediaSize.width + 16)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.11), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 24, y: 14)
        .shadow(color: accent.opacity(0.25), radius: 30)
        .overlay { sparkleBurst.allowsHitTesting(false) }
        // Fun dashboard: their Flamey peeks over the card's top edge, beside
        // the header's empty right side — never over the photo or the text.
        .overlay(alignment: .topTrailing) {
            if let look = flameyLook {
                FlameyDressedFigure(look: look, health: .healthy, size: 54, scale: 1, mood: .done)
                    .frame(width: 54, height: 54)
                    .offset(x: 10, y: -24 + (floating ? -3 : 0))
                    .opacity(appeared ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
        .scaleEffect(appeared ? 1 : 0.9)
        .opacity(appeared ? 1 : 0)
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
            Spacer(minLength: 0)
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

    /// "Walk · 1.24 mi · now" — the feed header's own subtitle shape.
    private var cardMeta: String {
        if joiningPostId != nil { return "Your photo becomes a slide on it" }
        let kind = isBuddyWalk
            ? (isWalk ? "Buddy walk" : "Buddy run")
            : (isWalk ? "Walk" : "Run")
        guard stats.distance > 0 else { return "\(kind) · now" }
        return "\(kind) · \(stats.distance.distanceFormatted) · now"
    }

    // MARK: Card media — the hole their photo goes in

    @ViewBuilder
    private func media(size: CGSize) -> some View {
        if let entry = selectedSnapEntry {
            snapPreview(entry, size: size)
        } else {
            viewfinder(size: size)
        }
    }

    /// An empty frame that's obviously a camera: corner brackets, a shutter,
    /// the clock for the camera window, and the walk's map tucked in the
    /// corner with a "+" — the photo and the map become one post.
    private func viewfinder(size: CGSize) -> some View {
        Button {
            MADHaptics.action()
            openPrimaryAction()
        } label: {
            ZStack {
                LinearGradient(
                    colors: [accent.opacity(0.22), Color(white: 0.07), Color(white: 0.04)],
                    startPoint: .top, endPoint: .bottom)

                ViewfinderBrackets()
                    .stroke(Color.white.opacity(0.85),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .padding(14)

                VStack(spacing: 12) {
                    shutterGlyph(diameter: size.width < 220 ? 72 : 86)
                    VStack(spacing: 3) {
                        Text(cameraOpen ? "Tap to snap" : "Pick a photo")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        if cameraOpen, size.height > 260 {
                            Text("or choose one from this \(noun)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
                .offset(y: -6)
            }
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .top) {
                if cameraOpen { cameraClock.padding(.top, 12) }
            }
            .overlay(alignment: .bottomTrailing) { mapTuck }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(cameraOpen ? "Take a photo" : "Choose a photo from this \(noun)")
        .accessibilityHint("Your photo leads the post, with your route and stats on it")
    }

    private func shutterGlyph(diameter: CGFloat) -> some View {
        ZStack {
            // The breathing halo: transform + opacity only, off under
            // Reduce Motion (`floating` never starts there).
            Circle()
                .stroke(accent.opacity(0.7), lineWidth: 2)
                .frame(width: diameter, height: diameter)
                .scaleEffect(floating ? 1.3 : 1)
                .opacity(floating ? 0 : 0.9)
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: diameter + 18, height: diameter + 18)
            Circle()
                .strokeBorder(Color.white, lineWidth: 4)
                .frame(width: diameter, height: diameter)
            Circle()
                .fill(LinearGradient(colors: [accent.opacity(0.85), accent],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: diameter - 18, height: diameter - 18)
            Image(systemName: cameraOpen ? "camera.fill" : "photo.on.rectangle.angled")
                .font(.system(size: diameter * 0.3, weight: .bold))
                .foregroundColor(.white)
        }
        .accessibilityHidden(true)
    }

    /// "Camera open · 9:41". A deadline for SHOOTING, not for sharing — the
    /// library stays open all day, and the secondary button says so.
    private var cameraClock: some View {
        HStack(spacing: 5) {
            Image(systemName: "camera.fill")
                .font(.system(size: 10, weight: .bold))
                .accessibilityHidden(true)
            Text("Camera open ·")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .lineLimit(1)
                .fixedSize()
            Text(
                timerInterval: (freshWindow.windowOpenedAt ?? Date())...freshWindow.windowEndDate,
                countsDown: true
            )
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .monospacedDigit()
            // A lighter cut of the activity colour, legible on the dark chip.
            .foregroundColor(isWalk
                ? Color(red: 0.6, green: 0.8, blue: 1)
                : Color(red: 1, green: 0.55, blue: 0.68))
            .lineLimit(1)
            .fixedSize()
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(Color.black.opacity(0.55))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Camera open for a few more minutes")
    }

    /// The walk's own card, small and tilted in the frame's corner, with a
    /// "+": the photo leads, the map is the post's second face. Rendered at
    /// the old preview size and scaled down so the route art lays out as it
    /// was designed to.
    private var mapTuck: some View {
        let full = CGSize(width: 140, height: 175)
        let scale: CGFloat = 0.46
        return ZStack(alignment: .bottom) {
            walkCard
                .frame(width: full.width, height: full.height)
                .scaleEffect(scale)
                .frame(width: full.width * scale, height: full.height * scale)
            Text(isBuddyWalk ? "ROUTES" : "MAP")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(0.6)
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .padding(.bottom, 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white, lineWidth: 2)
        )
        .overlay(alignment: .topLeading) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .black))
                .foregroundColor(.black)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white))
                .offset(x: -9, y: -9)
        }
        .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
        .rotationEffect(.degrees(appeared ? 6 : 0))
        .padding(14)
        .accessibilityHidden(true)
    }

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

    // MARK: Card footer — who sees it

    /// Who this reaches, said on the card itself. "Will my whole friends list
    /// see this?" and "why can't Sam see my photo?" had no answer anywhere
    /// before the share step; the earn-to-view rule (photos unlock once the
    /// viewer has done their own mile) is the second half of that answer.
    private var cardFooter: some View {
        HStack(spacing: 8) {
            friendFaces
            Text(audienceText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            HStack(spacing: 3) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("after their mile")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundColor(.white.opacity(0.45))
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(audienceText). They see the photo once they've done their own mile today.")
    }

    @ViewBuilder
    private var friendFaces: some View {
        let friends = Array(friendService.friends.prefix(3))
        if friends.isEmpty {
            Image(systemName: "person.2.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
        } else {
            HStack(spacing: -7) {
                ForEach(friends, id: \.user_id) { friend in
                    AvatarView(name: friend.username ?? "?",
                               imageURL: friend.profile_image_url, size: 20)
                        .overlay(Circle().strokeBorder(Color.black, lineWidth: 1.5))
                }
            }
        }
    }

    private var audienceText: String {
        if isBuddyWalk { return "Your friends and the crew's" }
        let count = friendService.friends.count
        switch count {
        case 0: return "For your friends"
        case 1: return "For your 1 friend"
        default: return "For your \(count) friends"
        }
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

    // MARK: - Celebration sparkle

    /// One small burst off the card as it lands — the moment reads as a
    /// reward, not a form. One-shot, transform + opacity, nothing under
    /// Reduce Motion (`burst` never flips there).
    private var sparkleBurst: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { i in
                let angle = CGFloat(i) / 10 * 2 * .pi + 0.3
                let reach: CGFloat = i.isMultiple(of: 2) ? 150 : 115
                Image(systemName: i.isMultiple(of: 3) ? "sparkle" : "circle.fill")
                    .font(.system(size: i.isMultiple(of: 3) ? 14 : 5, weight: .bold))
                    .foregroundColor(i.isMultiple(of: 2) ? .white : accent)
                    .offset(x: burst ? cos(angle) * reach : 0,
                            y: burst ? sin(angle) * reach * 1.2 : 0)
                    .scaleEffect(burst ? 1 : 0.01)
                    .opacity(burst ? 0 : 1)
            }
        }
        .opacity(appeared && !reduceMotion ? 1 : 0)
        .accessibilityHidden(true)
    }

    // MARK: - The walk's card (inside the map tuck)

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
        case .useSnap: return "Use this photo"
        case .camera: return primary || selectedSnapEntry == nil ? "Take a photo" : "New photo"
        case .library:
            if primary { return "Choose from this \(noun)" }
            return selectedSnapEntry == nil ? "Choose from this \(noun)" : "From library"
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
        return VStack(spacing: 10) {
            Button {
                MADHaptics.action()
                perform(primary)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon(primary))
                        .font(.system(size: 17, weight: .bold))
                    Text(title(primary, primary: true))
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    Capsule().fill(LinearGradient(
                        colors: [accent, accent.opacity(0.78)],
                        startPoint: .leading, endPoint: .trailing))
                )
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .shadow(color: accent.opacity(0.45), radius: 16, y: 6)
                .contentShape(Capsule())
            }
            .buttonStyle(ScaleButtonStyle())

            if !rest.isEmpty {
                HStack(spacing: 10) {
                    ForEach(rest, id: \.self) { action in
                        Button {
                            MADHaptics.tap()
                            perform(action)
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: icon(action))
                                    .font(.system(size: 14, weight: .semibold))
                                Text(title(action, primary: false))
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .foregroundColor(.white.opacity(0.92))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(
                                Capsule().fill(Color.white.opacity(0.09))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.13), lineWidth: 1))
                            )
                            .contentShape(Capsule())
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
            }

            Button { skip() } label: {
                VStack(spacing: 2) {
                    Text(skipTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                    // What skipping does, when it does something — said
                    // quietly here so it's never a surprise later.
                    if let skipNote {
                        Text(skipNote)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, MADTheme.Spacing.lg)
        .padding(.top, MADTheme.Spacing.md)
        .padding(.bottom, MADTheme.Spacing.xs)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
    }

    /// The photo frame does what the primary button does.
    private func openPrimaryAction() {
        perform(actions[0])
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
        let locations = await HealthKitManager.shared.fetchAllRouteLocations(for: workout)
        guard locations.count >= 2 else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            routeCoords = locations.map(\.coordinate)
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
    private var importWindow: ClosedRange<Date> {
        let now = Date()
        guard let workoutId,
              let workout = HealthKitManager.shared.todaysWorkouts
            .first(where: { $0.uuid.uuidString == workoutId }) else {
            return now.addingTimeInterval(-3 * 60 * 60)...now.addingTimeInterval(2 * 60)
        }
        let start = workout.startDate.addingTimeInterval(-5 * 60)
        let end = workout.endDate.addingTimeInterval(30 * 60)
        return start...max(start, end)
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

/// The four corner brackets of a camera viewfinder — what makes an empty
/// frame read as "a photo goes here" rather than a placeholder box.
private struct ViewfinderBrackets: Shape {
    var arm: CGFloat = 24
    var radius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(radius, arm)
        // Top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                       control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))
        // Top-right
        p.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                       control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))
        // Bottom-right
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))
        // Bottom-left
        p.move(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - arm))
        return p
    }
}
