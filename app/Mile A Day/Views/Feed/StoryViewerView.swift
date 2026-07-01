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
    @State private var hyping = false

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
            if let post = current {
                ReportPostSheet(postId: post.post_id) { showReport = false }
            }
        }
        .statusBarHidden(true)
    }

    // MARK: - Pieces

    private func storyImage(_ post: PostItem) -> some View {
        AsyncImage(url: post.mediaURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
                    .onAppear { imageReady = true }
            case .failure:
                Image(systemName: "photo").font(.largeTitle).foregroundColor(.white.opacity(0.3))
                    .onAppear { imageReady = true }
            default:
                ProgressView().tint(.white)
            }
        }
        // Re-identify per story so the readiness onAppear refires every step.
        .id(post.post_id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
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
                Text(post.relativeTime)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
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

    // Instagram-style footer: caption bottom-left, hype bottom-right, over a soft
    // bottom scrim. The run stats already live in the photo's baked-in overlay,
    // so we don't repeat them here.
    @ViewBuilder
    private func footer(_ post: PostItem) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            if let caption = post.caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.7), radius: 4, y: 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }

            if !post.is_self {
                HypeButton(isHyped: post.is_hyped, isBusy: hyping) {
                    Task { await hype(post) }
                }
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

    @ViewBuilder
    private func overflowMenu(_ post: PostItem) -> some View {
        Menu {
            if post.is_self {
                Button(role: .destructive) {
                    Task { await deleteOwn(post) }
                } label: { Label("Delete story", systemImage: "trash") }
            } else {
                Button { paused = true; showReport = true } label: {
                    Label("Report", systemImage: "flag")
                }
                Button(role: .destructive) {
                    Task { await block(post) }
                } label: { Label("Block \(group.displayName)", systemImage: "hand.raised") }
            }
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
        guard !isLoading, !paused, !showReport, imageReady, current != nil else { return }
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
                if loaded.isEmpty { close() } else { markViewed() }
            }
        } catch {
            await MainActor.run { isLoading = false; close() }
        }
    }

    private func hype(_ post: PostItem) async {
        guard !hyping, !post.is_hyped else { return }
        hyping = true
        defer { hyping = false }
        do {
            _ = try await HypeService.sendHype(
                targetUserId: post.user_id,
                context: HypeContext(
                    contextType: "post",
                    contextId: post.post_id,
                    contextLabel: post.caption ?? group.displayName
                )
            )
            await MainActor.run {
                if stories.indices.contains(index) {
                    stories[index].is_hyped = true
                    stories[index].hype_count = (stories[index].hype_count ?? 0) + 1
                }
            }
        } catch {
            // conflict (already hyped) / rate-limited — leave button as-is.
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
