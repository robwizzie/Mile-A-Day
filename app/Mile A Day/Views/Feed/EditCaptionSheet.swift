import SwiftUI

/// Edit the caption of one of the user's own posts — reachable from the feed
/// card menu, the profile posts sheet, and the workout detail's linked post.
/// Saves through PATCH /posts/:postId and hands the trimmed caption back so
/// the presenting view can update in place without a refetch.
struct EditCaptionSheet: View {
    let post: PostItem
    /// Called after a successful save with the new caption (nil when cleared).
    let onSaved: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private static let maxLength = 280

    init(post: PostItem, onSaved: @escaping (String?) -> Void) {
        self.post = post
        self.onSaved = onSaved
        _text = State(initialValue: post.caption ?? "")
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
                        Spacer()
                        Text("\(text.count)/\(Self.maxLength)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 2)

                    Spacer()
                }
                .padding(MADTheme.Spacing.md)
            }
            .navigationTitle("Edit caption")
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
                try await PostService.updateCaption(postId: post.post_id, caption: trimmed)
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
