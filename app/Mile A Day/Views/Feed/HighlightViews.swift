import SwiftUI

/// What the highlight editor was opened for.
///
/// One sheet, three entry points: the rail's "New" button, a long-press on a
/// post ("save this one somewhere"), and editing an existing highlight. The
/// middle case is the important one — a story is the only thing in this app
/// that expires, so the moment someone wants to keep one is while they're
/// looking at it, not later from a menu on another screen.
enum HighlightEditorTarget: Identifiable {
    case new
    case newWithPost(String)
    case existing(PostHighlight)

    var id: String {
        switch self {
        case .new: return "new"
        case .newWithPost(let postId): return "new-\(postId)"
        case .existing(let highlight): return highlight.highlight_id
        }
    }

    var existing: PostHighlight? {
        if case .existing(let highlight) = self { return highlight }
        return nil
    }

    var seedPostId: String? {
        if case .newWithPost(let postId) = self { return postId }
        return nil
    }
}

// MARK: - Viewer

/// A highlight, opened: full-screen, one photo per page, tap the edges to move
/// through it. Deliberately a plain pager rather than the story viewer — a
/// highlight has no expiry, no unseen state and no viewer list, so the timed
/// auto-advance and the seen-ring bookkeeping would all be answering questions
/// this screen doesn't have.
struct HighlightViewerView: View {
    let highlight: PostHighlight
    let isSelf: Bool
    let onEdit: () -> Void
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [PostItem] = []
    @State private var index = 0
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var reportingPostId: String?
    @State private var blockConfirmation = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(.white)
            } else if items.isEmpty {
                emptyState
            } else {
                TabView(selection: $index) {
                    ForEach(Array(items.enumerated()), id: \.element.post_id) { offset, post in
                        slide(post).tag(offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
            }

            VStack(spacing: 10) {
                if items.count > 1 { progressBar }
                header
                Spacer()
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.top, MADTheme.Spacing.sm)
        }
        .task { await load() }
        // Presented BY this cover, not by whatever pushed it: a sheet attached
        // to the profile grid can't come up while this full-screen cover is on
        // top, which would make Report read as a dead button.
        .sheet(item: Binding(
            get: { reportingPostId.map { ReportTarget(postId: $0) } },
            set: { if $0 == nil { reportingPostId = nil } }
        )) { target in
            ReportPostSheet(postId: target.postId) { reportingPostId = nil }
        }
        .alert("Block this person?", isPresented: $blockConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Block", role: .destructive) { Task { await block() } }
        } message: {
            Text("You won't see each other's posts, walks or profiles, and any friendship between you ends.")
        }
    }

    private struct ReportTarget: Identifiable {
        let postId: String
        var id: String { postId }
    }

    private func block() async {
        try? await BlockService.block(userId: highlight.user_id)
        await MainActor.run {
            // The rail reloads behind us: blocking removes their whole profile
            // from view, so the circle this was opened from has to go too.
            onChanged()
            dismiss()
        }
    }

    /// One segment per slide, filled up to the current one. Static, not timed:
    /// nothing here advances on its own.
    private var progressBar: some View {
        HStack(spacing: 3) {
            ForEach(items.indices, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(i <= index ? 0.95 : 0.28))
                    .frame(height: 2.5)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(highlight.title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .shadow(radius: 4)
            if !items.isEmpty {
                Text("\(index + 1)/\(items.count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
            Spacer()
            // Someone else's photos: this is user-generated content on a
            // surface of its own, so it carries its own report and block —
            // every screen that shows another person's photo has to (App
            // Review 1.2), and the feed's card menu isn't reachable from here.
            if !isSelf {
                Menu {
                    Button {
                        reportingPostId = items.indices.contains(index)
                            ? items[index].post_id : nil
                    } label: {
                        Label("Report this photo", systemImage: "flag")
                    }
                    Button(role: .destructive) {
                        blockConfirmation = true
                    } label: {
                        Label("Block this person", systemImage: "hand.raised")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(.black.opacity(0.35)))
                }
            }
            if isSelf {
                Button {
                    dismiss()
                    // The editor is presented by the profile grid, not by this
                    // cover — two presentations from the same node race and one
                    // silently never appears.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onEdit() }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(.black.opacity(0.35)))
                }
                .buttonStyle(.plain)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Circle().fill(.black.opacity(0.35)))
            }
            .buttonStyle(.plain)
        }
    }

    private func slide(_ post: PostItem) -> some View {
        GeometryReader { geo in
            ZStack {
                AsyncImage(url: post.storyPhotoURL ?? post.mediaURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        Image(systemName: "photo")
                            .font(.system(size: 44))
                            .foregroundColor(.white.opacity(0.3))
                    default:
                        ProgressView().tint(.white)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)

                // Tap zones. A pager already swipes; these are for the thumb
                // that's holding the phone one-handed.
                HStack(spacing: 0) {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { step(-1) }
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { step(1) }
                }

                VStack {
                    Spacer()
                    caption(post)
                }
            }
        }
    }

    @ViewBuilder
    private func caption(_ post: PostItem) -> some View {
        let miles = post.stats_snapshot?.distance
        if (post.caption?.isEmpty == false) || (miles ?? 0) > 0 {
            VStack(alignment: .leading, spacing: 4) {
                if let miles, miles > 0 {
                    Text("\(miles.milesText) mi")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                }
                if let caption = post.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MADTheme.Spacing.md)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.65)],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: loadFailed ? "wifi.slash" : "bookmark")
                .font(.system(size: 36))
                .foregroundColor(.white.opacity(0.35))
            Text(loadFailed ? "Couldn't load this highlight" : "Nothing left in here")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            if !loadFailed {
                // Members resolve at read time, so a highlight empties itself
                // when its posts are deleted or go private. Say that, rather
                // than showing a blank screen that looks broken.
                Text(isSelf
                     ? "The posts in this highlight were deleted or made private."
                     : "These posts aren't shared any more.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MADTheme.Spacing.lg)
            }
            Button("Close") { dismiss() }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(MADTheme.Colors.madRed)
                .padding(.top, 4)
        }
    }

    private func step(_ delta: Int) {
        let next = index + delta
        guard next >= 0 else { return }
        guard next < items.count else {
            dismiss()
            return
        }
        withAnimation(.easeInOut(duration: 0.18)) { index = next }
    }

    private func load() async {
        do {
            let detail = try await PostService.fetchHighlight(
                highlightId: highlight.highlight_id
            )
            await MainActor.run {
                items = detail.items
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadFailed = true
                isLoading = false
            }
        }
    }
}

// MARK: - Editor

/// Create or edit a highlight: name it, pick which of your own posts are in
/// it, and choose the cover.
///
/// Selection order IS the order the highlight plays in, which is why the
/// picked row is drawn separately above the library — dragging tiles around a
/// grid to express order is a worse gesture than tapping them in the order you
/// want, and the row shows you the answer as you build it.
struct HighlightEditorView: View {
    let userId: String
    let target: HighlightEditorTarget
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    /// Ordered — position in this array becomes the highlight's play order.
    @State private var selected: [String] = []
    @State private var coverPostId: String?
    /// A cover picked from the camera roll this session, not uploaded yet —
    /// uploading on Save means a cancelled edit costs nothing and a bad
    /// connection fails once, where the user is already being told about it.
    @State private var pickedCover: UIImage?
    /// The uploaded cover already on the highlight, if it has one.
    @State private var coverImageUrl: String?
    /// The user chose a post's photo over the uploaded cover, so Save has to
    /// say so out loud — an omitted field means "leave it alone", which would
    /// keep drawing the cover they just replaced.
    @State private var coverCleared = false
    @State private var showingCoverPicker = false
    @State private var showingCoverCropper = false
    @State private var pickedFromLibrary: UIImage?
    @State private var library: [PostItem] = []
    /// The members this highlight already holds, from its own detail read.
    /// The library is paginated, so an older member — including the one that
    /// is the cover — often isn't on the first page, and looking a thumbnail
    /// up in the library alone drew the strip and the cover circle blank.
    @State private var memberPosts: [String: PostItem] = [:]
    @State private var nextBefore: String?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    private var isNew: Bool { target.existing == nil }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !selected.isEmpty
            && !isSaving
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                        coverField
                        nameField
                        if !selected.isEmpty { selectionStrip }
                        libraryGrid
                    }
                    .padding(MADTheme.Spacing.md)
                    .padding(.bottom, 60)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(isNew ? "New Highlight" : "Edit Highlight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .fontWeight(.bold)
                        .foregroundColor(canSave ? MADTheme.Colors.madRed : .white.opacity(0.3))
                        .disabled(!canSave)
                }
            }
            .alert("Couldn't save", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showingCoverPicker) {
                ImagePicker(selectedImage: $pickedFromLibrary)
            }
            // The rail draws covers in a circle, so the crop is the same one
            // the profile photo gets — what you frame here is what shows.
            .fullScreenCover(isPresented: $showingCoverCropper) {
                if let image = pickedFromLibrary {
                    ProfileImageCropper(
                        image: image,
                        onCrop: { cropped in
                            pickedCover = cropped
                            coverCleared = false
                            showingCoverCropper = false
                            pickedFromLibrary = nil
                            MADHaptics.tap()
                        },
                        onCancel: {
                            showingCoverCropper = false
                            pickedFromLibrary = nil
                        }
                    )
                }
            }
            .onChange(of: pickedFromLibrary) { _, newImage in
                if newImage != nil { showingCoverCropper = true }
            }
        }
        .task { await load() }
    }

    // MARK: - Cover

    /// Is the circle currently a photo from the camera roll rather than one of
    /// the posts inside?
    private var usesCustomCover: Bool {
        pickedCover != nil || (!coverCleared && coverImageUrl?.isEmpty == false)
    }

    /// A picked post by id, from whichever of the two sources has it.
    private func pickedPost(_ postId: String) -> PostItem? {
        library.first { $0.post_id == postId } ?? memberPosts[postId]
    }

    /// The post whose photo would be the cover if there were no uploaded one.
    private var coverPost: PostItem? {
        guard let id = coverPostId ?? selected.first else { return nil }
        return pickedPost(id)
    }

    private var coverField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("COVER")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.45))
            HStack(spacing: MADTheme.Spacing.md) {
                coverPreview
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        MADHaptics.tap()
                        showingCoverPicker = true
                    } label: {
                        Label(
                            usesCustomCover ? "Change cover photo" : "Choose a cover photo",
                            systemImage: "photo.on.rectangle"
                        )
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, MADTheme.Spacing.md)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(Color.white.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)

                    if usesCustomCover {
                        Button {
                            MADHaptics.tap()
                            pickedCover = nil
                            coverCleared = true
                        } label: {
                            Text("Use a photo from inside instead")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("Or tap a photo below to use it as the cover.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var coverPreview: some View {
        Group {
            if let pickedCover {
                Image(uiImage: pickedCover).resizable().scaledToFill()
            } else if !coverCleared,
                      let coverImageUrl,
                      !coverImageUrl.isEmpty,
                      let url = ProfileImageService.fullImageURL(for: coverImageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: Color.white.opacity(0.06)
                    }
                }
            } else if let post = coverPost {
                AsyncImage(url: post.storyPhotoURL ?? post.mediaURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: Color.white.opacity(0.06)
                    }
                }
            } else {
                ZStack {
                    Color.white.opacity(0.06)
                    Image(systemName: "photo")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(MADTheme.Colors.madRed.opacity(0.8), lineWidth: 2)
        )
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NAME")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.45))
            TextField("", text: $title, prompt: Text("Sunday loops").foregroundColor(.white.opacity(0.3)))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                // Matches the server's CHECK; a longer name is rejected there,
                // and being stopped at the keyboard beats being stopped on Save.
                .onChange(of: title) { _, newValue in
                    if newValue.count > 30 { title = String(newValue.prefix(30)) }
                }
        }
    }

    /// The picked posts in play order, with the cover marked. Tapping one
    /// makes it the cover; the ✕ removes it.
    private var selectionStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(usesCustomCover
                 ? "IN THIS HIGHLIGHT · TAP ONE TO USE IT AS THE COVER"
                 : "IN THIS HIGHLIGHT · TAP TO SET THE COVER")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundColor(.white.opacity(0.45))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(selected.enumerated()), id: \.element) { position, postId in
                        selectionTile(postId: postId, position: position)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func selectionTile(postId: String, position: Int) -> some View {
        let post = pickedPost(postId)
        // A highlight has ONE cover: picking a post's photo has to retire the
        // uploaded one, or the tap does nothing visible and reads as broken.
        let isCover = coverPostId == postId && !usesCustomCover
        return Button {
            MADHaptics.tap()
            coverPostId = postId
            pickedCover = nil
            if coverImageUrl?.isEmpty == false { coverCleared = true }
        } label: {
            AsyncImage(url: post?.storyPhotoURL ?? post?.mediaURL) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: Color.white.opacity(0.06)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isCover ? MADTheme.Colors.madRed : Color.white.opacity(0.12),
                        lineWidth: isCover ? 2 : 1
                    )
            )
            .overlay(alignment: .bottomLeading) {
                Text("\(position + 1)")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(4)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    MADHaptics.tap()
                    remove(postId)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Circle().fill(.black.opacity(0.6)))
                }
                .buttonStyle(.plain)
                .padding(3)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var libraryGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR POSTS & STORIES")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundColor(.white.opacity(0.45))

            if isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, MADTheme.Spacing.lg)
            } else if library.isEmpty {
                Text("Share a photo of a walk or run and it'll show up here.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, MADTheme.Spacing.sm)
            } else {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(library) { post in
                        libraryTile(post)
                            .onAppear {
                                if post.id == library.last?.id { Task { await loadMore() } }
                            }
                    }
                }
            }
        }
    }

    private func libraryTile(_ post: PostItem) -> some View {
        let position = selected.firstIndex(of: post.post_id)
        return Button {
            MADHaptics.tap()
            toggle(post.post_id)
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    AsyncImage(url: post.storyPhotoURL ?? post.mediaURL) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: Color.white.opacity(0.05)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            position != nil ? MADTheme.Colors.madRed : Color.white.opacity(0.06),
                            lineWidth: position != nil ? 2 : 0.5
                        )
                )
                .overlay(alignment: .topTrailing) {
                    // The badge carries the ORDER, not just a tick: selection
                    // order is what the highlight plays in, so it has to be
                    // visible while you're picking.
                    ZStack {
                        Circle()
                            .fill(position != nil ? MADTheme.Colors.madRed : Color.black.opacity(0.35))
                            .frame(width: 20, height: 20)
                        if let position {
                            Text("\(position + 1)")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(5)
                }
                .overlay(alignment: .bottomLeading) {
                    if post.share_to_feed == false {
                        Text("STORY")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .tracking(0.6)
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.black.opacity(0.5)))
                            .padding(5)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selection

    private func toggle(_ postId: String) {
        if selected.contains(postId) {
            remove(postId)
        } else {
            selected.append(postId)
            if coverPostId == nil { coverPostId = postId }
        }
    }

    private func remove(_ postId: String) {
        selected.removeAll { $0 == postId }
        // The cover must stay a member, or the rail draws a photo the
        // highlight no longer holds — the server refuses it anyway.
        if coverPostId == postId { coverPostId = selected.first }
    }

    // MARK: - Loading / saving

    private func load() async {
        // Seed from the existing highlight first so the picker opens showing
        // what's already in it, in the order it plays.
        if let existing = target.existing {
            await MainActor.run {
                title = existing.title
                coverPostId = existing.cover_post_id
                coverImageUrl = existing.cover_image_url
            }
            if let detail = try? await PostService.fetchHighlight(
                highlightId: existing.highlight_id
            ) {
                var byId: [String: PostItem] = [:]
                for item in detail.items { byId[item.post_id] = item }
                await MainActor.run {
                    selected = detail.items.map(\.post_id)
                    memberPosts = byId
                }
            }
        } else if let seed = target.seedPostId {
            await MainActor.run {
                selected = [seed]
                coverPostId = seed
            }
        }

        let response = try? await PostService.fetchUserPosts(
            userId: userId,
            before: nil,
            // Stories are the whole point of a highlight, so the picker has to
            // offer the ones that never reached the feed.
            includeStories: true,
            pinsSplit: false
        )
        await MainActor.run {
            library = response?.items ?? []
            nextBefore = response?.next_before
            isLoading = false
        }
    }

    private func loadMore() async {
        guard let before = nextBefore else { return }
        await MainActor.run { nextBefore = nil }
        let response = try? await PostService.fetchUserPosts(
            userId: userId, before: before, includeStories: true, pinsSplit: false
        )
        await MainActor.run {
            let existing = Set(library.map(\.post_id))
            library.append(contentsOf: (response?.items ?? []).filter { !existing.contains($0.post_id) })
            nextBefore = response?.next_before
        }
    }

    private func save() async {
        guard canSave else { return }
        await MainActor.run { isSaving = true }
        defer { Task { @MainActor in isSaving = false } }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            // A picked cover is uploaded here, not when it was chosen: an edit
            // that gets cancelled should leave nothing behind on the server.
            // The empty string is how "drop the uploaded cover" is spelled —
            // an omitted field means "leave it alone" (see updateHighlight).
            var coverImage: String? = nil
            if let pickedCover {
                coverImage = try await PostService.uploadMedia(pickedCover)
            } else if coverCleared {
                coverImage = ""
            }
            if let existing = target.existing {
                try await PostService.updateHighlight(
                    highlightId: existing.highlight_id,
                    title: name,
                    postIds: selected,
                    coverPostId: coverPostId,
                    coverImageUrl: coverImage
                )
            } else {
                try await PostService.createHighlight(
                    title: name,
                    postIds: selected,
                    coverPostId: coverPostId,
                    // Nothing to clear on a highlight that doesn't exist yet.
                    coverImageUrl: coverImage?.isEmpty == false ? coverImage : nil
                )
            }
            await MainActor.run {
                MADHaptics.success()
                onSaved()
                dismiss()
            }
        // Only the cover upload throws a PostError here; every other leg of
        // this save is an APIError, so the message can name the real failure.
        } catch is PostError {
            await MainActor.run {
                errorMessage = "Couldn't upload that cover photo. Check your connection and try again."
            }
        } catch let APIError.apiError(message) where message == "highlight_limit_reached" {
            await MainActor.run {
                errorMessage = "You've reached the highlight limit. Delete one to make room."
            }
        } catch {
            await MainActor.run {
                errorMessage = "Couldn't save that highlight. Check your connection and try again."
            }
        }
    }
}
