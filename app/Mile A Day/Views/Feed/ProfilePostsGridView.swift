import SwiftUI

/// Instagram-style grid of a user's permanent posts, used on both the owner's
/// profile and a friend's. Tapping a thumbnail opens the person's posts as a
/// scrollable feed (starting at the tapped post) so you can keep swiping
/// through their history. Paginates as the user scrolls.
///
/// A profile grid is the one screen in this app that is genuinely a person's
/// own space, so it is theirs to arrange: highlights above it, up to three
/// pinned posts at the top of it, and a sort / filter / density they choose.
/// Every one of those is the OWNER's setting applied to the OWNER's grid —
/// visiting someone else's profile always draws it the plain way, because how
/// you like to read your own history says nothing about theirs (and a sticky
/// filter carried onto a stranger's grid just looks like they've posted
/// nothing).
struct ProfilePostsGridView: View {
    let userId: String
    var isSelf: Bool = false

    /// Which grid is showing: the user's own posts, or posts they're tagged
    /// in (accepted collabs + caption @mentions) — Instagram's two profile tabs.
    private enum GridSection { case posts, tagged }
    @State private var section: GridSection = .posts

    @State private var posts: [PostItem] = []
    /// Pinned posts, kept OUT of `posts` and drawn above it. Only ever
    /// populated on the owner's own request (`pins=split`); a grid that
    /// doesn't ask gets them inline, which is what keeps them visible to
    /// anything that doesn't know pins exist.
    @State private var pinnedPosts: [PostItem] = []
    /// Own story posts whose run never made the feed (self view only) — shown
    /// in their own strip so the owner can add one to the feed or let it be.
    @State private var storyPosts: [PostItem] = []
    @State private var nextBefore: String?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var loaded = false
    @State private var selectedPost: PostItem?
    @State private var selectedPinnedPost: PostItem?
    @State private var selectedStoryPost: PostItem?
    @State private var addingToFeedIds: Set<String> = []
    @State private var addToFeedError: String?
    @State private var pinError: String?
    /// Observed so the "Add to feed" pills disappear when the walk's posting
    /// window lapses while the grid is on screen.
    @ObservedObject private var freshWindow = FreshPostWindowManager.shared

    // Grid arrangement. Seeded from the owner's saved preference and written
    // back on change; a visitor's copy stays on the defaults for the whole
    // visit (see the type comment).
    @State private var sort: PostGridSort = .newest
    @State private var filter: PostGridFilter = .all
    @State private var layout: PostGridLayout = .compact

    // Highlights rail.
    @State private var highlights: [PostHighlight] = []
    @State private var highlightsLoaded = false
    @State private var openHighlight: PostHighlight?
    @State private var editingHighlight: HighlightEditorTarget?

    // Tagged grid — loaded lazily the first time the section is opened.
    @State private var taggedPosts: [PostItem] = []
    @State private var taggedNextBefore: String?
    @State private var isTaggedLoading = false
    @State private var isTaggedLoadingMore = false
    @State private var taggedLoaded = false
    @State private var selectedTaggedPost: PostItem?

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: layout.columns)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            highlightsRail
            gridHeader
            switch section {
            case .posts: postsContent
            case .tagged: taggedContent
            }
        }
        .task {
            if !loaded {
                // Only the owner's own arrangement is restored. Doing this in
                // `.task` rather than at init keeps a visitor's grid on the
                // defaults even when this view is reused across profiles.
                if isSelf {
                    sort = PostGridPreferences.sort
                    filter = PostGridPreferences.filter
                    layout = PostGridPreferences.layout
                }
                await load()
            }
            if !highlightsLoaded { await loadHighlights() }
        }
        // The "Tagged posts on my grid" switch lives in Settings, which is
        // pushed FROM here — so popping back lands on a grid that's still
        // alive and still holding the tags the user just turned off. Without
        // this the setting reads as broken at the exact moment it's used.
        .onReceive(NotificationCenter.default.publisher(
            for: NSNotification.Name("MAD_TaggedPostsOnProfileChanged")
        )) { _ in
            guard isSelf else { return }
            Task { await load() }
        }
        .sheet(item: $selectedPost) { post in
            PostDetailView(
                title: isSelf ? "Your Posts" : "Posts",
                posts: $posts,
                initialPostId: post.post_id,
                onNeedMore: { Task { await loadMore() } },
                // This list IS a profile grid, so a collab hidden from the
                // viewer's grid has to leave it. Only on their OWN profile —
                // someone else's grid isn't theirs to curate.
                dropsCollabsHiddenFromProfile: isSelf
            )
        }
        // Pins are their own array, so they need their own detail sheet or a
        // tap would open the wrong post — `initialPostId` can only find a post
        // that's actually in the list it was handed.
        .sheet(item: $selectedPinnedPost) { post in
            PostDetailView(
                title: isSelf ? "Your Posts" : "Posts",
                posts: $pinnedPosts,
                initialPostId: post.post_id,
                onNeedMore: {},
                dropsCollabsHiddenFromProfile: isSelf
            )
        }
        .sheet(item: $selectedStoryPost) { post in
            PostDetailView(
                title: "Your Stories",
                posts: $storyPosts,
                initialPostId: post.post_id,
                onNeedMore: {}
            )
        }
        .sheet(item: $selectedTaggedPost) { post in
            // Tagged posts belong to OTHER authors — let taps on their names
            // (and @mentions) open profiles from inside the sheet.
            PostDetailView(
                title: "Tagged",
                posts: $taggedPosts,
                initialPostId: post.post_id,
                onNeedMore: { Task { await loadMoreTagged() } },
                showsAuthorProfiles: true
            )
        }
        .fullScreenCover(item: $openHighlight) { highlight in
            HighlightViewerView(
                highlight: highlight,
                isSelf: isSelf,
                onEdit: { editingHighlight = .existing(highlight) },
                onChanged: { Task { await loadHighlights() } }
            )
        }
        .sheet(item: $editingHighlight) { target in
            HighlightEditorView(userId: userId, target: target) {
                Task { await loadHighlights() }
            }
        }
        .alert("Couldn't add to feed", isPresented: Binding(
            get: { addToFeedError != nil },
            set: { if !$0 { addToFeedError = nil } }
        )) {
            Button("OK", role: .cancel) { addToFeedError = nil }
        } message: {
            Text(addToFeedError ?? "")
        }
        .alert("Couldn't pin that", isPresented: Binding(
            get: { pinError != nil },
            set: { if !$0 { pinError = nil } }
        )) {
            Button("OK", role: .cancel) { pinError = nil }
        } message: {
            Text(pinError ?? "")
        }
    }

    // MARK: - Highlights rail

    /// The circles above the grid. Drawn whenever there's something to draw,
    /// plus a "New" button on your own profile — an empty rail on someone
    /// else's profile is just absent, since there's nothing there to invite.
    @ViewBuilder
    private var highlightsRail: some View {
        if !highlights.isEmpty || (isSelf && highlightsLoaded) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MADTheme.Spacing.md) {
                    if isSelf {
                        newHighlightButton
                    }
                    ForEach(highlights) { highlight in
                        highlightCircle(highlight)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
    }

    private var newHighlightButton: some View {
        Button {
            MADHaptics.tap()
            editingHighlight = .new
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                        )
                        .foregroundColor(.white.opacity(0.25))
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(width: 64, height: 64)
                Text("New")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
    }

    private func highlightCircle(_ highlight: PostHighlight) -> some View {
        Button {
            MADHaptics.tap()
            openHighlight = highlight
        } label: {
            VStack(spacing: 6) {
                AsyncImage(url: highlight.coverURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: Color.white.opacity(0.06)
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1.5)
                )
                Text(highlight.title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isSelf {
                Button {
                    editingHighlight = .existing(highlight)
                } label: {
                    Label("Edit highlight", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    Task { await deleteHighlight(highlight) }
                } label: {
                    Label("Delete highlight", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Header: section picker + arrangement menu

    private var gridHeader: some View {
        HStack(spacing: 8) {
            segmentButton(.posts, icon: "square.grid.3x3", label: "Posts")
            segmentButton(.tagged, icon: "person.crop.square", label: "Tagged")
            Spacer()
            if section == .posts {
                arrangementMenu
            }
        }
    }

    /// Sort / filter / density, and a dot when any of them is off the default
    /// — a grid that's quietly filtered otherwise reads as a grid that's empty.
    private var arrangementMenu: some View {
        Menu {
            Picker("Sort", selection: sortBinding) {
                ForEach(PostGridSort.allCases) { option in
                    Label(option.title, systemImage: option.icon).tag(option)
                }
            }
            Picker("Show", selection: filterBinding) {
                ForEach(PostGridFilter.allCases) { option in
                    Label(option.title, systemImage: option.icon).tag(option)
                }
            }
            Picker("Size", selection: layoutBinding) {
                ForEach(PostGridLayout.allCases) { option in
                    Label(option.title, systemImage: option.icon).tag(option)
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.07)))
                if isArranged {
                    Circle()
                        .fill(MADTheme.Colors.madRed)
                        .frame(width: 7, height: 7)
                        .offset(x: 1, y: -1)
                }
            }
        }
    }

    private var isArranged: Bool {
        sort != .newest || filter != .all || layout != .compact
    }

    // Bindings rather than `.onChange`: the grid has to reload when the sort
    // or the filter moves (they're server-side), and only persist for the
    // owner. Density is client-side, so it never triggers a fetch.
    private var sortBinding: Binding<PostGridSort> {
        Binding(get: { sort }, set: { newValue in
            guard newValue != sort else { return }
            sort = newValue
            if isSelf { PostGridPreferences.sort = newValue }
            MADHaptics.tap()
            Task { await load() }
        })
    }

    private var filterBinding: Binding<PostGridFilter> {
        Binding(get: { filter }, set: { newValue in
            guard newValue != filter else { return }
            filter = newValue
            if isSelf { PostGridPreferences.filter = newValue }
            MADHaptics.tap()
            Task { await load() }
        })
    }

    private var layoutBinding: Binding<PostGridLayout> {
        Binding(get: { layout }, set: { newValue in
            guard newValue != layout else { return }
            withAnimation(.easeInOut(duration: 0.18)) { layout = newValue }
            if isSelf { PostGridPreferences.layout = newValue }
            MADHaptics.tap()
        })
    }

    private func segmentButton(_ target: GridSection, icon: String, label: String) -> some View {
        let isActive = section == target
        return Button {
            guard section != target else { return }
            section = target
            if target == .tagged && !taggedLoaded {
                Task { await loadTagged() }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(label)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
            }
            .foregroundColor(isActive ? .white : .white.opacity(0.45))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isActive ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Posts grid

    @ViewBuilder
    private var postsContent: some View {
        if isLoading && posts.isEmpty && pinnedPosts.isEmpty && storyPosts.isEmpty {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: MADTheme.Colors.madRed))
                .frame(maxWidth: .infinity)
                .padding(.top, MADTheme.Spacing.xl)
        } else if posts.isEmpty && pinnedPosts.isEmpty && storyPosts.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                if isSelf && !storyPosts.isEmpty {
                    storySection
                }
                if !pinnedPosts.isEmpty {
                    pinnedSection
                }
                if !posts.isEmpty {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(posts) { post in
                            gridThumbnail(post) { selectedPost = post }
                                .onAppear {
                                    if post.id == posts.last?.id { Task { await loadMore() } }
                                }
                        }
                    }
                }
                if isLoadingMore {
                    ProgressView().tint(.white).padding(.vertical, MADTheme.Spacing.md)
                }
            }
        }
    }

    /// Up to three posts the owner chose to lead with. Deliberately the same
    /// tile as the grid below it, with a label instead of a different shape:
    /// a pin is "this one first", not a different kind of post.
    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("PINNED")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
            }
            .foregroundColor(.white.opacity(0.55))

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(pinnedPosts) { post in
                    gridThumbnail(post) { selectedPinnedPost = post }
                }
            }
        }
    }

    // MARK: - Tagged grid

    @ViewBuilder
    private var taggedContent: some View {
        if isTaggedLoading && taggedPosts.isEmpty {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: MADTheme.Colors.madRed))
                .frame(maxWidth: .infinity)
                .padding(.top, MADTheme.Spacing.xl)
        } else if taggedPosts.isEmpty {
            taggedEmptyState
        } else {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(taggedPosts) { post in
                        gridThumbnail(post) { selectedTaggedPost = post }
                            .onAppear {
                                if post.id == taggedPosts.last?.id {
                                    Task { await loadMoreTagged() }
                                }
                            }
                    }
                }
                if isTaggedLoadingMore {
                    ProgressView().tint(.white).padding(.vertical, MADTheme.Spacing.md)
                }
            }
        }
    }

    private var taggedEmptyState: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: "person.crop.square")
                .font(.system(size: 34))
                .foregroundColor(.white.opacity(0.3))
            Text(isSelf ? "No tagged posts yet" : "No tagged posts")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(isSelf
                 ? "When friends collab with you or @mention you, those posts show up here."
                 : "Collabs and @mentions of them will show up here.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, MADTheme.Spacing.xl)
        .padding(.horizontal, MADTheme.Spacing.lg)
    }

    // MARK: - Story-only strip (own profile)

    /// Horizontal strip of story photos that never made the feed, each with a
    /// one-tap "Add to feed" — promoted posts keep their original date and
    /// stats and slide straight into the grid below.
    private var storySection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                Text("STORIES NOT ON YOUR FEED")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.6))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    ForEach(storyPosts) { post in
                        storyCard(post)
                    }
                }
            }
        }
    }

    private func storyCard(_ post: PostItem) -> some View {
        VStack(spacing: 6) {
            Button { selectedStoryPost = post } label: {
                AsyncImage(url: post.mediaURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure:
                        ZStack { Color.white.opacity(0.05); Image(systemName: "photo").foregroundColor(.white.opacity(0.3)) }
                    default:
                        ZStack { Color.white.opacity(0.05); ProgressView().tint(.white) }
                    }
                }
                .frame(width: 108, height: 135)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
                .overlay(alignment: .bottomLeading) {
                    if let date = storyDateText(post) {
                        Text(date)
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .padding(6)
                    }
                }
            }
            .buttonStyle(.plain)
            // A story is the only thing here that expires, so the way to keep
            // one is to put it in a highlight — offered right where the
            // expiring photos are, not buried in a menu somewhere else.
            .contextMenu {
                Button {
                    editingHighlight = .newWithPost(post.post_id)
                } label: {
                    Label("Save to a highlight", systemImage: "bookmark")
                }
            }

            // Promoting a story puts a photo on the feed, so it answers to the
            // same rule as posting one: a qualifying walk/run today. That's the
            // DAY tier — the ten-minute countdown bounds the camera, and this
            // photo was captured long before this tap.
            if freshWindow.canPostToday {
                Button { addToFeed(post) } label: {
                    HStack(spacing: 4) {
                        if addingToFeedIds.contains(post.post_id) {
                            ProgressView().tint(.white).scaleEffect(0.6)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .heavy))
                        }
                        Text("Add to feed")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(width: 108)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(MADTheme.Colors.redGradient))
                }
                .buttonStyle(.plain)
                .disabled(addingToFeedIds.contains(post.post_id))
            }
        }
    }

    private static let storyDateParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let storyDateDisplay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private func storyDateText(_ post: PostItem) -> String? {
        guard let localDate = post.local_date,
              let date = Self.storyDateParser.date(from: localDate) else { return nil }
        return Self.storyDateDisplay.string(from: date)
    }

    private func addToFeed(_ post: PostItem) {
        guard !addingToFeedIds.contains(post.post_id) else { return }
        addingToFeedIds.insert(post.post_id)
        Task {
            do {
                try await PostService.addPostToFeed(postId: post.post_id)
                // Reload so the promoted post re-splits into the grid.
                await load()
            } catch let APIError.apiError(message) where message == "post_window_closed" {
                await MainActor.run {
                    addToFeedError = "Feed posts belong to the day's walk or run, and today's has rolled over. Your story stays on your profile."
                }
            } catch {
                await MainActor.run {
                    addToFeedError = "This run may already have a feed post. Pull to refresh and try again."
                }
            }
            _ = await MainActor.run { addingToFeedIds.remove(post.post_id) }
        }
    }

    // MARK: - Thumbnail

    private func thumbnail(_ post: PostItem) -> some View {
        // The real picture leads when the run has one; the workout card is only
        // the face of the post when no photo exists.
        let url = post.storyPhotoURL ?? post.mediaURL
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                // The lock tile is for when the withheld photo WAS the tile —
                // an auto route/stats card that survived the gate still shows
                // its face, since only the picture is locked.
                Group {
                    if url == nil, post.isPhotoLocked {
                        ZStack {
                            LinearGradient(
                                colors: [MADTheme.Colors.madRed.opacity(0.30), Color.black.opacity(0.6)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                            Image(systemName: "lock.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    } else {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image): image.resizable().scaledToFill()
                            case .failure:
                                ZStack { Color.white.opacity(0.05); Image(systemName: "photo").foregroundColor(.white.opacity(0.3)) }
                            default:
                                ZStack { Color.white.opacity(0.05); ProgressView().tint(.white) }
                            }
                        }
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
            // Top-right says WHAT THE POST IS — a pin, a collab, more than one
            // slide. Stacked in one row rather than scattered to the corners so
            // two of them can't collide at 3-across.
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 3) {
                    if post.pinned_at != nil {
                        tileGlyph("pin.fill", color: .white)
                    }
                    if post.hasAcceptedCoauthor {
                        tileGlyph(
                            post.isMultiCollab ? "person.3.fill" : "person.2.fill",
                            color: .white
                        )
                    }
                    if post.hasExtraSlides {
                        tileGlyph("square.on.square", color: .white)
                    }
                }
                .padding(5)
            }
            // Bottom-left says WHAT THE WALK WAS. Distance beside the activity
            // icon: a grid of photos with no numbers on it is a photo album,
            // and this is a run log.
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 4) {
                    if let type = post.workout_type {
                        Image(systemName: ActivityCardView.icon(type))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(ActivityCardView.color(type))
                    }
                    if let miles = post.stats_snapshot?.distance, miles > 0 {
                        Text(miles.milesText)
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(Capsule().fill(.black.opacity(0.45)))
                .padding(5)
            }
            .overlay(alignment: .topLeading) {
                if post.stats_snapshot?.streak != nil {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(4)
                        .background(Circle().fill(.black.opacity(0.4)))
                        .padding(4)
                }
            }
    }

    private func tileGlyph(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(color)
            .padding(4)
            .background(Circle().fill(.black.opacity(0.45)))
    }

    private var emptyState: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: filter == .all ? "square.grid.3x3" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 34))
                .foregroundColor(.white.opacity(0.3))
            Text(emptyTitle)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            if filter != .all {
                // A filter that hides everything must say so, or an arranged
                // grid is indistinguishable from an empty one.
                Button("Show everything") { filterBinding.wrappedValue = .all }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(MADTheme.Colors.madRed)
            } else if isSelf {
                Text("Share a photo of your walk or run from the Feed tab.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, MADTheme.Spacing.xl)
        .padding(.horizontal, MADTheme.Spacing.lg)
    }

    private var emptyTitle: String {
        if filter != .all { return "Nothing matches \"\(filter.title)\"" }
        return isSelf ? "No posts yet" : "No posts to show"
    }

    // MARK: - Curating the grid

    private var currentUserId: String? {
        UserDefaults.standard.string(forKey: "backendUserId")
    }

    /// A grid cell, carrying a long-press menu ONLY where there's something to
    /// put in it — an empty `contextMenu` still pops a blank panel on
    /// long-press, so the modifier is branched rather than the menu left to
    /// build nothing. The branch is stable per post, so it can't thrash view
    /// identity inside the ForEach.
    @ViewBuilder
    private func gridThumbnail(_ post: PostItem, onTap: @escaping () -> Void) -> some View {
        if canCurateOnProfile(post) || isOwnPost(post) {
            Button(action: onTap) { thumbnail(post) }
                .buttonStyle(.plain)
                .contextMenu { gridContextMenu(post) }
        } else {
            Button(action: onTap) { thumbnail(post) }
                .buttonStyle(.plain)
        }
    }

    /// Mine to arrange: my own profile, and a post I actually authored.
    /// Deliberately not `is_self` — that's "you posted this", which is exactly
    /// what's wanted here, but only on your own grid.
    private func isOwnPost(_ post: PostItem) -> Bool {
        isSelf && post.user_id == currentUserId
    }

    /// Is this a collab the VIEWER is tagged in, on their own profile, from a
    /// server that knows about the grid split?
    private func canCurateOnProfile(_ post: PostItem) -> Bool {
        isSelf
            && post.hasAcceptedCoauthor
            && post.coauthor_user_id == currentUserId
            && post.coauthor_on_profile != nil
    }

    @ViewBuilder
    private func gridContextMenu(_ post: PostItem) -> some View {
        if isOwnPost(post) {
            Button {
                Task { await setPinned(post, pinned: post.pinned_at == nil) }
            } label: {
                Label(
                    post.pinned_at == nil ? "Pin to top of grid" : "Unpin",
                    systemImage: post.pinned_at == nil ? "pin" : "pin.slash"
                )
            }
            Button {
                editingHighlight = .newWithPost(post.post_id)
            } label: {
                Label("Save to a highlight", systemImage: "bookmark")
            }
            Button {
                Task { await setIncludeRoute(post, include: !(post.include_route ?? true)) }
            } label: {
                Label(
                    (post.include_route ?? true) ? "Hide the route map" : "Show the route map",
                    systemImage: (post.include_route ?? true) ? "map.slash" : "map"
                )
            }
        }
        collabProfileMenu(post)
    }

    /// Long-press a collab you're tagged in to pin it on or off your own Posts
    /// grid, or to stop it reaching your friends' feeds. Deliberately not
    /// destructive language: the tag survives either way and the post never
    /// leaves the Tagged tab.
    @ViewBuilder
    private func collabProfileMenu(_ post: PostItem) -> some View {
        if canCurateOnProfile(post) {
            if let onProfile = post.coauthor_on_profile {
                Button {
                    Task { await setCollabOnProfile(post, onProfile: !onProfile) }
                } label: {
                    Label(onProfile ? "Remove from my grid" : "Add to my grid",
                          systemImage: onProfile ? "minus.square" : "square.grid.3x3")
                }
            }
            // Separate from the grid switch on purpose: quieting the broadcast
            // shouldn't cost you the credit. Older servers omit the field, and
            // there's nothing to offer when the endpoint isn't there.
            if let onFeed = post.coauthor_on_feed {
                Button {
                    Task { await setCollabOnFeed(post, onFeed: !onFeed) }
                } label: {
                    Label(onFeed ? "Hide from my friends' feeds" : "Show in my friends' feeds",
                          systemImage: onFeed ? "eye.slash" : "eye")
                }
            }
            if let mine = post.acceptedCoauthors.first(where: { $0.user_id == currentUserId }) {
                let showing = mine.include_route ?? true
                Button {
                    Task { await setMyCrewRoute(post, include: !showing) }
                } label: {
                    Label(showing ? "Hide my route on this post" : "Show my route on this post",
                          systemImage: showing ? "map.slash" : "map")
                }
            }
        }
    }

    // MARK: - Mutations

    private func setPinned(_ post: PostItem, pinned: Bool) async {
        await MainActor.run { MADHaptics.tap() }
        do {
            try await PostService.setPostPinned(postId: post.post_id, pinned: pinned)
            await load()
        } catch APIError.conflict {
            await MainActor.run {
                pinError = "You can pin up to \(PostGridPreferences.pinLimit) posts. Unpin one to make room."
            }
        } catch {
            await MainActor.run { pinError = "Couldn't update your pins. Try again." }
        }
    }

    private func setIncludeRoute(_ post: PostItem, include: Bool) async {
        await MainActor.run {
            MADHaptics.tap()
            applyToLoadedCopies(of: post.post_id) { $0.include_route = include }
        }
        do {
            try await PostService.setPostIncludeRoute(postId: post.post_id, includeRoute: include)
        } catch {
            await MainActor.run {
                applyToLoadedCopies(of: post.post_id) { $0.include_route = !include }
            }
        }
    }

    private func setCollabOnFeed(_ post: PostItem, onFeed: Bool) async {
        await MainActor.run {
            MADHaptics.tap()
            applyToLoadedCopies(of: post.post_id) { $0.coauthor_on_feed = onFeed }
        }
        do {
            try await PostService.setCoauthorOnFeed(postId: post.post_id, onFeed: onFeed)
        } catch {
            await MainActor.run {
                applyToLoadedCopies(of: post.post_id) { $0.coauthor_on_feed = !onFeed }
            }
        }
    }

    private func setMyCrewRoute(_ post: PostItem, include: Bool) async {
        await MainActor.run {
            MADHaptics.tap()
            applyToLoadedCopies(of: post.post_id) { item in
                guard let idx = item.coauthors?.firstIndex(where: { $0.user_id == currentUserId })
                else { return }
                item.coauthors?[idx].include_route = include
            }
        }
        do {
            try await PostService.setCoauthorRoute(postId: post.post_id, includeRoute: include)
        } catch {
            await load()
        }
    }

    private func setCollabOnProfile(_ post: PostItem, onProfile: Bool) async {
        await MainActor.run {
            MADHaptics.tap()
            // Both grids can be showing the same collab, so keep them in step
            // or the Tagged tab offers "Remove from my grid" on something
            // that already left it.
            applyToLoadedCopies(of: post.post_id) { $0.coauthor_on_profile = onProfile }
            if !onProfile {
                posts.removeAll { $0.post_id == post.post_id }
                pinnedPosts.removeAll { $0.post_id == post.post_id }
            }
        }
        do {
            try await PostService.setCoauthorOnProfile(
                postId: post.post_id, onProfile: onProfile
            )
            // Re-pinned: it belongs back in date order, which only a reload
            // can place correctly (this page may not even reach that far back).
            if onProfile { await load() }
        } catch {
            await MainActor.run {
                applyToLoadedCopies(of: post.post_id) { $0.coauthor_on_profile = !onProfile }
            }
            if !onProfile { await load() }
        }
    }

    /// Apply an optimistic edit to every array that might be holding this post.
    /// The same post can be in the grid, the pinned row and the Tagged tab at
    /// once, and a menu that updates one of them leaves the others offering an
    /// action that has already happened.
    @MainActor
    private func applyToLoadedCopies(
        of postId: String,
        _ mutate: (inout PostItem) -> Void
    ) {
        for idx in posts.indices where posts[idx].post_id == postId { mutate(&posts[idx]) }
        for idx in pinnedPosts.indices where pinnedPosts[idx].post_id == postId { mutate(&pinnedPosts[idx]) }
        for idx in taggedPosts.indices where taggedPosts[idx].post_id == postId { mutate(&taggedPosts[idx]) }
        for idx in storyPosts.indices where storyPosts[idx].post_id == postId { mutate(&storyPosts[idx]) }
    }

    private func deleteHighlight(_ highlight: PostHighlight) async {
        await MainActor.run {
            MADHaptics.tap()
            highlights.removeAll { $0.highlight_id == highlight.highlight_id }
        }
        try? await PostService.deleteHighlight(highlightId: highlight.highlight_id)
        await loadHighlights()
    }

    // MARK: - Loading

    private func loadHighlights() async {
        let fetched = (try? await PostService.fetchHighlights(userId: userId)) ?? []
        await MainActor.run {
            highlights = fetched
            highlightsLoaded = true
        }
    }

    private func load() async {
        await MainActor.run { isLoading = posts.isEmpty && storyPosts.isEmpty }
        let response = try? await PostService.fetchUserPosts(
            userId: userId,
            before: nil,
            includeStories: isSelf,
            sort: sort,
            filter: filter,
            pinsSplit: true
        )
        await MainActor.run {
            if let response {
                posts = response.items.filter { $0.share_to_feed != false }
                storyPosts = response.items.filter { $0.share_to_feed == false }
                // Nil (an older server) is NOT an empty pin row — it means the
                // pins are still inline in `items`, exactly where they've
                // always been, and drawing an empty PINNED header above them
                // would be a lie about a grid that's fine.
                pinnedPosts = response.pinned ?? []
                nextBefore = response.next_before
            }
            isLoading = false
            loaded = true
        }
    }

    private func loadMore() async {
        guard let before = nextBefore, !isLoadingMore else { return }
        await MainActor.run { isLoadingMore = true }
        let response = try? await PostService.fetchUserPosts(
            userId: userId,
            before: before,
            includeStories: isSelf,
            sort: sort,
            filter: filter,
            pinsSplit: true
        )
        await MainActor.run {
            if let response {
                let existing = Set(posts.map(\.post_id) + storyPosts.map(\.post_id))
                let fresh = response.items.filter { !existing.contains($0.post_id) }
                posts.append(contentsOf: fresh.filter { $0.share_to_feed != false })
                storyPosts.append(contentsOf: fresh.filter { $0.share_to_feed == false })
                nextBefore = response.next_before
            }
            isLoadingMore = false
        }
    }

    private func loadTagged() async {
        await MainActor.run { isTaggedLoading = taggedPosts.isEmpty }
        let response = try? await PostService.fetchUserTaggedPosts(userId: userId)
        await MainActor.run {
            if let response {
                taggedPosts = response.items
                taggedNextBefore = response.next_before
            }
            isTaggedLoading = false
            taggedLoaded = true
        }
    }

    private func loadMoreTagged() async {
        guard let before = taggedNextBefore, !isTaggedLoadingMore else { return }
        await MainActor.run { isTaggedLoadingMore = true }
        let response = try? await PostService.fetchUserTaggedPosts(userId: userId, before: before)
        await MainActor.run {
            if let response {
                let existing = Set(taggedPosts.map(\.post_id))
                taggedPosts.append(contentsOf: response.items.filter { !existing.contains($0.post_id) })
                taggedNextBefore = response.next_before
            }
            isTaggedLoadingMore = false
        }
    }
}
