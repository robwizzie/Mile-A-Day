import SwiftUI

/// Full-screen story playback for a single author: segmented progress bars,
/// ~5s auto-advance, tap left/right to step, swipe down to dismiss, inline hype,
/// and a report/block (or delete-own) overflow.
struct StoryViewerView: View {
    let group: StoryGroup
    let currentUserId: String?
    /// Called when the viewer dismisses, with whether anything changed (a story
    /// was deleted) so the parent can refresh the rail.
    let onClose: (_ changed: Bool) -> Void

    @State private var stories: [PostItem] = []
    @State private var index: Int = 0
    @State private var progress: CGFloat = 0
    @State private var isLoading = true
    @State private var dragOffset: CGFloat = 0
    @State private var changed = false
    @State private var paused = false
    /// The current photo has rendered (or failed) — the 5s timer holds until
    /// then so a slow connection can't advance past an image nobody saw.
    @State private var imageReady = false

    @State private var showReport = false
    /// The story the overflow options were opened FOR — captured at tap time so
    /// the auto-advance can never re-target a destructive action mid-dialog.
    @State private var optionsPost: PostItem?
    @State private var showOptions = false
    /// postId → emoji the viewer sent this session (server keeps one per story).
    @State private var myReactions: [String: String] = [:]
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

                VStack(spacing: 0) {
                    progressBars
                    header(post)
                    Spacer()
                    footer(post)
                }
                .padding(.top, 8)
            } else {
                Color.clear.onAppear { close() }
            }
        }
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture()
                .onChanged { v in if v.translation.height > 0 { dragOffset = v.translation.height } }
                .onEnded { v in
                    if v.translation.height > 120 { close() } else { withAnimation { dragOffset = 0 } }
                }
        )
        .task { await load() }
        .onReceive(tick) { _ in advanceProgress() }
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
                    Button("Delete story", role: .destructive) {
                        Task { await deleteOwn(post) }
                    }
                } else {
                    Button("Report") { showReport = true }
                    Button("Block \(group.displayName)", role: .destructive) {
                        Task { await block(post) }
                    }
                }
            }
        }
        .onChange(of: showOptions) { _, open in
            // Resume when the dialog closes — unless it handed off to another
            // pausing surface (report sheet) or a destructive action is running.
            if !open && !showReport && promoteError == nil {
                paused = false
            }
        }
        .statusBarHidden(true)
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
            Button { close() } label: {
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
    /// run's auto route/stats card in place (upsert by workout).
    private func canPromote(_ post: PostItem) -> Bool {
        post.share_to_feed != true && !promotedIds.contains(post.post_id)
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
        guard !isLoading, !paused, !showReport, !showOptions, !promoting,
              imageReady, current != nil else { return }
        progress += 0.05 / stepDuration
        if progress >= 1 { step(1) }
    }

    private func step(_ dir: Int) {
        progress = 0
        let next = index + dir
        if next < 0 { return }
        if next >= stories.count { close(); return }
        imageReady = false
        index = next
        markViewed()
    }

    private func markViewed() {
        guard let post = current else { return }
        Task { try? await PostService.markStoryViewed(postId: post.post_id) }
    }

    private func close() {
        onClose(changed)
    }

    // MARK: - Actions

    private func load() async {
        do {
            let loaded = try await PostService.fetchUserStories(userId: group.user_id)
            await MainActor.run {
                stories = loaded
                isLoading = false
                if loaded.isEmpty {
                    // The group's stories expired/vanished since the rail
                    // loaded — report changed so the parent removes the dead
                    // ring instead of re-presenting a black flash forever.
                    changed = true
                    close()
                } else {
                    markViewed()
                }
            }
        } catch {
            await MainActor.run { isLoading = false; close() }
        }
    }

    private func react(_ post: PostItem, _ emoji: String) {
        // Optimistic — the server keeps one reaction per story and swapping is
        // idempotent, so a failed call just means no push went out.
        myReactions[post.post_id] = emoji
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { try? await PostService.reactToStory(postId: post.post_id, emoji: emoji) }
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
                isAuto: false
            )
            await MainActor.run {
                promotedIds.insert(post.post_id)
                changed = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
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
            changed = true
            await MainActor.run {
                stories.removeAll { $0.post_id == post.post_id }
                if index >= stories.count { index = max(0, stories.count - 1) }
                progress = 0
                imageReady = false
                if stories.isEmpty { close() }
            }
        } catch {}
    }

    private func block(_ post: PostItem) async {
        do {
            try await BlockService.block(userId: post.user_id)
            changed = true
            await MainActor.run { close() }
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
