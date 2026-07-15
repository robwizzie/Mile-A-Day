import SwiftUI

/// Horizontal rail of story rings at the top of the feed. The first cell is the
/// viewer's "Your story" / add button (gated on completing the mile); the rest
/// are friends with active stories, unviewed rings highlighted.
struct StoriesRailView: View {
    let groups: [StoryGroup]
    let currentUserId: String?
    let myName: String
    let myImageURL: String?
    let canPost: Bool
    /// The viewer has already shared this workout — the "+" add badge hides
    /// (one post per walk/run); the ring still opens their own story.
    var hasSharedWorkout: Bool = false
    /// Per-group viewing gate: viewing is earned per story DAY (yesterday's
    /// stories stay open for a viewer who completed yesterday; a new today
    /// story locks until today's mile is done). The feed owns the rule.
    var isGroupViewable: (StoryGroup) -> Bool = { _ in true }
    let onTapAdd: () -> Void
    let onTapGroup: (StoryGroup) -> Void
    var onLockedStoryTap: () -> Void = {}

    private var friendGroups: [StoryGroup] {
        groups.filter { $0.user_id != currentUserId }
    }
    private var myGroup: StoryGroup? {
        groups.first { $0.user_id == currentUserId }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: MADTheme.Spacing.md) {
                addCell
                ForEach(friendGroups) { group in
                    let viewable = isGroupViewable(group)
                    Button {
                        if viewable { onTapGroup(group) } else { onLockedStoryTap() }
                    } label: {
                        cell(
                            name: group.displayName,
                            imageURL: group.profile_image_url,
                            unviewed: group.has_unviewed,
                            locked: !viewable
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, MADTheme.Spacing.sm)
        }
    }

    // The viewer's own cell: tapping the ring opens their story if they have one;
    // the small "+" always opens the composer (when allowed).
    private var addCell: some View {
        Button {
            // If the viewer already has an active story, open it; otherwise
            // (or when they can post) open the composer. The compose FAB in the
            // feed also reaches the composer, so adding-more is always available.
            if let myGroup {
                onTapGroup(myGroup)
            } else {
                onTapAdd()
            }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    ring(unviewed: myGroup?.has_unviewed ?? false, dashed: myGroup == nil) {
                        AvatarView(name: myName, imageURL: myImageURL, size: 64)
                    }
                    // No add/lock badge once they've shared this workout — the
                    // ring still opens their own story, there's just nothing new
                    // to post. Lock shows only before the mile is done.
                    if !hasSharedWorkout {
                        Image(systemName: canPost ? "plus.circle.fill" : "lock.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white, canPost ? MADTheme.Colors.madRed : Color.gray)
                            .background(Circle().fill(.black))
                            .offset(x: 2, y: 2)
                    }
                }
                Text("Your story")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(width: 76)
        }
        .buttonStyle(.plain)
    }

    private func cell(name: String, imageURL: String?, unviewed: Bool, locked: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                ring(unviewed: unviewed && !locked, dashed: false) {
                    AvatarView(name: name, imageURL: imageURL, size: 64)
                        .saturation(locked ? 0 : 1)
                        .opacity(locked ? 0.55 : 1)
                }
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                }
            }
            Text(name)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: 76)
    }

    @ViewBuilder
    private func ring<Content: View>(unviewed: Bool, dashed: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(3)
            .background(
                Circle().fill(MADTheme.Colors.madBlack)
            )
            .overlay(
                Circle()
                    .strokeBorder(
                        unviewed
                            ? AnyShapeStyle(LinearGradient(
                                colors: [MADTheme.Colors.madRed, .orange],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color.white.opacity(0.25)),
                        style: StrokeStyle(lineWidth: 2.5, dash: dashed ? [4] : [])
                    )
            )
    }
}
