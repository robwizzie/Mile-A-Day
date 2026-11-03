import SwiftUI

/// The top of the Feed: TODAY, one tile per friend, replacing the plain
/// stories rail. A story used to be the same photo as a post with a 24-hour
/// timer, so the rail answered nothing a post didn't. The board answers the
/// app's own question, "who has done their mile today?", and stories become
/// the live layer of that day.
///
/// Each tile is one of four states, in this order along the row:
/// - **Walking now**: live distance from `/live/friends-out` (which already
///   honours `share_live_presence`), said in words: a progress ring toward
///   their goal, the distance on top, "Walking"/"Running" along the bottom,
///   and a pulsing walk-blue edge. Tap → the Out now sheet (Hype / Join),
///   also reachable from the header's "N out now" pill. Polled every 20s
///   while anyone is out, 60s otherwise.
/// - **New / seen story**: the newest story photo as the tile (`preview_url`,
///   withheld server-side when the photo gate applies), the brand ring while
///   unseen. Locked behind the viewer's own mile like every story.
/// - **Done today**: a flame edge; tap → THEIR day (`FriendDaySheet`: Hype,
///   Ask for a photo, Profile), the way a walking tile opens the person.
/// - **Not yet**: tap once to nudge (a hand waves on the tile); once nudged,
///   tap → their day. "Nudged" reads `NudgeStatusStore`, the app-wide nudge
///   state, so it agrees with the Friends tab and their profile.
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
    /// Zoom source for the story viewer (iOS 18): a story opens out of its
    /// tile and shrinks back into it, Instagram-style.
    var storyZoom: Namespace.ID? = nil
    /// The author the open story viewer is on. Their tile is scrolled into
    /// view, so a swipe-down zooms back into the tile of the story you are
    /// LOOKING at (a lazy row doesn't mount offscreen tiles, and a zoom with
    /// no source on screen has nothing to land in).
    var focusedStoryId: String? = nil
    /// When `friendsToday` was fetched: a friend's "minutes left" ages from it.
    var friendsTodayFetchedAt: Date = Date()
    var isGroupViewable: (StoryGroup) -> Bool = { _ in true }
    var isGroupUnviewed: (StoryGroup) -> Bool = { $0.has_unviewed }
    let onTapAdd: () -> Void
    let onTapGroup: (StoryGroup) -> Void
    var onLockedStoryTap: () -> Void = {}
    let onNudge: (FriendActivityItem) -> Void
    /// A done-today friend with nothing to watch: their profile.
    let onTapFriend: (FriendActivityItem) -> Void
    /// Re-reads who's out; the board polls it while it is on screen.
    var refreshLive: () async -> Void = {}

    /// A friend's profile, opened from the live sheet (after it closes).
    var onOpenLiveProfile: (FriendOutNow) -> Void = { _ in }

    /// The live sheet: one person (a walking tile) or everyone (the header's
    /// pill). nil = closed.
    @State private var outNowRoute: OutNowRoute?
    /// A done (or already-nudged) friend's day, opened from their tile.
    @State private var dayFriend: FriendActivityItem?
    /// App-wide nudge state (see `NudgeStatusStore`).
    @ObservedObject private var nudgeStore = NudgeStatusStore.shared
    /// The tile whose hand is waving right now, and a counter that restarts
    /// the wave on each nudge.
    @State private var wavingId: String?
    @State private var waveCount = 0

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
        /// Within a rank, lower first (at-risk friends: the longest streak
        /// at stake leads). 0 keeps the server's order.
        var tiebreak: Int = 0
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
                                 imageURL: friend.profile_image_url, kind: .done(friend), rank: 4))
            } else {
                // A streak ending tonight comes before the done friends: that's
                // the nudge that matters most right now, longest streak first.
                let atRisk = friend.streakAtRisk(since: friendsTodayFetchedAt)
                out.append(Entry(id: friend.user_id, name: friend.displayName,
                                 imageURL: friend.profile_image_url,
                                 kind: .notYet(friend, nudged: nudgeStore.hasNudgedToday(friend.user_id)),
                                 rank: atRisk ? 3 : 5,
                                 tiebreak: atRisk ? -(friend.current_streak ?? 0) : 0))
            }
        }
        // Stable within a rank: the server's own order (rail recency, live
        // start time, the friends list) is already meaningful.
        return out.enumerated()
            .sorted {
                if $0.element.rank != $1.element.rank { return $0.element.rank < $1.element.rank }
                if $0.element.tiebreak != $1.element.tiebreak { return $0.element.tiebreak < $1.element.tiebreak }
                return $0.offset < $1.offset
            }
            .map(\.element)
    }

    private var doneCount: Int { friendsToday.filter(\.completed_today).count }

    /// Most of your friends are done and you aren't: your own tile says so
    /// ("12 of 15 done") instead of your distance, with a red edge.
    private var youreNext: Bool {
        !mileDone && friendsToday.count >= 3 && doneCount * 2 >= friendsToday.count
    }

    private var lockedStoryCount: Int {
        groups.filter { $0.user_id != currentUserId && !isGroupViewable($0) }.count
    }

    // MARK: - Body

    var body: some View {
        let rows = entries
        VStack(alignment: .leading, spacing: 8) {
            header
            riskBar
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: FeedLayout.storyGap) {
                        myTile
                            .id(myGroup?.user_id ?? "me")
                        ForEach(rows) { entry in
                            tile(for: entry)
                        }
                    }
                    .padding(.horizontal, FeedLayout.gutter)
                    // Room for the live tile's pulse, which scales 8% past the
                    // tile (~4pt each side); the scroll view clips at its bounds.
                    .padding(.vertical, 6)
                }
                .onChange(of: focusedStoryId) { _, id in
                    guard let id else { return }
                    // Behind the full-screen viewer, so no animation needed.
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            // Its own node: the board's root already presents the out-now
            // sheet, and two presentations on one node drop one.
            .sheet(item: $dayFriend) { friend in
                FriendDaySheet(
                    friend: friend,
                    onNudge: { nudge(friend) },
                    onOpenProfile: {
                        dayFriend = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onTapFriend(friend) }
                    }
                )
                // The sheet sizes itself to its content (see FriendDaySheet).
                .presentationDragIndicator(.visible)
            }
            if !mileDone, lockedStoryCount > 0 {
                unlockBar
                    .padding(.horizontal, FeedLayout.gutter)
            }
        }
        .task {
            // Who's out moves minute to minute; nothing else on the board does.
            // Faster while someone IS out, so their tile reads as live: a
            // walker's phone reports every ~45s, so 20s keeps us within one
            // beat of it. Idle, once a minute is enough to notice a new walker.
            await refreshLive()
            while !Task.isCancelled {
                let seconds: UInt64 = friendsOut.isEmpty ? 60 : 20
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                guard !Task.isCancelled else { break }
                await refreshLive()
            }
        }
        // Who's out, with Hype and Join: the existing live list (the same
        // one the Friends tab shows), one tap from any walking tile.
        .sheet(item: $outNowRoute) { route in
            OutNowContainer(
                initial: route,
                onJoined: {
                    outNowRoute = nil
                    // Hand the joined walk to the Dashboard after this sheet
                    // has gone (a presentation raised in a dismissal is dropped).
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        guard let sessionId = BuddySessionService.shared.session?.id else { return }
                        DeepLinkRouter.shared.requestOpenBuddySession(sessionId: sessionId)
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MAD_SwitchTab"), object: nil, userInfo: ["tab": 0]
                        )
                    }
                },
                onOpenProfile: { friend in
                    outNowRoute = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onOpenLiveProfile(friend) }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Today")
                .madFont(size: 15, weight: .bold, design: .rounded)
                .foregroundColor(.white.opacity(0.92))
            Spacer(minLength: 8)
            if !friendsToday.isEmpty {
                Text("\(doneCount) of \(friendsToday.count) done")
                    .madFont(size: 12, weight: .medium, design: .rounded, monospacedDigit: true)
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if !friendsOut.isEmpty {
                // "Out now" is a THING you can open, not a count in a caption:
                // a live dot, the words, and the sheet with Hype and Join.
                Button {
                    MADHaptics.tap()
                    outNowRoute = .everyone
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(MADTheme.Colors.walkBlue)
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                        Text("\(friendsOut.count) out now")
                            .madFont(size: 12, weight: .bold, design: .rounded, maxScale: 1.3, monospacedDigit: true)
                            .lineLimit(1)
                            .fixedSize()
                        Image(systemName: "chevron.right")
                            .madFont(size: 9, weight: .bold, maxScale: 1.3)
                            .opacity(0.6)
                            .accessibilityHidden(true)
                    }
                    .foregroundColor(MADTheme.Colors.walkBlue)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(MADTheme.Colors.walkBlue.opacity(0.14)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(friendsOut.count) friends out walking now. Opens hype and join.")
            }
        }
        .padding(.horizontal, FeedLayout.gutter)
    }

    // MARK: - Streaks ending tonight

    private func atRiskFriends(now: Date) -> [FriendActivityItem] {
        friendsToday
            .filter { $0.streakAtRisk(since: friendsTodayFetchedAt, now: now) }
            .sorted { ($0.current_streak ?? 0) > ($1.current_streak ?? 0) }
    }

    /// One row, only while a friend's streak ends tonight: how many and how
    /// soon (the soonest of them, ticking each minute). Information only:
    /// nudges go one person at a time, from each tile's own Nudge button
    /// (no "Nudge all"). The time used to sit on every red tile, the same
    /// "34m" four times over.
    @ViewBuilder
    private var riskBar: some View {
        // Gated OUTSIDE the timeline: an empty TimelineView would still take
        // a slot (and the spacing) in the board's VStack.
        if !atRiskFriends(now: Date()).isEmpty {
            riskTimeline
        }
    }

    private var riskTimeline: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let friends = atRiskFriends(now: now)
            if !friends.isEmpty {
                let soonest = friends.compactMap { $0.minutesLeft(since: friendsTodayFetchedAt, now: now) }.min() ?? 0
                HStack(spacing: 8) {
                    Image(systemName: "hourglass")
                        .madFont(size: 12, weight: .bold, maxScale: 1.2)
                        .foregroundColor(MADTheme.Colors.madRed)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(friends.count == 1 ? "1 streak ends tonight" : "\(friends.count) streaks end tonight")
                            .madFont(size: 13, weight: .heavy, design: .rounded, maxScale: 1.2)
                            .foregroundColor(.white)
                        Text("\(Self.shortTime(soonest)) left")
                            .madFont(size: 11, weight: .semibold, design: .rounded, maxScale: 1.2, monospacedDigit: true)
                            .foregroundColor(MADTheme.Colors.madRed)
                            .contentTransition(.numericText())
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MADTheme.Colors.madRed.opacity(0.12))
                )
                .padding(.horizontal, FeedLayout.gutter)
            }
        }
    }

    /// "17" — their streak at stake — plus their own time left only when
    /// their midnight is 30+ minutes off yours (the bar's time is yours).
    private func riskChipText(_ friend: FriendActivityItem, streak: Int) -> String {
        guard let left = friend.minutesLeft(since: friendsTodayFetchedAt) else { return "\(streak)" }
        let calendar = Calendar.current
        let now = Date()
        let midnight = calendar.startOfDay(for: now).addingTimeInterval(86_400)
        let mine = Int(midnight.timeIntervalSince(now) / 60)
        return abs(left - mine) >= 30 ? "\(streak) · \(Self.shortTime(left))" : "\(streak)"
    }

    // MARK: - Tiles

    private func tile(for entry: Entry) -> some View {
        Button {
            tap(entry)
        } label: {
            VStack(spacing: 6) {
                tileFace(entry)
                    .storyZoomSource(id: zoomSourceId(entry), in: storyZoom)
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

    /// Story tiles are zoom sources for the viewer (keyed by author id, the
    /// same id the viewer is presented with).
    private func zoomSourceId(_ entry: Entry) -> String? {
        if case .story(let group, _, let locked, _) = entry.kind, !locked { return group.user_id }
        return nil
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
                            // Opaque: a plain blur fades the photo's own edges
                            // to clear, which reads as a dark rim inside the tile.
                            .blur(radius: locked ? 8 : 0, opaque: true)
                            .saturation(locked ? 0.6 : 1)
                    } else {
                        TodayTileStyle.ground
                        // Centred like every other avatar tile, so a live chip
                        // on top never lands on the face.
                        AvatarView(name: entry.name, imageURL: entry.imageURL, size: 46)
                            .blur(radius: locked ? 4 : 0)
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
            // Lit from within, not shouted: a blue glow rising from the
            // bottom of the tile, a "Live" chip in the same quiet dark style
            // as Done (a solid blue pill on a solid blue edge was loud and
            // crowded the face), their progress as a ring around the face,
            // and the distance with a walk/run glyph along the bottom.
            TodayTile(edge: .live) {
                ZStack {
                    TodayTileStyle.liveGround
                    LiveProgressAvatar(name: entry.name, imageURL: entry.imageURL,
                                       progress: liveProgress(friend))
                        .frame(maxHeight: .infinity, alignment: .center)
                        .padding(.bottom, 6)
                }
                .overlay(alignment: .top) { LiveTileChip() }
                .overlay(alignment: .bottom) { liveLabel(friend) }
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
        case .notYet(let friend, let nudged):
            // The face in colour with a labelled "Nudge" button along the
            // bottom of the tile, so what a tap does is never a guess (a
            // wave badge alone wasn't clear). It turns into "✓ Nudged".
            //
            // A streak ending tonight gets a red edge and its streak on top
            // ("🔥 17"), the number that's actually at stake. The time left
            // is the SAME for everyone in your time zone, so it lives once,
            // in the row above the board (`riskBar`); a tile shows its own
            // time only when that friend's midnight is meaningfully
            // different from yours.
            let atRisk = friend.streakAtRisk(since: friendsTodayFetchedAt)
            TodayTile(edge: atRisk ? (nudged ? .riskQuiet : .risk) : .none) {
                ZStack {
                    TodayTileStyle.dimGround
                    // Smaller and lifted, so the streak chip on top and the
                    // Nudge button along the bottom both clear the face.
                    AvatarView(name: entry.name, imageURL: entry.imageURL, size: 40)
                        .opacity(nudged ? 0.75 : 0.9)
                        .padding(.bottom, 12)
                    if wavingId == friend.user_id {
                        NudgeWave(trigger: waveCount)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .overlay(alignment: .top) {
                    if atRisk, let streak = friend.current_streak {
                        TodayChip(text: riskChipText(friend, streak: streak), icon: "flame.fill",
                                  style: nudged ? .riskQuiet : .risk)
                    }
                }
                .overlay(alignment: .bottom) {
                    NudgeButtonLabel(nudged: nudged, urgent: atRisk)
                        .padding(.bottom, 7)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: nudged)
        }
    }

    /// "2h 10m" / "45m".
    static func shortTime(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func liveChip(_ friend: FriendOutNow) -> some View {
        TodayChip(text: friend.distanceMiles.map { $0.distanceFormatted } ?? "Out now",
                  icon: friend.isRunning ? "figure.run" : "figure.walk", style: .live)
            .animation(.easeOut(duration: 0.4), value: friend.distanceMiles)
    }

    /// "🚶 0.48 mi" (or "Walking" before the first distance report).
    private func liveLabel(_ friend: FriendOutNow) -> some View {
        HStack(spacing: 3) {
            Image(systemName: friend.isRunning ? "figure.run" : "figure.walk")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(MADTheme.Colors.walkBlue)
                .accessibilityHidden(true)
            Text(friend.distanceMiles.map { $0.distanceFormatted } ?? (friend.isRunning ? "Running" : "Walking"))
                .madFont(size: 11, weight: .heavy, design: .rounded, maxScale: 1.1, monospacedDigit: true)
                .foregroundColor(.white)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.4), value: friend.distanceMiles)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }

    private func liveProgress(_ friend: FriendOutNow) -> Double {
        guard let miles = friend.distanceMiles else { return 0 }
        return min(1, max(0, miles / friend.goal))
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
            // Tapping a person opens THAT person, not a list they're in.
            MADHaptics.tap()
            outNowRoute = .person(friend.userId)
        case .done(let friend):
            // Tapping a person opens THAT person's day, not their profile
            // (it's one tap further, in the sheet).
            MADHaptics.tap()
            dayFriend = friend
        case .notYet(let friend, let nudged):
            if nudged {
                MADHaptics.tap()
                dayFriend = friend
            } else {
                nudge(friend)
            }
        }
    }

    /// One tap: the hand waves on their tile, the chip flips to "Nudged"
    /// (the shared store marks it at once and rolls back on failure).
    private func nudge(_ friend: FriendActivityItem) {
        MADHaptics.success()
        waveCount += 1
        withAnimation(.easeOut(duration: 0.15)) { wavingId = friend.user_id }
        let count = waveCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            guard waveCount == count else { return }
            withAnimation(.easeIn(duration: 0.25)) { wavingId = nil }
        }
        onNudge(friend)
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
            return "\(entry.name), done today, double tap for their day"
        case .notYet(let friend, let nudged):
            var s = "\(entry.name), not done yet"
            if friend.streakAtRisk(since: friendsTodayFetchedAt),
               let left = friend.minutesLeft(since: friendsTodayFetchedAt) {
                s += ", streak ends in \(Self.shortTime(left))"
            }
            return s + (nudged ? ", nudged, double tap for their day" : ", double tap to nudge")
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
                TodayTile(edge: mileDone ? .done : (youreNext ? .risk : .quiet)) {
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
                        // Centred in the space above the distance label (which
                        // sits 7pt off the bottom), clear of the "+" badge.
                        .frame(maxHeight: .infinity, alignment: .center)
                        .padding(.bottom, 8)
                    }
                    .overlay(alignment: .bottom) {
                        Text(mileDone ? "Done" : (youreNext ? "\(doneCount) of \(friendsToday.count) done" : myMiles.distanceFormatted))
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
                .storyZoomSource(id: myGroup?.user_id, in: storyZoom)
                Text("You")
                    .madFont(size: 11, weight: .medium, design: .rounded, maxScale: 1.2)
                    .foregroundColor(.white.opacity(0.62))
                    .lineLimit(1)
            }
            .frame(width: TodayTileStyle.width)
        }
        .buttonStyle(TodayTileButtonStyle())
        .accessibilityLabel(mileDone ? "Your day, mile done"
                            : youreNext ? "Your day, \(myMiles.distanceFormatted) so far. \(doneCount) of \(friendsToday.count) friends are done, you're next"
                            : "Your day, \(myMiles.distanceFormatted) so far")
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

    /// A walking tile: the usual ground with a blue glow rising from the
    /// bottom, so "out now" reads from across the row without a loud fill.
    static var liveGround: some View {
        ZStack {
            Color(red: 0.07, green: 0.08, blue: 0.13)
            RadialGradient(colors: [MADTheme.Colors.walkBlue.opacity(0.45), .clear],
                           center: .bottom, startRadius: 2, endRadius: 90)
        }
    }

    static var bottomScrim: some View {
        LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
            .allowsHitTesting(false)
    }
}

/// The board's tile: a tall rounded card with a 2.5pt edge whose colour IS
/// the state, the way the ring was on the old circles.
private struct TodayTile<Content: View>: View {
    enum Edge { case story, live, done, quiet, none, risk, riskQuiet }

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
        case .live: return AnyShapeStyle(MADTheme.Colors.walkBlue.opacity(0.75))
        case .done: return AnyShapeStyle(Color.orange.opacity(0.55))
        case .risk: return AnyShapeStyle(MADTheme.Colors.madRed.opacity(0.85))
        case .riskQuiet: return AnyShapeStyle(MADTheme.Colors.madRed.opacity(0.35))
        case .quiet: return AnyShapeStyle(Color.white.opacity(0.12))
        case .none: return AnyShapeStyle(Color.white.opacity(0.06))
        }
    }
}

/// The small label riding a tile's top edge: live distance, Done, Nudge.
private struct TodayChip: View {
    enum Style { case live, done, quiet, nudged, risk, riskQuiet }
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
                .contentTransition(.numericText())
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
        case .risk: return .white
        case .riskQuiet: return MADTheme.Colors.madRed
        }
    }

    private var background: Color {
        switch style {
        case .live: return MADTheme.Colors.walkBlue
        case .done: return .black.opacity(0.55)
        case .quiet: return .white.opacity(0.12)
        case .nudged: return .white.opacity(0.9)
        case .risk: return MADTheme.Colors.madRed
        case .riskQuiet: return .black.opacity(0.55)
        }
    }
}

/// A story preview filling its tile, through the feed's image cache.
///
/// The photo rides an overlay on `Color.clear` so it can NEVER size the
/// tile: a fill-scaled image reports its full scaled size, and laid out
/// directly it grew the tile's ZStack past the tile (a 9:16 photo by ~30pt),
/// pushing the bottom-pinned avatar and top-pinned chip out of view under the
/// clip. `Color.clear` takes exactly the space offered; the photo fills it
/// centred and is cropped to it.
private struct TodayPreviewImage: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                FeedImageView(url: url, loadedImage: $image)
            }
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


/// The walking tile's top chip: a breathing blue dot and "Live", dark like
/// the Done chip.
private struct LiveTileChip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(MADTheme.Colors.walkBlue)
                .frame(width: 6, height: 6)
                .opacity(on ? 0.3 : 1)
            Text("Live")
                .madFont(size: 10, weight: .heavy, design: .rounded, maxScale: 1.1)
                .foregroundColor(MADTheme.Colors.walkBlue)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .padding(.top, 6)
        .onAppear {
            guard !reduceMotion else { return }
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A face with a progress ring around it, for a friend mid-walk: the ring
/// fills toward their own goal as their phone reports in.
private struct LiveProgressAvatar: View {
    let name: String
    let imageURL: String?
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(MADTheme.Colors.walkBlue, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: MADTheme.Colors.walkBlue.opacity(0.6), radius: 4)
                .animation(.easeOut(duration: 0.6), value: progress)
            AvatarView(name: name, imageURL: imageURL, size: 44)
        }
        .frame(width: 56, height: 56)
    }
}

/// Which live sheet: one friend, or everyone out.
enum OutNowRoute: Identifiable, Equatable {
    case person(String)
    case everyone

    var id: String {
        switch self {
        case .person(let id): return "person-\(id)"
        case .everyone: return "everyone"
        }
    }
}

/// The live sheet's content. Switching from one person to everyone happens
/// INSIDE the sheet, so "See everyone out" never dismisses and re-presents.
struct OutNowContainer: View {
    let initial: OutNowRoute
    let onJoined: () -> Void
    let onOpenProfile: (FriendOutNow) -> Void

    @State private var route: OutNowRoute?

    var body: some View {
        switch route ?? initial {
        case .person(let id):
            LiveFriendSheet(
                friendId: id,
                onJoined: onJoined,
                onOpenProfile: onOpenProfile,
                onSeeEveryone: { withAnimation(.easeInOut(duration: 0.2)) { route = .everyone } }
            )
        case .everyone:
            OutNowSheet(onJoined: onJoined)
        }
    }
}

/// Everyone out right now, with Hype and Join, opened from the Today board.
///
/// The list itself is `BuddyJoinFriendCard`, reused verbatim (the Friends
/// tab's "Out right now"): closest-to-finishing first, a live ring per
/// person, Hype that lands on their tracker mid-walk, and Join / Ask to walk.
struct OutNowSheet: View {
    let onJoined: () -> Void
    @ObservedObject private var buddy = BuddySessionService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Out right now")
                    .madFont(size: 22, weight: .heavy, design: .rounded)
                    .foregroundColor(.white)
                Text("Hype them mid-walk and it shows up on their screen. Or go with them.")
                    .madFont(size: 14, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)

            ScrollView {
                if buddy.friendsOutNow.isEmpty {
                    Text("Nobody is out right now.")
                        .madFont(size: 15, weight: .semibold, design: .rounded)
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    BuddyJoinFriendCard(
                        // You can't join a walk mid-walk; hyping still works.
                        hasActiveWorkout: InProgressWorkoutStore.load()?.isActive == true,
                        onJoined: onJoined
                    )
                    .padding(.horizontal, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.09, green: 0.05, blue: 0.07).ignoresSafeArea())
        // A list: medium to start, pull up for more. (The one-person sheet
        // sizes itself to its content.)
        .presentationDetents([.medium, .large])
        .madTypeCap(.madCardCap)
        .task {
            // Fresh numbers the moment it opens, then every 20s while open.
            while !Task.isCancelled {
                await buddy.refreshFriendsOutNow()
                try? await Task.sleep(nanoseconds: 20 * 1_000_000_000)
            }
        }
    }
}

/// The hand that waves on a tile when you nudge: a big 👋 swinging from the
/// wrist, restarted by `trigger`.
private struct NudgeWave: View {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("👋")
            .font(.system(size: 34))
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            .phaseAnimator(reduceMotion ? [0.0] : [0.0, -22, 18, -22, 18, 0], trigger: trigger) { content, angle in
                content.rotationEffect(.degrees(angle), anchor: .bottomTrailing)
            } animation: { _ in .easeInOut(duration: 0.16) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.25))
    }
}

/// Whether stories zoom out of their tiles (the iOS 18 zoom transition).
enum StoryZoom {
    static var isAvailable: Bool {
        if #available(iOS 18.0, *) { return true }
        return false
    }
}

extension View {
    /// The tile a story zooms out of and back into (iOS 18 zoom transition).
    /// No-op before iOS 18 or without a namespace.
    @ViewBuilder
    func storyZoomSource(id: String?, in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), let id, let namespace {
            self.matchedTransitionSource(id: id, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        } else {
            self
        }
    }

    /// The presented story viewer's side of that zoom.
    @ViewBuilder
    func storyZoomTransition(id: String, in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), let namespace {
            self.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

/// The bottom of a not-yet tile: a labelled "Nudge" button (red when their
/// streak ends tonight), "✓ Nudged" once sent. The whole tile is the tap
/// target; this says what the tap does.
private struct NudgeButtonLabel: View {
    let nudged: Bool
    let urgent: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: nudged ? "checkmark" : "hand.wave.fill")
                .font(.system(size: 9, weight: .bold))
                .accessibilityHidden(true)
            Text(nudged ? "Nudged" : "Nudge")
                .madFont(size: 11, weight: .heavy, design: .rounded, maxScale: 1.1)
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundColor(nudged ? .white.opacity(0.6) : .white)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(nudged ? Color.white.opacity(0.08)
                                  : (urgent ? MADTheme.Colors.madRed : Color.white.opacity(0.18)))
        )
        .contentTransition(.interpolate)
    }
}
