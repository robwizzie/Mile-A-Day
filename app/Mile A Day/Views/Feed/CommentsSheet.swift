import SwiftUI

/// Instagram's comments sheet in Mile A Day's language: flat top-level
/// comments, one level of replies collapsed behind "View N replies", a pinned
/// input bar with a "Replying to" state, and @friend autocomplete. Long-press
/// a comment to delete (yours, or any on your own/co-authored post) or report.
struct CommentsSheet: View {
    /// The post's caption, shown at the top of the thread the way Instagram
    /// does: the author's words first, then the conversation about them.
    struct CaptionHeader {
        let userId: String
        let username: String?
        let firstName: String?
        let lastName: String?
        let profileImageURL: String?
        let displayName: String
        let text: String
        let relativeTime: String

        /// Nil when the post has no caption worth showing.
        init?(post: PostItem) {
            guard let caption = post.caption?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !caption.isEmpty else { return nil }
            userId = post.user_id
            username = post.username
            firstName = post.first_name
            lastName = post.last_name
            profileImageURL = post.profile_image_url
            displayName = post.displayName
            text = caption
            relativeTime = post.relativeTime
        }
    }

    let target: CommentTarget
    let captionHeader: CaptionHeader?
    /// True when the current user authors/co-authors this feed item (may
    /// delete any comment on it).
    let canModerate: Bool
    /// Reports the latest comment count back to the feed card.
    var onCountChange: ((Int) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var comments: [PostComment] = []
    @State private var isLoading = true
    @State private var failed = false
    @State private var draft = ""
    @State private var replyingTo: PostComment?
    @State private var expandedThreads: Set<String> = []
    @State private var isSending = false
    @State private var reportingComment: PostComment?
    @State private var showTermsGate = false
    @State private var termsJustAccepted = false
    @State private var errorMessage: String?
    /// Profile opened from a tapped @mention inside a comment.
    @State private var profileUser: BackendUser?
    /// A long caption starts folded, like Instagram's "… more".
    @State private var captionExpanded = false
    @StateObject private var friendService = FriendService()
    @FocusState private var inputFocused: Bool

    init(
        post: PostItem,
        canModerate: Bool,
        onCountChange: ((Int) -> Void)? = nil
    ) {
        self.target = .post(post.post_id)
        self.captionHeader = CaptionHeader(post: post)
        self.canModerate = canModerate
        self.onCountChange = onCountChange
    }

    init(
        target: CommentTarget,
        canModerate: Bool,
        onCountChange: ((Int) -> Void)? = nil
    ) {
        self.target = target
        self.captionHeader = nil
        self.canModerate = canModerate
        self.onCountChange = onCountChange
    }

    private var topLevel: [PostComment] { comments.filter { $0.parent_comment_id == nil } }
    private func replies(to comment: PostComment) -> [PostComment] {
        comments.filter { $0.parent_comment_id == comment.comment_id }
    }

    /// Friends matching the @token being typed at the end of the draft.
    /// Explicit types throughout — inference across filter/prefix chains is
    /// what makes the type checker crawl.
    private var mentionCandidates: [BackendUser] {
        guard let token = draft.split(separator: " ").last, token.hasPrefix("@") else { return [] }
        let query: String = String(token.dropFirst()).lowercased()
        let matches: [BackendUser] = friendService.friends.filter { friend in
            guard let name = friend.username?.lowercased() else { return false }
            return query.isEmpty || name.hasPrefix(query)
        }
        return Array(matches.prefix(8))
    }

    private var draftIsEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var viewerName: String {
        let user = UserManager.shared.currentUser
        if let username = user.username, !username.isEmpty { return username }
        if !user.name.isEmpty { return user.name }
        return "You"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    commentsHeader
                    Divider().overlay(Color.white.opacity(0.10))
                    content
                    inputBar
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            await load()
            try? await friendService.loadFriends()
        }
        .sheet(item: $reportingComment) { comment in
            ReportCommentSheet(commentId: comment.comment_id) { reportingComment = nil }
        }
        .sheet(item: $profileUser) { user in
            NavigationStack {
                UserProfileDetailView(user: user, friendService: friendService)
            }
        }
        .sheet(isPresented: $showTermsGate, onDismiss: {
            // Re-send the kept draft ONLY when the gate was actually accepted —
            // a "Not now" dismissal must not loop back into the gate.
            if termsJustAccepted {
                termsJustAccepted = false
                if !draft.isEmpty { Task { await send() } }
            }
        }) {
            PostTermsGateView { termsJustAccepted = true }
        }
        .alert("Couldn't post comment", isPresented: Binding<Bool>(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var commentsHeader: some View {
        ZStack {
            Text("Comments")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.72))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close comments")
            }
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        if let captionHeader {
            // With a caption, it leads and scrolls with the thread; the
            // loading / empty states sit under it instead of centring.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    captionRow(captionHeader)
                    Divider()
                        .overlay(Color.white.opacity(0.08))
                        .padding(.horizontal, MADTheme.Spacing.md)
                        .padding(.bottom, 4)
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: MADTheme.Colors.madRed))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if failed {
                        stateMessage(icon: "wifi.slash", text: "Couldn't load comments")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if comments.isEmpty {
                        stateMessage(icon: "bubble.left.and.bubble.right", text: "No comments yet",
                                     detail: "Be the first to cheer them on")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(topLevel) { comment in
                                thread(comment)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                }
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        } else if isLoading {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: MADTheme.Colors.madRed))
            Spacer()
        } else if failed {
            Spacer()
            stateMessage(icon: "wifi.slash", text: "Couldn't load comments")
            Spacer()
        } else if comments.isEmpty {
            Spacer()
            stateMessage(icon: "bubble.left.and.bubble.right", text: "No comments yet",
                         detail: "Be the first to cheer them on")
            Spacer()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(topLevel) { comment in
                        thread(comment)
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    @ViewBuilder
    private func thread(_ comment: PostComment) -> some View {
        let kids = replies(to: comment)
        row(comment, isReply: false)
        if !kids.isEmpty {
            if expandedThreads.contains(comment.comment_id) {
                ForEach(kids) { reply in
                    row(reply, isReply: true)
                }
                threadToggle("Hide replies", comment: comment)
            } else {
                threadToggle("View \(kids.count) \(kids.count == 1 ? "reply" : "replies")", comment: comment)
            }
        }
    }

    private func threadToggle(_ label: String, comment: PostComment) -> some View {
        Button {
            if expandedThreads.contains(comment.comment_id) {
                expandedThreads.remove(comment.comment_id)
            } else {
                expandedThreads.insert(comment.comment_id)
            }
        } label: {
            HStack(spacing: 8) {
                Rectangle().fill(Color.white.opacity(0.25)).frame(width: 24, height: 1)
                Text(label)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(.leading, 64)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A tapped @mention: resolve the username (exact, case-insensitive) via
    /// the search endpoint and open that profile. No-ops for unknown names and
    /// for the viewer themself.
    /// The person who wrote this comment.
    ///
    /// Built straight from the comment row rather than routed through
    /// `openMentionProfile`, which has to hit the network to turn a username
    /// back into a user — everything the profile needs is already on the
    /// comment. Never the viewer themselves.
    private func openCommenter(_ comment: PostComment) {
        guard comment.user_id != UserDefaults.standard.string(forKey: "backendUserId")
        else { return }
        profileUser = BackendUser(
            user_id: comment.user_id,
            username: comment.username,
            email: nil,
            first_name: comment.first_name,
            last_name: comment.last_name,
            bio: nil,
            profile_image_url: comment.profile_image_url,
            apple_id: nil,
            auth_provider: nil,
            role: nil
        )
    }

    private func openMentionProfile(_ username: String) {
        let lowered = username.lowercased()
        Task {
            guard let match = try? await friendService.searchUsers(byUsername: lowered)
                .first(where: { $0.username?.lowercased() == lowered }) else { return }
            await MainActor.run {
                guard match.user_id != UserDefaults.standard.string(forKey: "backendUserId") else { return }
                profileUser = match
            }
        }
    }

    /// The caption, laid out like a comment (avatar, name, time, text) so it
    /// reads as the first word in the thread, without Reply or a menu.
    private func captionRow(_ caption: CaptionHeader) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Button { openAuthor(caption) } label: {
                AvatarView(name: caption.displayName, imageURL: caption.profileImageURL, size: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(caption.displayName)'s profile")
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Button { openAuthor(caption) } label: {
                        Text(caption.displayName)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    Text(caption.relativeTime)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }
                Text(MentionText.attributed(caption.text))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(captionExpanded ? nil : Self.captionFoldLines)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.openURL, OpenURLAction { url in
                        if let username = MentionText.username(from: url) {
                            openMentionProfile(username)
                            return .handled
                        }
                        return .systemAction
                    })
                if !captionExpanded, Self.captionMightFold(caption.text) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { captionExpanded = true }
                    } label: {
                        Text("more")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
    }

    private static let captionFoldLines = 6

    /// Cheap stand-in for "is it taller than the fold": many line breaks or
    /// enough characters to wrap past it on a phone.
    private static func captionMightFold(_ text: String) -> Bool {
        text.count > 240 || text.filter { $0 == "\n" }.count >= captionFoldLines
    }

    /// The post's author, built from the post itself (no lookup needed).
    private func openAuthor(_ caption: CaptionHeader) {
        guard caption.userId != UserDefaults.standard.string(forKey: "backendUserId") else { return }
        profileUser = BackendUser(
            user_id: caption.userId,
            username: caption.username,
            email: nil,
            first_name: caption.firstName,
            last_name: caption.lastName,
            bio: nil,
            profile_image_url: caption.profileImageURL,
            apple_id: nil,
            auth_provider: nil,
            role: nil
        )
    }

    private func row(_ comment: PostComment, isReply: Bool) -> some View {
        HStack(alignment: .top, spacing: 11) {
            // Avatar and name both open the commenter, the way a comment
            // thread anywhere else does — they were the only people on this
            // screen you couldn't reach.
            Button { openCommenter(comment) } label: {
                AvatarView(name: comment.displayName,
                           imageURL: comment.profile_image_url,
                           size: isReply ? 28 : 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(comment.displayName)'s profile")
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Button { openCommenter(comment) } label: {
                        Text(comment.displayName)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    Text(comment.relativeTime)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer(minLength: 8)
                    commentMenu(comment)
                }
                Text(MentionText.attributed(comment.content))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    // Tapping an @mention opens that user's profile, same as
                    // post captions.
                    .environment(\.openURL, OpenURLAction { url in
                        if let username = MentionText.username(from: url) {
                            openMentionProfile(username)
                            return .handled
                        }
                        return .systemAction
                    })
                Button {
                    replyingTo = comment
                    // Instagram prefills the @handle when replying.
                    if let username = comment.username, !username.isEmpty {
                        draft = "@\(username) "
                    }
                    inputFocused = true
                } label: {
                    Text("Reply")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.leading, isReply ? 45 : 0)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            commentActions(comment)
        }
    }

    private func commentMenu(_ comment: PostComment) -> some View {
        Menu {
            commentActions(comment)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white.opacity(0.38))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func commentActions(_ comment: PostComment) -> some View {
        if comment.is_self || canModerate {
            Button(role: .destructive) {
                Task { await delete(comment) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        if !comment.is_self {
            Button {
                reportingComment = comment
            } label: {
                Label("Report", systemImage: "flag")
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            if !mentionCandidates.isEmpty && inputFocused {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(mentionCandidates, id: \.user_id) { friend in
                            mentionChip(friend)
                        }
                    }
                    .padding(.horizontal, MADTheme.Spacing.md)
                }
                .padding(.vertical, 8)
            }
            if let replyingTo {
                // Two plain Texts, NOT `Text + Text` — the concat overload is a
                // known Swift type-checker explosion that hangs the build.
                HStack(spacing: 0) {
                    Text("Replying to ")
                        .foregroundColor(.white.opacity(0.55))
                    Text(replyingTo.displayName)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Spacer()
                    Button {
                        self.replyingTo = nil
                        draft = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.05))
            }
            Divider().overlay(Color.white.opacity(0.1))
            HStack(alignment: .bottom, spacing: 10) {
                AvatarView(
                    name: viewerName,
                    imageURL: UserManager.shared.currentUser.profileImageUrl,
                    size: 32
                )
                TextField("Add a comment…", text: $draft, axis: .vertical)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Color.white.opacity(inputFocused ? 0.18 : 0.08), lineWidth: 1)
                            )
                    )
                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(width: 44, height: 34)
                    } else {
                        Text("Post")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundColor(draftIsEmpty ? .white.opacity(0.32) : MADTheme.Colors.madRed)
                            .frame(width: 44, height: 34)
                    }
                }
                .disabled(isSending || draftIsEmpty)
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, 11)
        }
        .background(Color.black.opacity(0.32))
    }

    private func stateMessage(icon: String, text: String, detail: String? = nil) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundColor(.white.opacity(0.3))
            Text(text)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            if let detail {
                Text(detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        do {
            comments = try await CommentService.list(target: target)
            isLoading = false
            onCountChange?(comments.count)
        } catch {
            isLoading = false
            failed = true
        }
    }

    private func mentionChip(_ friend: BackendUser) -> some View {
        Button {
            completeMention(friend)
        } label: {
            HStack(spacing: 6) {
                AvatarView(name: friend.username ?? "?",
                           imageURL: friend.profile_image_url, size: 24)
                Text("@\(friend.username ?? "")")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func completeMention(_ friend: BackendUser) {
        guard let username = friend.username, !username.isEmpty else { return }
        var parts = draft.split(separator: " ", omittingEmptySubsequences: false)
        if let last = parts.last, last.hasPrefix("@") { parts.removeLast() }
        draft = (parts + ["@\(username) "]).joined(separator: " ")
    }

    private func send() async {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isSending else { return }
        guard content.count <= CommentService.maxLength else {
            errorMessage = "Comments are capped at \(CommentService.maxLength) characters."
            return
        }
        isSending = true
        defer { isSending = false }
        do {
            let created = try await CommentService.add(
                target: target,
                content: content,
                parentCommentId: replyingTo.map { $0.parent_comment_id ?? $0.comment_id }
            )
            comments.append(created)
            if let parent = created.parent_comment_id { expandedThreads.insert(parent) }
            draft = ""
            replyingTo = nil
            onCountChange?(comments.count)
        } catch APIError.apiError("terms_not_accepted") {
            // First-time commenter: run the same UGC terms gate as posting,
            // keeping the draft to auto-send after acceptance.
            showTermsGate = true
        } catch {
            errorMessage = "Check your connection and try again."
        }
    }

    private func delete(_ comment: PostComment) async {
        // Optimistic: remove the thread locally, restore on failure.
        let removedIds = Set([comment.comment_id] + replies(to: comment).map(\.comment_id))
        let backup = comments
        comments.removeAll { removedIds.contains($0.comment_id) }
        onCountChange?(comments.count)
        do {
            try await CommentService.delete(commentId: comment.comment_id)
        } catch {
            comments = backup
            onCountChange?(comments.count)
        }
    }
}

/// Mirror of ReportPostSheet for comments — same reasons, same moderation
/// queue (App Store 1.2).
struct ReportCommentSheet: View {
    let commentId: String
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: String?
    @State private var isSubmitting = false
    @State private var submitted = false

    private let reasons: [(String, String)] = [
        ("spam", "Spam"),
        ("nudity", "Nudity or sexual content"),
        ("harassment", "Harassment or bullying"),
        ("violence", "Violence or dangerous acts"),
        ("other", "Something else"),
    ]

    private var submitFill: AnyShapeStyle {
        selected == nil
            ? AnyShapeStyle(Color.gray.opacity(0.4))
            : AnyShapeStyle(MADTheme.Colors.redGradient)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
                VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                    if submitted {
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.green)
                            Text("Thanks — we'll take a look")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Text("Why are you reporting this comment?")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.top, MADTheme.Spacing.md)
                        ForEach(reasons, id: \.0) { reason in
                            Button {
                                selected = reason.0
                            } label: {
                                HStack {
                                    Text(reason.1)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Image(systemName: selected == reason.0 ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(selected == reason.0 ? MADTheme.Colors.madRed : .white.opacity(0.3))
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                        .fill(Color.white.opacity(0.05))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                        Button {
                            Task { await submit() }
                        } label: {
                            Group {
                                if isSubmitting {
                                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text("Submit report")
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(submitFill))
                        }
                        .disabled(selected == nil || isSubmitting)
                    }
                }
                .padding(.horizontal, MADTheme.Spacing.lg)
                .padding(.bottom, MADTheme.Spacing.lg)
            }
            .navigationTitle("Report comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss(); onDone() }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func submit() async {
        guard let selected else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await CommentService.report(commentId: commentId, reason: selected)
            submitted = true
            try? await Task.sleep(for: .seconds(1.2))
            dismiss()
            onDone()
        } catch {
            // Repeat reports are idempotent server-side; treat any failure softly.
            submitted = true
            try? await Task.sleep(for: .seconds(1.2))
            dismiss()
            onDone()
        }
    }
}
