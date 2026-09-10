import SwiftUI

/// Edit the caption of one of the user's own posts — reachable from the feed
/// card menu, the profile posts sheet, and the workout detail's linked post.
/// Saves through PATCH /posts/:postId and hands the trimmed caption back so
/// the presenting view can update in place without a refetch.
struct EditCaptionSheet: View {
    /// Whose words this sheet is editing.
    ///
    /// A buddy walk is ONE post with several people's pictures on it, and each
    /// picture carries its own caption. The author's is `posts.caption`; a
    /// credited participant's is their row in `post_coauthors`. Same editor,
    /// two different things being written — so the mode is explicit rather
    /// than inferred from `is_self`, which is the server's "you POSTED this"
    /// and is false for exactly the person this second mode exists for.
    enum Subject {
        /// The post's own caption. Author only.
        case post
        /// My own slide's caption on a walk I'm credited on.
        case myCollabSlide
    }

    let post: PostItem
    var subject: Subject = .post
    /// Called after a successful save with the new caption (nil when cleared).
    let onSaved: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private static let maxLength = 280

    init(post: PostItem, subject: Subject = .post, onSaved: @escaping (String?) -> Void) {
        self.post = post
        self.subject = subject
        self.onSaved = onSaved
        switch subject {
        case .post:
            _text = State(initialValue: post.caption ?? "")
        case .myCollabSlide:
            let me = UserDefaults.standard.string(forKey: "backendUserId")
            let mine = post.acceptedCoauthors.first { $0.user_id == me }
            _text = State(initialValue: mine?.caption ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                    TextField("Write a caption…", text: $text, axis: .vertical)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(3...8)
                        .focused($focused)
                        .padding(MADTheme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                        .onChange(of: text) { _, newValue in
                            if newValue.count > Self.maxLength {
                                text = String(newValue.prefix(Self.maxLength))
                            }
                        }

                    HStack {
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.red)
                        }
                        // Anchored dismiss for the multi-line keyboard (Return
                        // adds newlines) — same inline pattern as the composer.
                        if focused {
                            Button {
                                focused = false
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "keyboard.chevron.compact.down")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("Done")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(MADTheme.Colors.redGradient))
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                        Spacer()
                        Text("\(text.count)/\(Self.maxLength)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 2)
                    .animation(.easeInOut(duration: 0.15), value: focused)

                    Spacer()
                }
                .padding(MADTheme.Spacing.md)
            }
            // Named for what it edits: on a card with four pictures on it,
            // "Edit caption" alone reads as the post's, which is the author's
            // and not this person's to change.
            .navigationTitle(subject == .post ? "Edit caption" : "Your caption")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.7))
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView().tint(MADTheme.Colors.madRed)
                        } else {
                            Text("Save").fontWeight(.bold)
                        }
                    }
                    .foregroundColor(MADTheme.Colors.madRed)
                    .disabled(isSaving)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                switch subject {
                case .post:
                    try await PostService.updateCaption(postId: post.post_id, caption: trimmed)
                case .myCollabSlide:
                    try await PostService.setCrewCaption(
                        postId: post.post_id,
                        caption: trimmed.isEmpty ? nil : trimmed
                    )
                }
                await MainActor.run {
                    onSaved(trimmed.isEmpty ? nil : trimmed)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Couldn't save — try again."
                }
            }
        }
    }
}
