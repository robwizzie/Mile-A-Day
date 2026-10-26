import SwiftUI

/// Posts kept on the phone because there was no signal (`PostDraftStore`),
/// at the top of the feed until they go out. Renders nothing when there are
/// none.
///
/// They send themselves — on reconnect, on foreground, and on a backoff while
/// waiting — so the only things offered here are "try now" and delete.
struct PostDraftsCard: View {
    @ObservedObject private var store = PostDraftStore.shared

    var body: some View {
        if !store.drafts.isEmpty {
            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(store.drafts) { draft in
                    PostDraftRow(draft: draft, isSending: store.sending.contains(draft.id))
                }
            }
            // Padded INSIDE the condition, so no drafts leaves nothing — not
            // even a gutter — in the feed's stack.
            .padding(.horizontal, MADTheme.Spacing.md)
        }
    }
}

private struct PostDraftRow: View {
    let draft: PostDraft
    let isSending: Bool

    @State private var thumbnail: UIImage?
    @State private var confirmDelete = false

    private var status: String {
        if isSending { return "Posting…" }
        if let stuck = draft.stuckMessage { return stuck }
        if draft.isExpired {
            return "This walk's day is over, so it can't be posted any more."
        }
        return "Waiting for a connection — it'll post on its own."
    }

    private var isBlocked: Bool { draft.stuckMessage != nil || draft.isExpired }

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white.opacity(0.08)
                }
            }
            .frame(width: 48, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(draft.crewPhotoPostId != nil ? "Your photo · draft" : "Post · draft")
                    .madFont(size: 15, weight: .bold, design: .rounded)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(status)
                    .madFont(size: 13, design: .rounded)
                    .foregroundColor(isBlocked ? MADTheme.Colors.error : .white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                if !isBlocked && !isSending {
                    Button {
                        MADHaptics.tap()
                        Task { await PostDraftStore.shared.send(draft) }
                    } label: {
                        Text("Post now")
                            .madFont(size: 13, weight: .bold, design: .rounded)
                            .foregroundColor(MADTheme.Colors.madRed)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            if isSending {
                ProgressView().tint(.white)
            } else {
                Button {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Delete draft"))
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                        .strokeBorder(MADTheme.Colors.madRed.opacity(0.35), lineWidth: 1)
                )
        )
        .confirmationDialog("Delete this draft?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete draft", role: .destructive) {
                PostDraftStore.shared.delete(draft)
            }
        } message: {
            Text("It won't be posted.")
        }
        .task(id: draft.id) {
            // The downscale runs off the main thread — a full-size decode
            // per row would hitch the feed.
            let full = PostDraftStore.shared.primaryImage(for: draft)
            thumbnail = await full?.byPreparingThumbnail(ofSize: CGSize(width: 144, height: 180))
        }
    }
}
