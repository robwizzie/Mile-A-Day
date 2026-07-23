import Combine
import SwiftUI

/// Full-screen story playback across ALL viewable authors, Instagram-style:
/// swipe horizontally to cube-rotate between authors' story groups, finishing
/// an author's last story slides straight into the next author, tap left/right
/// steps within an author, hold to pause, swipe down to dismiss.
///
/// The cube: each page rotates about the screen edge it shares with its
/// neighbor (90° at a full page width) with perspective, receding faces dim —
/// the exact grammar Instagram trained everyone on, so the gesture needs no
/// explanation. Adjacent authors' stories are premounted (edge-on, invisible)
/// so their images are usually loaded before the swipe lands; they never mark
/// themselves viewed or run timers until they actually become the front face.
struct StoryViewerView: View {
    /// Viewable story groups in rail order — the deck the cube pages through.
    let groups: [StoryGroup]
    let currentUserId: String?
    /// Per-group earned story days ("yyyy-MM-dd"); nil = no filtering (own).
    let allowedDaysFor: (StoryGroup) -> Set<String>?
    /// Called exactly once when the viewer closes, with whether anything
    /// changed (a story deleted/expired, an author blocked) so the parent can
    /// refresh the rail.
    let onClose: (_ changed: Bool) -> Void

    @State private var currentIndex: Int
    /// Live horizontal drag translation (also driven programmatically for the
    /// auto-advance cube). 0 when settled.
    @State private var dragX: CGFloat = 0
    /// Live downward drag for the dismiss gesture. 0 when settled.
    @State private var dragY: CGFloat = 0
    /// Locked on the first moved points so a diagonal finger can't fight both
    /// axes at once — horizontal cubes, vertical dismisses, never both.
    @State private var dragAxis: DragAxis?
    /// A commit/cancel animation is in flight — input is ignored until the
    /// cube settles so a mid-flight tap can't tear the transition.
    @State private var isTransitioning = false
    @State private var changed = false
    private enum DragAxis { case horizontal, vertical }

    init(
        groups: [StoryGroup],
        initialGroupId: String,
        currentUserId: String?,
        allowedDaysFor: @escaping (StoryGroup) -> Set<String>?,
        onClose: @escaping (_ changed: Bool) -> Void
    ) {
        self.groups = groups
        self.currentUserId = currentUserId
        self.allowedDaysFor = allowedDaysFor
        self.onClose = onClose
        _currentIndex = State(
            initialValue: groups.firstIndex { $0.user_id == initialGroupId } ?? 0
        )
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack {
                // Backdrop behind the rotating faces (and the shrunken card
                // while dragging down to dismiss).
                Color.black.ignoresSafeArea()

                if groups.isEmpty {
                    Color.clear.onAppear { close() }
                } else {
                    ZStack {
                        ForEach(visibleIndices, id: \.self) { i in
                            page(i, width: width)
                        }
                    }
                    // Drag-down dismiss: the whole deck follows the finger and
                    // shrinks slightly — releasing high springs it back. (No
                    // clip shape here: clipping would letterbox the stories'
                    // edge-to-edge backgrounds at the safe-area bounds.)
                    .offset(y: dragY)
                    .scaleEffect(max(0.82, 1 - dragY / 1400))
                }
            }
            .contentShape(Rectangle())
            .gesture(pagerGesture(width: width))
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden(true)
    }

    /// Current page plus premounted neighbors (edge-on at ±90°, so invisible
    /// until a swipe starts revealing them).
    private var visibleIndices: [Int] {
        [currentIndex - 1, currentIndex, currentIndex + 1].filter(groups.indices.contains)
    }

    @ViewBuilder
    private func page(_ i: Int, width: CGFloat) -> some View {
        let offset = slotOffset(i, width: width)
        // −1…1 across the visible travel; clamped so premounted faces park
        // exactly edge-on instead of over-rotating.
        let progress = max(-1, min(1, offset / max(width, 1)))
        StoryGroupPlayerView(
            group: groups[i],
            currentUserId: currentUserId,
            allowedDays: allowedDaysFor(groups[i]),
            isActive: i == currentIndex && !isTransitioning,
            isGesturing: dragAxis != nil || isTransitioning,
            onAdvancePastEnd: { advance(from: i, width: width) },
            onBackPastStart: { goBack(from: i, width: width) },
            onGroupEmpty: { skipEmptyGroup(i, width: width) },
            onRequestClose: { close() },
            onChanged: { changed = true }
        )
        .frame(width: width, height: nil)
        // Receding cube faces fall into shadow, like Instagram's.
        .overlay(
            Color.black.opacity(Double(abs(progress)) * 0.55)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        )
        .rotation3DEffect(
            .degrees(Double(progress) * 90),
            axis: (x: 0, y: 1, z: 0),
            // Hinge on the edge shared with the neighbor: pages to the right
            // fold about their leading edge, pages to the left (and the
            // outgoing current page) about their trailing edge.
            anchor: offset > 0 ? .leading : .trailing,
            anchorZ: 0,
            perspective: 2.5
        )
        .offset(x: offset)
        .zIndex(i == currentIndex ? 1 : 0)
        .allowsHitTesting(i == currentIndex && !isTransitioning)
    }

    private func slotOffset(_ i: Int, width: CGFloat) -> CGFloat {
        CGFloat(i - currentIndex) * width + dragX
    }

    // MARK: - Gesture

    private func pagerGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                guard !isTransitioning else { return }
                if dragAxis == nil {
                    dragAxis = abs(value.translation.width) > abs(value.translation.height)
                        ? .horizontal : .vertical
                }
                switch dragAxis {
                case .horizontal:
                    var translation = value.translation.width
                    // No page to the right of the first group — rubber-band
                    // instead of tearing open an empty face.
                    if currentIndex == 0 && translation > 0 { translation /= 3 }
                    dragX = translation
                case .vertical:
                    dragY = max(0, value.translation.height)
                case nil:
                    break
                }
            }
            .onEnded { value in
                let axis = dragAxis
                dragAxis = nil
                guard !isTransitioning else { return }
                switch axis {
                case .horizontal: settleHorizontal(value, width: width)
                case .vertical: settleVertical(value)
                case nil: break
                }
            }
    }

    private func settleHorizontal(_ value: DragGesture.Value, width: CGFloat) {
        let translation = value.translation.width
        let flick = value.predictedEndTranslation.width
        let goNext = translation < -width / 3 || flick < -width * 0.6
        let goPrev = translation > width / 3 || flick > width * 0.6

        if goNext {
            if currentIndex < groups.count - 1 {
                animate(to: currentIndex + 1, width: width)
            } else {
                // Cubing past the last author ends the show, like Instagram.
                close()
            }
        } else if goPrev, currentIndex > 0 {
            animate(to: currentIndex - 1, width: width)
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { dragX = 0 }
        }
    }

    private func settleVertical(_ value: DragGesture.Value) {
        if value.translation.height > 140 || value.predictedEndTranslation.height > 320 {
            close()
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { dragY = 0 }
        }
    }

    // MARK: - Navigation

    /// Cube to a neighboring group: animate the drag the rest of the way, then
    /// commit the index and zero the translation in one animation-free
    /// transaction — the settled frame is pixel-identical, so there's no jump.
    private func animate(to target: Int, width: CGFloat) {
        guard groups.indices.contains(target), target != currentIndex else { return }
        isTransitioning = true
        MADHaptics.action()
        withAnimation(
            .spring(response: 0.38, dampingFraction: 0.92),
            completionCriteria: .logicallyComplete
        ) {
            dragX = -CGFloat(target - currentIndex) * width
        } completion: {
            var settle = Transaction()
            settle.disablesAnimations = true
            withTransaction(settle) {
                currentIndex = target
                dragX = 0
            }
            isTransitioning = false
        }
    }

    /// A group's last story finished (timer or tap) — flow straight into the
    /// next author, or end the show after the last one.
    private func advance(from i: Int, width: CGFloat) {
        guard i == currentIndex, !isTransitioning else { return }
        if currentIndex < groups.count - 1 {
            animate(to: currentIndex + 1, width: width)
        } else {
            close()
        }
    }

    /// Tapping back past a group's first story returns to the previous author
    /// (the first group just replays its first story — the player already
    /// reset its progress).
    private func goBack(from i: Int, width: CGFloat) {
        guard i == currentIndex, !isTransitioning, currentIndex > 0 else { return }
        animate(to: currentIndex - 1, width: width)
    }

    /// A group turned out to have nothing viewable (expired mid-session, all
    /// stories deleted, or a failed load) — skip past it without breaking the
    /// flow; closing only when there's nowhere left to go.
    private func skipEmptyGroup(_ i: Int, width: CGFloat) {
        changed = true
        guard i == currentIndex, !isTransitioning else { return }
        if currentIndex < groups.count - 1 {
            animate(to: currentIndex + 1, width: width)
        } else if currentIndex > 0 {
            animate(to: currentIndex - 1, width: width)
        } else {
            close()
        }
    }

    private func close() {
        onClose(changed)
    }
}

/// One author's stories inside the pager: segmented progress bars, ~5s
/// auto-advance, tap left/right to step, hold to pause (chrome fades away),
/// inline reactions, and a report/block (or delete-own) overflow. Runs its
/// timers and marks stories viewed ONLY while it is the pager's front face.
private struct StoryGroupPlayerView: View {
    let group: StoryGroup
    let currentUserId: String?
    /// Story days ("yyyy-MM-dd") the viewer has EARNED (completed that day).
    /// nil = no filtering (own stories). Items outside these days are hidden.
    var allowedDays: Set<String>? = nil
    /// This page is front-and-center: timers run, views get marked.
    let isActive: Bool
    /// The pager is mid-drag or mid-cube — hold playback so a story can't
    /// advance underneath a transition.
    let isGesturing: Bool
    /// The group's last story finished (tap or timer) — the pager decides
    /// whether that cubes onward or closes.
    let onAdvancePastEnd: () -> Void
    /// Tapped back past the first story.
    let onBackPastStart: () -> Void
    /// Nothing viewable in this group (expired/deleted/failed) — skip me.
    let onGroupEmpty: () -> Void
    /// The X button (and other explicit exits).
    let onRequestClose: () -> Void
    /// Something changed that the feed should refresh for (delete/block/…).
    let onChanged: () -> Void

    @State private var stories: [PostItem] = []
    @State private var index: Int = 0
    @State private var progress: CGFloat = 0
    @State private var isLoading = true
    @State private var paused = false
    /// Finger held down on the photo — playback pauses and the chrome fades,
    /// Instagram's "let me look at this" gesture.
    @State private var holdPaused = false
    /// The current photo has rendered (or failed) — the 5s timer holds until
    /// then so a slow connection can't advance past an image nobody saw.
    @State private var imageReady = false

    @State private var showReport = false
    /// The story the overflow options were opened FOR — captured at tap time so
    /// the auto-advance can never re-target a destructive action mid-dialog.
    @State private var optionsPost: PostItem?
    @State private var showOptions = false
    /// postId → the viewer's own emoji (hydrated from the server on load, so a
    /// re-view shows the reaction they already left; the server keeps one/story).
    @State private var myReactions: [String: String] = [:]
    /// postId → everyone who reacted, for the Instagram-style bubble row shown
    /// to ALL viewers (not just the author).
    @State private var reactors: [String: [StoryReactor]] = [:]
    /// Own-story extras: seen-by counts per post + the viewers sheet.
    @State private var viewerCounts: [String: Int] = [:]
    @State private var viewersSheetFor: PostItem?
    /// Stories promoted to the feed this session ("Add to feed").
    @State private var promotedIds: Set<String> = []
    @State private var promoting = false
    @State private var promoteError: String?

    /// The emoji palette — must match the backend's ALLOWED_STORY_REACTIONS.
    private let reactionEmojis = ["❤️", "🔥", "👏", "💪", "😮"]

    private let stepDuration: CGFloat = 5.0
    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var current: PostItem? { stories.indices.contains(index) ? stories[index] : nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(.white)
            } else if let post = current {
                storyImage(post)
                tapZones

                // Top scrim so the white progress bars + author stay legible over
                // bright photos (e.g. a sky).
                VStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(0.5), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 150)
                    Spacer()
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .opacity(holdPaused ? 0 : 1)

                VStack(spacing: 0) {
                    progressBars
                    header(post)
                    Spacer()
                    footer(post)
                }
                .padding(.top, 8)
                // Holding to look at the photo fades the chrome away.
                .opacity(holdPaused ? 0 : 1)
                .animation(.easeInOut(duration: 0.2), value: holdPaused)
            } else {
                // Deck emptied (deleted the last story / everything expired).
                Color.clear.onAppear { if isActive { onGroupEmpty() } }
            }
        }
        .task { await load() }
        .onReceive(tick) { _ in advanceProgress() }
        .onChange(of: isActive) { _, active in
            if active { activate() }
        }
        // onDismiss also covers swiping the sheet away, which would otherwise
        // leave `paused` stuck true and freeze the story.
        .sheet(isPresented: $showReport, onDismiss: { paused = false }) {
            // Report the story the options were opened for, not whatever is
            // current by the time the sheet lands.
            if let post = optionsPost ?? current {
                ReportPostSheet(postId: post.post_id) { showReport = false }
            }
        }
        .sheet(item: $viewersSheetFor, onDismiss: { paused = false }) { post in
            StoryViewersSheet(postId: post.post_id)
        }
        .task(id: current?.post_id) {
            // Own story: load who's seen it so the "Seen by" pill has a count.
            guard let post = current, post.is_self else { return }
            if let resp = try? await PostService.storyViewers(postId: post.post_id) {
                viewerCounts[post.post_id] = resp.count
            }
        }
        .task(id: current?.post_id) {
            // Everyone's reactions for the current story → the bubble row.
            guard let post = current else { return }
            if let resp = try? await PostService.storyReactors(postId: post.post_id) {
                reactors[post.post_id] = resp.reactors
            }
        }
        .alert("Couldn't add to feed", isPresented: Binding(
            get: { promoteError != nil },
            set: { if !$0 { promoteError = nil; paused = false } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(promoteError ?? "")
        }
        .confirmationDialog("Story options", isPresented: $showOptions, titleVisibility: .hidden) {
            if let post = optionsPost {
                if post.is_self {
                    Button("Delete story & photo", role: .destructive) {
                        Task { await deleteOwn(post) }
                    }
                } else {
                    Button("Report") { showReport = true }
                    Button("Block \(group.displayName)", role: .destructive) {
                        Task { await block(post) }
                    }
                }
            }
        } message: {
            // The story's photo also fronts the run's card on the feed and
            // profile — deleting it removes the photo EVERYWHERE, which
            // surprised users who thought they were only ending the 24h story.
            if optionsPost?.is_self == true {
                Text("This also removes the photo from your run's card on the feed and your profile.")
            }
        }
        .onChange(of: showOptions) { _, open in
            // Resume when the dialog closes — unless it handed off to another
            // pausing surface (report sheet) or a destructive action is running.
            if !open && !showReport && promoteError == nil {
                paused = false
            }
        }
    }

    // MARK: - Pieces

    private func storyImage(_ post: PostItem) -> some View {
        // The media is composed at 4:5 with the stats sticker baked in, so it
        // must be shown WHOLE — fit within the screen (never fill-crop; that
        // cut off the sticker/edges on tall phones) over a blurred, dimmed
        // edge-to-edge copy that fills the letterbox space. Both layers are
        // sized EXPLICITLY from the screen geometry so no proposal quirk can
        // ever regress this into a crop.
        GeometryReader { geo in
            AsyncImage(url: post.mediaURL) { phase in
                switch phase {
                case .success(let image):
                    ZStack {
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .blur(radius: 40, opaque: true)
                            .opacity(0.55)
                        image.resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                    .onAppear { imageReady = true }
                case .failure:
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.3))
                        .frame(width: geo.size.width, height: geo.size.height)
                        .onAppear { imageReady = true }
                default:
                    ProgressView().tint(.white)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            // Re-identify per story so the readiness onAppear refires every step.
            .id(post.post_id)
        }
        .ignoresSafeArea()
    }

    private var tapZones: some View {
        HStack(spacing: 0) {
            Color.clear.contentShape(Rectangle()).onTapGesture { step(-1) }
            Color.clear.contentShape(Rectangle()).onTapGesture { step(1) }
        }
        .ignoresSafeArea()
        // Hold to pause and take the photo in — chrome fades, releasing (or
        // starting a swipe, which cancels the press) resumes.
        .onLongPressGesture(minimumDuration: 0.25) {
            holdPaused = true
        } onPressingChanged: { pressing in
            if !pressing { holdPaused = false }
        }
    }

    private var progressBars: some View {
        HStack(spacing: 4) {
            ForEach(stories.indices, id: \.self) { i in
                GeometryReader { geo in
                    Capsule().fill(Color.white.opacity(0.3))
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color.white)
                                .frame(width: geo.size.width * fill(for: i))
                        }
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal, 10)
    }

    private func header(_ post: PostItem) -> some View {
        HStack(spacing: 10) {
            AvatarView(name: group.displayName, imageURL: group.profile_image_url, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.displayName)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                HStack(spacing: 4) {
                    Text(post.relativeTime)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                    if let type = post.workout_type {
                        Image(systemName: ActivityCardView.icon(type))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(ActivityCardView.color(type))
                    }
                }
            }
            Spacer()
            overflowMenu(post)
            Button { onRequestClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .padding(6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .shadow(color: .black.opacity(0.4), radius: 6)
    }

    // Instagram-style footer over a soft bottom scrim: caption on top, then the
    // ephemeral controls — emoji reactions on a friend's story, "Seen by" +
    // "Add to feed" on your own. (Hype stays the feed's currency.)
    @ViewBuilder
    private func footer(_ post: PostItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            reactorBubbles(post)

            if let caption = post.caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.7), radius: 4, y: 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if post.is_self {
                HStack(spacing: 10) {
                    seenByPill(post)
                    if canPromote(post) { addToFeedPill(post) }
                    Spacer(minLength: 0)
                }
            } else {
                reactionBar(post)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .frame(height: 200)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        )
    }

    /// Ephemeral emoji reactions — the story counterpart to feed hype.
    private func reactionBar(_ post: PostItem) -> some View {
        HStack(spacing: 10) {
            ForEach(reactionEmojis, id: \.self) { emoji in
                let selected = myReactions[post.post_id] == emoji
                Button {
                    react(post, emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: selected ? 26 : 22))
                        .frame(width: 44, height: 44)
                        .background(
                            Circle().fill(selected ? Color.white.opacity(0.25) : Color.black.opacity(0.35))
                        )
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(selected ? 0.7 : 0.15), lineWidth: 1)
                        )
                        .scaleEffect(selected ? 1.08 : 1.0)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: myReactions)
    }

    /// Instagram-style row of who reacted — overlapping avatars, each badged
    /// with their emoji. Shown to every viewer (per the product decision).
    @ViewBuilder
    private func reactorBubbles(_ post: PostItem) -> some View {
        let list = reactors[post.post_id] ?? []
        if !list.isEmpty {
            HStack(spacing: -8) {
                ForEach(list.prefix(6)) { reactor in
                    ZStack(alignment: .bottomTrailing) {
                        AvatarView(
                            name: reactor.displayName,
                            imageURL: reactor.profile_image_url,
                            size: 30
                        )
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.55), lineWidth: 1.5))
                        Text(reactor.emoji)
                            .font(.system(size: 12))
                            .padding(2)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                            .offset(x: 5, y: 4)
                    }
                }
                if list.count > 6 {
                    Text("+\(list.count - 6)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.leading, 14)
                }
                Spacer(minLength: 0)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: list.count)
        }
    }

    private func seenByPill(_ post: PostItem) -> some View {
        Button {
            paused = true
            viewersSheetFor = post
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 12, weight: .bold))
                if let count = viewerCounts[post.post_id] {
                    Text(count == 1 ? "Seen by 1" : "Seen by \(count)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                } else {
                    Text("Seen by")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.4)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// A story photo can be promoted into the permanent feed — it replaces the
    /// run's auto route/stats card in place (upsert by workout). Hidden when the
    /// story is itself on the feed OR its workout already has a separate
    /// DELIBERATE feed post (server-computed `workout_on_feed`; the auto card
    /// doesn't count — replacing it is the point) — otherwise "Add to feed"
    /// would be offered only to 409 on tap.
    private func canPromote(_ post: PostItem) -> Bool {
        post.share_to_feed != true
            && post.workout_on_feed != true
            && !promotedIds.contains(post.post_id)
    }

    private func addToFeedPill(_ post: PostItem) -> some View {
        Button {
            Task { await promoteToFeed(post) }
        } label: {
            HStack(spacing: 6) {
                if promoting {
                    ProgressView().tint(.white).scaleEffect(0.7)
                } else {
                    Image(systemName: "square.stack.badge.plus")
                        .font(.system(size: 12, weight: .bold))
                }
                Text("Add to feed")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(MADTheme.Colors.madRed.opacity(0.85)))
        }
        .buttonStyle(.plain)
        .disabled(promoting)
    }

    /// Pauses playback and opens the options dialog for THIS story. A plain
    /// Menu can't pause the auto-advance (no open/close signal), which let the
    /// story change underneath an open menu and mis-target "Delete story".
    private func overflowMenu(_ post: PostItem) -> some View {
        Button {
            paused = true
            optionsPost = post
            showOptions = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .padding(6)
        }
    }

    // MARK: - Progress / navigation

    private func fill(for i: Int) -> CGFloat {
        if i < index { return 1 }
        if i == index { return progress }
        return 0
    }

    private func advanceProgress() {
        guard isActive, !isGesturing, !holdPaused,
              !isLoading, !paused, !showReport, !showOptions, !promoting,
              imageReady, current != nil else { return }
        progress += 0.05 / stepDuration
        if progress >= 1 { step(1) }
    }

    private func step(_ dir: Int) {
        progress = 0
        let next = index + dir
        if next < 0 {
            // First story replays (progress just reset); the pager may cube
            // back to the previous author.
            onBackPastStart()
            return
        }
        if next >= stories.count {
            onAdvancePastEnd()
            return
        }
        imageReady = false
        index = next
        markViewed()
    }

    /// This page just became the pager's front face: restart the current bar
    /// and record the view. Premounted neighbor pages never reach this until
    /// the user actually lands on them.
    private func activate() {
        guard !isLoading else { return }
        if stories.isEmpty {
            onGroupEmpty()
        } else {
            progress = 0
            markViewed()
        }
    }

    private func markViewed() {
        guard isActive, let post = current else { return }
        Task { try? await PostService.markStoryViewed(postId: post.post_id) }
    }

    // MARK: - Actions

    private func load() async {
        do {
            var loaded = try await PostService.fetchUserStories(userId: group.user_id)
            // Per-day viewing gate: drop stories from days the viewer hasn't
            // earned (no local_date ⇒ legacy row, leave it visible).
            if let allowedDays {
                loaded = loaded.filter { story in
                    guard let day = story.local_date else { return true }
                    return allowedDays.contains(day)
                }
            }
            await MainActor.run {
                stories = loaded
                // Hydrate the viewer's prior reactions so re-opening a story
                // shows the emoji they already picked (server keeps one/story).
                for story in loaded {
                    if let emoji = story.viewer_reaction, !emoji.isEmpty {
                        myReactions[story.post_id] = emoji
                    }
                }
                isLoading = false
                if loaded.isEmpty {
                    // The group's stories expired/vanished since the rail
                    // loaded (or none are viewable yet) — tell the pager to
                    // skip past instead of flashing black.
                    onChanged()
                    if isActive { onGroupEmpty() }
                } else if isActive {
                    markViewed()
                }
            }
        } catch {
            // A failed load behaves like an empty group: skipped when (or if)
            // the user reaches it — one bad fetch must not kill the whole show.
            await MainActor.run {
                isLoading = false
                if isActive { onGroupEmpty() }
            }
        }
    }

    private func react(_ post: PostItem, _ emoji: String) {
        // Optimistic — the server keeps one reaction per story and swapping is
        // idempotent, so a failed call just means no push went out.
        myReactions[post.post_id] = emoji
        MADHaptics.action()
        Task {
            try? await PostService.reactToStory(postId: post.post_id, emoji: emoji)
            // Reconcile the bubble row with the server (adds/updates my bubble).
            if let resp = try? await PostService.storyReactors(postId: post.post_id) {
                await MainActor.run { reactors[post.post_id] = resp.reactors }
            }
        }
    }

    private func promoteToFeed(_ post: PostItem) async {
        guard !promoting else { return }
        promoting = true
        defer { promoting = false }
        do {
            // Carries the workout id, so this replaces the run's auto
            // route/stats card in place. If the run already has a deliberate
            // feed post, the server rejects it (one post per workout).
            _ = try await PostService.createPost(
                mediaUrl: post.media_url,
                caption: post.caption,
                workoutId: post.workout_id,
                shareToFeed: true,
                shareToStory: false,
                stats: post.stats_snapshot,
                isAuto: false,
                // Promoting while the run's 10-min window is still open counts
                // as posting live — the FRESH chip follows onto the feed.
                postedLive: FreshPostWindowManager.shared.isOpen
            )
            await MainActor.run {
                promotedIds.insert(post.post_id)
                onChanged()
                MADHaptics.success()
            }
        } catch APIError.conflict {
            await MainActor.run {
                paused = true
                promoteError = "This workout already has a feed post. Delete it first to share this photo instead."
            }
        } catch {
            print("[StoryViewer] ❌ Add to feed failed: \(error)")
        }
    }

    private func deleteOwn(_ post: PostItem) async {
        do {
            try await PostService.deletePost(postId: post.post_id)
            await MainActor.run {
                onChanged()
                stories.removeAll { $0.post_id == post.post_id }
                if index >= stories.count { index = max(0, stories.count - 1) }
                progress = 0
                imageReady = false
                if stories.isEmpty { onGroupEmpty() }
            }
        } catch {}
    }

    private func block(_ post: PostItem) async {
        do {
            try await BlockService.block(userId: post.user_id)
            await MainActor.run {
                onChanged()
                onRequestClose()
            }
        } catch {}
    }
}

/// "Seen by" list for the author's own story: who watched, when, and any emoji
/// reaction they left (reactors sort first, matching the server order).
struct StoryViewersSheet: View {
    let postId: String
    @Environment(\.dismiss) private var dismiss
    @State private var viewers: [StoryViewer] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
                Group {
                    if !loaded {
                        ProgressView().tint(.white)
                    } else if viewers.isEmpty {
                        VStack(spacing: MADTheme.Spacing.sm) {
                            Image(systemName: "eye.slash")
                                .font(.system(size: 30))
                                .foregroundColor(.white.opacity(0.3))
                            Text("No views yet")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("Friends see your story once they've done their mile today.")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, MADTheme.Spacing.xl)
                        }
                    } else {
                        ScrollView {
                            VStack(spacing: MADTheme.Spacing.sm) {
                                ForEach(viewers) { viewer in
                                    row(viewer)
                                }
                            }
                            .padding(MADTheme.Spacing.md)
                        }
                    }
                }
            }
            .navigationTitle(loaded && !viewers.isEmpty ? "Seen by \(viewers.count)" : "Seen by")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            if let resp = try? await PostService.storyViewers(postId: postId) {
                viewers = resp.viewers
            }
            loaded = true
        }
    }

    private func row(_ viewer: StoryViewer) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            AvatarView(name: viewer.displayName, imageURL: viewer.profile_image_url, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewer.displayName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(viewer.relativeTime)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            if let emoji = viewer.emoji {
                Text(emoji)
                    .font(.system(size: 24))
            }
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}
