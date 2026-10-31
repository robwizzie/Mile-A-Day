import SwiftUI

/// The top of the Feed: TODAY, one tile per friend, replacing the plain
/// stories rail. A story used to be the same photo as a post with a 24-hour
/// timer, so the rail answered nothing a post didn't. The board answers the
/// app's own question, "who has done their mile today?", and stories become
/// the live layer of that day.
///
/// Each tile is one of four states, in this order along the row:
/// - **Walking now**: live distance from `/live/friends-out` (which already
///   honours `share_live_presence`), a pulsing walk-blue edge. Tap → them.
/// - **New / seen story**: the newest story photo as the tile (`preview_url`,
///   withheld server-side when the photo gate applies), the brand ring while
///   unseen. Locked behind the viewer's own mile like every story.
/// - **Done today**: a flame edge; nothing new to watch.
/// - **Not yet**: dimmed; tap once to nudge (the existing friend nudge).
///
/// The viewer's own tile leads, with a progress ring of their mile.
struct TodayBoardView: View {
    let groups: [StoryGroup]
    /// `/friends/activity/today`: every friend's miles + done flag.
    let friendsToday: [FriendActivityItem]
    /// `/live/friends-out`: friends mid-walk who share presence.
    let friendsOut: [FriendOutNow]
    let currentUserId: String?
    let myName: String
    let myImageURL: String?
    let myMiles: Double
    let myGoal: Double
    let mileDone: Bool
    /// Mile done AND a qualifying walk/run today: the "+" badge.
    let canPost: Bool
    var hasSharedWorkout: Bool = false
    /// The CAMERA window's countdown ring on the viewer's own tile.
    var windowOpen: Bool = false
    var windowOpenedAt: Date? = nil
    /// Friends nudged from this board this session, so the tile flips at once.
    var nudgedIds: Set<String> = []
    var isGroupViewable: (StoryGroup) -> Bool = { _ in true }
    var isGroupUnviewed: (StoryGroup) -> Bool = { $0.has_unviewed }
    let onTapAdd: () -> Void
    let onTapGroup: (StoryGroup) -> Void
    var onLockedStoryTap: () -> Void = {}
    let onTapLive: (FriendOutNow) -> Void
    let onNudge: (FriendActivityItem) -> Void
    /// A done-today friend with nothing to watch: their profile.
    let onTapFriend: (FriendActivityItem) -> Void
    /// Re-reads who's out; the board polls it while it is on screen.
    var refreshLive: () async -> Void = {}

    // MARK: - Entries

    private struct Entry: Identifiable {
        enum Kind {
            case story(StoryGroup, unviewed: Bool, locked: Bool, live: FriendOutNow?)
            case walking(FriendOutNow)
            case done(FriendActivityItem)
            case notYet(FriendActivityItem, nudged: Bool)
        }
        let id: String
        let name: String
        let imageURL: String?
        let kind: Kind
        let rank: Int
    }

    private var myGroup: StoryGroup? {
        groups.first { $0.user_id == currentUserId }
    }

    /// One tile per friend, ranked: out now → new story → seen story → done
    /// → not yet. A friend with a story keeps their story tile (with the live
    /// chip if they're also out) so the preview is never hidden by presence.
    private var entries: [Entry] {
        var seen = Set<String>()
        if let currentUserId { seen.insert(currentUserId) }
        var out: [Entry] = []
        let liveById = Dictionary(friendsOut.map { ($0.userId, $0) }, uniquingKeysWith: { a, _ in a })

        for group in groups where !seen.contains(group.user_id) {
            seen.insert(group.user_id)
            let viewable = isGroupViewable(group)
            let unviewed = isGroupUnviewed(group)
            let live = liveById[group.user_id]
            out.append(Entry(
                id: group.user_id, name: group.displayName, imageURL: group.profile_image_url,
                kind: .story(group, unviewed: unviewed, locked: !viewable, live: live),
                rank: live != nil ? 0 : (unviewed ? 1 : 2)
            ))
        }
        for friend in friendsOut where !seen.contains(friend.userId) {
            seen.insert(friend.userId)
            out.append(Entry(id: friend.userId, name: friend.displayName,
                             imageURL: friend.profileImageUrl, kind: .walking(friend), rank: 0))
        }
        for friend in friendsToday where !seen.contains(friend.user_id) {
            seen.insert(friend.user_id)
            if friend.completed_today {
                out.append(Entry(id: friend.user_id, name: friend.displayName,
                                 imageURL: friend.profile_image_url, kind: .done(friend), rank: 3))
            } else {
                out.append(Entry(id: friend.user_id, name: friend.displayName,
                                 imageURL: friend.profile_image_url,
                                 kind: .notYet(friend, nudged: nudgedIds.contains(friend.user_id)), rank: 4))
            }
        }
        // Stable within a rank: the server's own order (rail recency, live
        // start time, the friends list) is already meaningful.
        return out.enumerated()
            .sorted { $0.element.rank != $1.element.rank ? $0.element.rank < $1.element.rank : $0.offset < $1.offset }
            .map(\.element)
    }

    private var doneCount: Int { friendsToday.filter(\.completed_today).count }

    private var lockedStoryCount: Int {
        groups.filter { $0.user_id != currentUserId && !isGroupViewable($0) }.count
    }

    // MARK: - Body

    var body: some View {
        let rows = entries
        VStack(alignment: .leading, spacing: 8) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: FeedLayout.storyGap) {
                    myTile
                    ForEach(rows) { entry in
                        tile(for: entry)
                    }
                }
                .padding(.horizontal, FeedLayout.gutter)
                .padding(.vertical, 2)
            }
            if !mileDone, lockedStoryCount > 0 {
                unlockBar
                    .padding(.horizontal, FeedLayout.gutter)
            }
        }
        .task {
            // Who's out moves minute to minute; nothing else on the board does.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                guard !Task.isCancelled else { break }
                await refreshLive()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Today")
                .madFont(size: 15, weight: .bold, design: .rounded)
                .foregroundColor(.white.opacity(0.92))
            Spacer(minLength: 8)
            Text(summary)
                .madFont(size: 12, weight: .medium, design: .rounded)
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, FeedLayout.gutter)
    }

    private var summary: String {
        var parts: [String] = []
        if !friendsToday.isEmpty {
            parts.append("\(doneCount) of \(friendsToday.count) done")
        }
        if !friendsOut.isEmpty {
            parts.append("\(friendsOut.count) out now")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Tiles

    private func tile(for entry: Entry) -> some View {
        Button {
            tap(entry)
        } label: {
            VStack(spacing: 6) {
                tileFace(entry)
                Text(entry.name)
                    .madFont(size: 11, weight: .medium, design: .rounded, maxScale: 1.2)
                    .foregroundColor(.white.opacity(isDim(entry) ? 0.4 : 0.62))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: TodayTileStyle.width)
        }
        .buttonStyle(TodayTileButtonStyle())
        .accessibilityLabel(accessibilityText(entry))
    }

    private func isDim(_ entry: Entry) -> Bool {
        if case .notYet = entry.kind { return true }
        return false
    }

    @ViewBuilder
    private func tileFace(_ entry: Entry) -> some View {
        switch entry.kind {
        case .story(let group, let unviewed, let locked, let live):
            TodayTile(edge: unviewed && !locked ? .story : .quiet) {
                ZStack {
                    if let url = group.previewURL {
                        TodayPreviewImage(url: url)
                            .blur(radius: locked ? 8 : 0)
                            .saturation(locked ? 0.6 : 1)
                    } else {
                        TodayTileStyle.ground
                        AvatarView(name: entry.name, imageURL: entry.imageURL, size: 46)
                            .blur(radius: locked ? 4 : 0)
                            .frame(maxHeight: .infinity, alignment: .center)
                            .padding(.bottom, 16)
                    }
                    TodayTileStyle.bottomScrim
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 3)
                            .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .bottom) {
                    if group.previewURL != nil {
                        AvatarView(name: entry.name, imageURL: entry.imageURL, size: 28)
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 2))
                            .padding(.bottom, 7)
                    }
                }
                .overlay(alignment: .top) {
                    if let live { liveChip(live) }
                }
            }
        case .walking(let friend):
            TodayTile(edge: .live) {
                ZStack {
                    TodayTileStyle.ground
                    AvatarView(name: entry.name, imageURL: entry.imageURL, size: 46)
                }
                .overlay(alignment: .top) { liveChip(friend) }
            }
        case .done:
            TodayTile(edge: .done) {
                ZStack {
                    TodayTileStyle.ground
                    AvatarView(name: entry.name, imageURL: entry.imageURL, size: 46)
                }
                .overlay(alignment: .top) {
                    TodayChip(text: "Done", icon: "flame.fill", style: .done)
                }
            }
        case .notYet(_, let nudged):
            TodayTile(edge: .none) {
                ZStack {
                    TodayTileStyle.dimGround
                    AvatarView(name: entry.name, imageURL: entry.imageURL, size: 46)
                        .saturation(0)
                        .opacity(0.45)
                }
                .overlay(alignment: .top) {
                    TodayChip(text: nudged ? "Nudged" : "Nudge",
                              icon: nudged ? "checkmark" : "hand.wave.fill",
                              style: nudged ? .nudged : .quiet)
                }
            }
        }
    }

    private func liveChip(_ friend: FriendOutNow) -> some View {
        TodayChip(text: friend.distanceMiles.map { $0.distanceFormatted } ?? "Out now",
                  icon: nil, style: .live)
    }

    private func tap(_ entry: Entry) {
        switch entry.kind {
        case .story(let group, _, let locked, _):
            if locked {
                MADHaptics.warning()
                onLockedStoryTap()
            } else {
                MADHaptics.tap()
                onTapGroup(group)
            }
        case .walking(let friend):
            MADHaptics.tap()
            onTapLive(friend)
        case .done(let friend):
            MADHaptics.tap()
            onTapFriend(friend)
        case .notYet(let friend, let nudged):
            if nudged {
                MADHaptics.tap()
                onTapFriend(friend)
            } else {
                MADHaptics.action()
                onNudge(friend)
            }
        }
    }

    private func accessibilityText(_ entry: Entry) -> String {
        switch entry.kind {
        case .story(_, let unviewed, let locked, let live):
            var s = "\(entry.name), \(unviewed ? "new story" : "story")"
            if locked { s += ", locked until you finish your mile" }
            if live != nil { s += ", walking now" }
            return s
        case .walking(let f):
            return "\(entry.name), walking now" + (f.distanceMiles.map { ", \($0.distanceFormatted)" } ?? "")
        case .done:
            return "\(entry.name), done today"
        case .notYet(_, let nudged):
            return "\(entry.name), not done yet, " + (nudged ? "nudged" : "double tap to nudge")
        }
    }

    // MARK: - Your tile

    private var myProgress: Double {
        guard myGoal > 0 else { return mileDone ? 1 : 0 }
        return mileDone ? 1 : min(1, max(0, myMiles / myGoal))
    }

    private var myTile: some View {
        Button {
            if myGroup == nil && !canPost {
                MADHaptics.warning()
            } else {
                MADHaptics.tap()
            }
            // Your own story opens if you have one; otherwise the composer
            // (the FAB below also reaches it, so adding more is never lost).
            if let myGroup { onTapGroup(myGroup) } else { onTapAdd() }
        } label: {
            VStack(spacing: 6) {
                TodayTile(edge: mileDone ? .done : .quiet) {
                    ZStack {
                        if let url = myGroup?.previewURL {
                            TodayPreviewImage(url: url)
                            TodayTileStyle.bottomScrim
                        } else {
                            TodayTileStyle.ground
                        }
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.14), lineWidth: 3.5)
                            Circle()
                                .trim(from: 0, to: myProgress)
                                .stroke(mileDone ? Color.orange : MADTheme.Colors.madRed,
                                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            AvatarView(name: myName, imageURL: myImageURL, size: 42)
                        }
                        .frame(width: 52, height: 52)
                        .overlay {
                            if windowOpen && canPost && !hasSharedWorkout, let openedAt = windowOpenedAt {
                                FreshWindowRing(openedAt: openedAt, color: MADTheme.Colors.madRed, lineWidth: 2.5)
                                    .padding(-4)
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                        .padding(.bottom, 14)
                    }
                    .overlay(alignment: .bottom) {
                        Text(mileDone ? "Done" : myMiles.distanceFormatted)
                            .madFont(size: 10, weight: .heavy, design: .rounded, maxScale: 1.1, monospacedDigit: true)
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 7)
                    }
                    .overlay(alignment: .topTrailing) {
                        if !hasSharedWorkout {
                            Image(systemName: canPost ? "plus.circle.fill" : "lock.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white, canPost ? MADTheme.Colors.madRed : Color.gray)
                                .padding(5)
                                .accessibilityHidden(true)
                        }
                    }
                }
                Text("You")
                    .madFont(size: 11, weight: .medium, design: .rounded, maxScale: 1.2)
                    .foregroundColor(.white.opacity(0.62))
                    .lineLimit(1)
            }
            .frame(width: TodayTileStyle.width)
        }
        .buttonStyle(TodayTileButtonStyle())
        .accessibilityLabel(mileDone ? "Your day, mile done" : "Your day, \(myMiles.distanceFormatted) so far")
    }

    // MARK: - Unlock

    /// Under the row while friends' stories are locked: how close YOU are to
    /// seeing them. The lock was a wall; this makes it the reason to go.
    private var unlockBar: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.14), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: myProgress)
                    .stroke(MADTheme.Colors.madRed, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(lockedStoryCount == 1
                     ? "Finish your mile to unlock 1 story"
                     : "Finish your mile to unlock \(lockedStoryCount) stories")
                    .madFont(size: 13, weight: .bold, design: .rounded)
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(2)
                Text("\(max(0, myGoal - myMiles).distanceToGoText) \(DistanceUnits.current.abbreviation) to go")
                    .madFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Tile chrome

/// Sizes and grounds shared by every tile (non-generic, so call sites don't
/// have to name `TodayTile`'s content type).
private enum TodayTileStyle {
    static var width: CGFloat { FeedLayout.storyCell + 2 }
    static var height: CGFloat { 104 }

    static var ground: LinearGradient {
        LinearGradient(colors: [Color(red: 0.17, green: 0.11, blue: 0.13),
                                Color(red: 0.11, green: 0.07, blue: 0.09)],
                       startPoint: .top, endPoint: .bottom)
    }

    static var dimGround: Color { Color(red: 0.10, green: 0.07, blue: 0.08) }

    static var bottomScrim: some View {
        LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
            .allowsHitTesting(false)
    }
}

/// The board's tile: a tall rounded card with a 2.5pt edge whose colour IS
/// the state, the way the ring was on the old circles.
private struct TodayTile<Content: View>: View {
    enum Edge { case story, live, done, quiet, none }

    let edge: Edge
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        content()
            .frame(width: TodayTileStyle.width - 5, height: TodayTileStyle.height - 5)
            .clipShape(RoundedRectangle(cornerRadius: 19.5, style: .continuous))
            .padding(2.5)
            .background(shape.fill(edgeStyle))
            .overlay {
                if edge == .live {
                    shape
                        .stroke(MADTheme.Colors.walkBlue, lineWidth: 2)
                        .scaleEffect(pulsing ? 1.08 : 1)
                        .opacity(pulsing ? 0 : 0.8)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: TodayTileStyle.width, height: TodayTileStyle.height)
            .onAppear {
                guard edge == .live, !reduceMotion else { return }
                // Next turn, not inside the appear commit, so the loop doesn't
                // attach to unrelated layout changes (the repeatForever rule).
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                        pulsing = true
                    }
                }
            }
    }

    private var edgeStyle: AnyShapeStyle {
        switch edge {
        case .story:
            return AnyShapeStyle(AngularGradient(
                colors: [MADTheme.Colors.madRed, .orange, MADTheme.Colors.madRed],
                center: .center))
        case .live: return AnyShapeStyle(MADTheme.Colors.walkBlue)
        case .done: return AnyShapeStyle(Color.orange.opacity(0.55))
        case .quiet: return AnyShapeStyle(Color.white.opacity(0.12))
        case .none: return AnyShapeStyle(Color.white.opacity(0.06))
        }
    }
}

/// The small label riding a tile's top edge: live distance, Done, Nudge.
private struct TodayChip: View {
    enum Style { case live, done, quiet, nudged }
    let text: String
    let icon: String?
    let style: Style

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                    .accessibilityHidden(true)
            }
            Text(text)
                .madFont(size: 10, weight: .heavy, design: .rounded, maxScale: 1.1, monospacedDigit: true)
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundColor(foreground)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(background))
        .padding(.top, 6)
    }

    private var foreground: Color {
        switch style {
        case .live: return .white
        case .done: return .orange
        case .quiet: return .white.opacity(0.75)
        case .nudged: return Color(red: 0.10, green: 0.05, blue: 0.07)
        }
    }

    private var background: Color {
        switch style {
        case .live: return MADTheme.Colors.walkBlue
        case .done: return .black.opacity(0.55)
        case .quiet: return .white.opacity(0.12)
        case .nudged: return .white.opacity(0.9)
        }
    }
}

/// A story preview filling its tile, through the feed's image cache.
private struct TodayPreviewImage: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        FeedImageView(url: url, loadedImage: $image)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}

private struct TodayTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
