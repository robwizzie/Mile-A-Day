import SwiftUI

/// Instagram's comments sheet in Mile A Day's language: flat top-level
/// comments, one level of replies collapsed behind "View N replies", a pinned
/// input bar with a "Replying to" state, and @friend autocomplete. Long-press
/// a comment to delete (yours, or any on your own/co-authored post) or report.
struct CommentsSheet: View {
    let target: CommentTarget
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
    @StateObject private var friendService = FriendService()
    @FocusState private var inputFocused: Bool

    init(
        post: PostItem,
        canModerate: Bool,
        onCountChange: ((Int) -> Void)? = nil
    ) {
        self.target = .post(post.post_id)
        self.canModerate = canModerate
        self.onCountChange = onCountChange
    }

    init(
        target: CommentTarget,
        canModerate: Bool,
        onCountChange: ((Int) -> Void)? = nil
    ) {
        self.target = target
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

    private var sendFill: AnyShapeStyle {
        draftIsEmpty
            ? AnyShapeStyle(Color.white.opacity(0.15))
            : AnyShapeStyle(MADTheme.Colors.redGradient)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    content
                    inputBar
                }
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(MADTheme.Colors.madRed)
                }
            }
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

    @ViewBuilder
    private var content: some View {
        if isLoading {
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
                .padding(.vertical, MADTheme.Spacing.sm)
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
            .padding(.leading, 62)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A tapped @mention: resolve the username (exact, case-insensitive) via
    /// the search endpoint and open that profile. No-ops for unknown names and
    /// for the viewer themself.
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

    private func row(_ comment: PostComment, isReply: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(name: comment.displayName,
                       imageURL: comment.profile_image_url,
                       size: isReply ? 28 : 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(comment.displayName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(comment.relativeTime)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
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
        .padding(.leading, isReply ? 44 : 0)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
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
            HStack(spacing: 10) {
                TextField("Add a comment…", text: $draft, axis: .vertical)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(width: 36, height: 36)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(sendFill))
                    }
                }
                .disabled(isSending || draftIsEmpty)
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, 10)
        }
        .background(Color.black.opacity(0.25))
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
