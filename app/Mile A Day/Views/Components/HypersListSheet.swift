import SwiftUI

/// Identifies one hypeable piece of content (a post or a daily mile) so the
/// feed can open the "who hyped this" list for it.
struct HypersListContext: Identifiable {
    /// "post" | "mile"
    let contextType: String
    /// Post id, or the mile's workout id (backend canonicalizes).
    let contextId: String
    /// The content author's user id.
    let targetUserId: String

    var id: String { "\(contextType)-\(contextId)" }
}

/// Instagram's "Likes" sheet, in Mile A Day's language: tap a card's hype
/// tally to see everyone who hyped it, newest first.
struct HypersListSheet: View {
    let context: HypersListContext
    /// Tap a row to open that person's profile (dismisses this sheet first).
    var onSelectUser: ((Hyper) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var hypers: [Hyper] = []
    @State private var isLoading = true
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: MADTheme.Colors.madRed))
                } else if failed {
                    stateMessage(icon: "wifi.slash", text: "Couldn't load hypes")
                } else if hypers.isEmpty {
                    stateMessage(icon: "hands.clap", text: "No hypes yet")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(hypers) { hyper in
                                row(hyper)
                                if hyper.id != hypers.last?.id {
                                    Divider().overlay(Color.white.opacity(0.06))
                                        .padding(.leading, 62)
                                }
                            }
                        }
                        .padding(.vertical, MADTheme.Spacing.sm)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("Hypes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(MADTheme.Colors.madRed)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await load() }
    }

    private func row(_ hyper: Hyper) -> some View {
        Button {
            if let onSelectUser {
                dismiss()
                onSelectUser(hyper)
            }
        } label: {
            HStack(spacing: 12) {
                AvatarView(name: hyper.displayName, imageURL: hyper.profile_image_url, size: 42)
                VStack(alignment: .leading, spacing: 1) {
                    Text(hyper.displayName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(hyper.relativeTime)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                Image(systemName: "hands.clap.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onSelectUser == nil)
    }

    private func stateMessage(icon: String, text: String) -> some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.3))
            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private func load() async {
        do {
            let result = try await HypeService.hypers(
                contextType: context.contextType,
                contextId: context.contextId,
                targetUserId: context.targetUserId
            )
            await MainActor.run {
                hypers = result
                isLoading = false
            }
        } catch {
            await MainActor.run {
                failed = true
                isLoading = false
            }
        }
    }
}
