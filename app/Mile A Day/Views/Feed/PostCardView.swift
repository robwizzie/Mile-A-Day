import SwiftUI
import CoreLocation

/// A single post in the social feed: author header, media, caption, the
/// hype/comment/share row with the streak chip, and a report/block/delete
/// menu. The media has two FACES behind a PHOTO | MAP toggle in its corner:
/// the photo (a swipeable carousel when the run has more than one — the
/// author's, the crew's) leads, and the map (the route with its stats band,
/// or the indoor card when there is no trace) is one tap away. The Flyover
/// chip rides the map face.
///
/// Media interactions are Instagram's: pinch a photo to zoom it in place
/// (no modal — it floats over the UI and springs back), and double-tap a
/// friend's photo to hype it with a clap burst.
struct PostCardView: View {
    let post: PostItem
    /// The run's story-only photo, when different from the post media.
    var storyPhotoURL: URL? = nil
    var isHyping: Bool = false
    /// Daily hype allowance spent (never true for unlimited roles) — dims the
    /// unspent Hype button, same as the friends list.
    var isOutOfHypes: Bool = false
    let onHype: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void
    let onDelete: () -> Void
    /// Own posts: opens the caption editor (hidden from the menu when nil).
    var onEditCaption: (() -> Void)? = nil
    /// A buddy walk you're credited on: the words under YOUR OWN slide. Not
    /// `onEditCaption` — that one edits the post's caption, which belongs to
    /// the author and is not this person's to change.
    var onEditMyCollabCaption: (() -> Void)? = nil
    /// Tap the author's avatar or name to open their profile.
    var onTapAuthor: (() -> Void)? = nil
    /// Tap the collab coauthor's avatar or name to open THEIR profile —
    /// Instagram behavior: each tagged name on a collab post routes to its own
    /// person, not the primary author.
    var onTapCoauthor: (() -> Void)? = nil
    /// A credited crew member on a buddy walk, tapped from the crew list that
    /// the multi-person byline opens. Nil leaves the list read-only.
    var onTapCrewMember: ((PostCoauthorItem) -> Void)? = nil
    /// Tap an @mention inside the caption — called with the mentioned
    /// username (lowercased, without the '@') to open that user's profile.
    var onTapMention: ((String) -> Void)? = nil
    /// Tap the hype tally to see who hyped (Instagram-likes style).
    var onTapHypeCount: (() -> Void)? = nil
    /// Open the Instagram-style comments sheet.
    var onOpenComments: (() -> Void)? = nil
    /// Non-nil when the CURRENT user is this post's pending coauthor —
    /// shows the Accept/Decline collab banner. Called with accept/decline.
    var onRespondCoauthor: ((Bool) -> Void)? = nil
    /// Copy/share a link to this post. Offered on every post, own or not —
    /// the link's landing page shows nothing the recipient isn't already
    /// entitled to (see PostShareLink).
    var onShare: (() -> Void)? = nil
    /// Accepted coauthor: leave this post (remove self as coauthor).
    var onLeaveCollab: (() -> Void)? = nil
    /// Accepted coauthor: pin this collab on/off MY profile grid, called with
    /// the new value. The lighter sibling of `onLeaveCollab` — the tag stays,
    /// only my grid changes. Wired alongside it; the menu still gates on the
    /// server having sent `coauthor_on_profile`.
    var onSetCollabOnProfile: ((Bool) -> Void)? = nil
    /// Accepted coauthor: does this collab reach MY friends' feeds? Deliberately
    /// a third switch rather than folded into the grid one — "keep it off my
    /// grid" and "don't put it in my friends' feeds" are different asks, and a
    /// user who only wants the second shouldn't have to give up the tag.
    /// Gated on the server having sent `coauthor_on_feed`.
    var onSetCollabOnFeed: ((Bool) -> Void)? = nil
    /// Credited participant: is MY route drawn on this post? Overrides my
    /// global "Share route maps" for this one card. Gated on my own row
    /// actually being in `coauthors`.
    var onSetMyCollabRoute: ((Bool) -> Void)? = nil
    /// Author: add or withdraw the route map slide after posting.
    var onSetIncludeRoute: ((Bool) -> Void)? = nil

    @State private var hypeBurst = 0
    /// The legend chip that was tapped: that walker's line leads, the rest
    /// dim. `"author"` for the poster, else a coauthor's user id.
    @State private var highlightedRouteId: String? = nil
    /// Collapses the same physical double-tap arriving from two recognizers
    /// (the card-level SwiftUI gesture AND the zoom host's UIKit one) into a
    /// single burst + hype.
    @State private var lastDoubleTapAt = Date.distantPast
    /// Set by the route slide's Flyover chip; item-based so the cover can't
    /// race a stale value (the fullScreenCover rule in ios.md).
    @State private var flyoverLaunch: FlyoverLaunch?
    /// The media page on screen: the photo face's slides come first, the map
    /// face is the last page. Both the PHOTO | MAP toggle and a swipe move it.
    @State private var mediaPage = 0
    @State private var showCrew = false
    @State private var showSplits = false
    /// The art card's ghost-map snapshot, kept for the pinch-zoom composite
    /// (same contract the map view had).
    @State private var routeArtSnapshot: RouteMapSnapshot?
    /// Paper-plane route share payload: same rendered route image the old map
    /// chip shared, just moved into the Instagram-style action row.
    /// Own post tapped Share — the story studio, built from this card.
    @State private var storyShare: MADStoryContent?
    /// True if the current user is the post author.
    private var isMine: Bool {
        post.is_self
    }

    /// My own row among the credited participants, if I'm one of them. The
    /// server only fills a participant's private switches (`on_feed`,
    /// `include_route`) on their OWN row, so this is the only row worth
    /// reading them from.
    private var myCoauthorRow: PostCoauthorItem? {
        guard let me = UserDefaults.standard.string(forKey: "backendUserId") else { return nil }
        return post.acceptedCoauthors.first { $0.user_id == me }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            header
            // Instagram behavior: double-tap ANYWHERE on the post body —
            // photo, route map, stats, caption, or the space between — hypes.
            // `simultaneousGesture` so single taps (paging dots, horizontal
            // swipes, pinch zoom) are untouched. The header and footer stay
            // out so double-tapping a button can't hype by accident.
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                media
                mediaControls
                crewGroupLine
                // The names-to-colours key belongs to the map, so it shows only
                // while the map face is up — under it rather than on it, since
                // the stats band owns the bottom of that face.
                if currentFace == .map {
                    crewRouteLegend
                }
                // The header shows the day's combined mile when this post is
                // attached to the workout that completed one made of several
                // walks; without the breakdown that total looks like a single run.
                if let segments = post.segments, segments.count > 1 {
                    MileSegmentStrip(
                        segments: segments,
                        accent: ActivityCardView.color(post.workout_type)
                    )
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture(count: 2).onEnded { doubleTapHype() }
            )
            if onRespondCoauthor != nil {
                coauthorInviteBanner
            }
            footer
        }
        .padding(MADTheme.Spacing.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .fullScreenCover(item: $flyoverLaunch) { launch in
            RouteFlyoverPlayerView(launch: launch)
        }
        .sheet(item: $storyShare) { content in
            ShareStudioView(content: content,
                            link: post.share_to_feed == false
                                ? nil : PostShareLink.url(for: post.post_id))
        }
    }

    /// "Walk · 1.08 mi · 2d" under the name: what it was (in the walk-blue /
    /// run-red language), how far, how long ago. The distance carries the feed
    /// role's framing ("+0.14 mi extra" once the goal was already banked), so
    /// the numbers no longer need a chip row of their own.
    private var subtitleLine: some View {
        HStack(spacing: 4) {
            Image(systemName: ActivityCardView.icon(post.workout_type, paceSecondsPerMile: post.stats_snapshot?.pace))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(ActivityCardView.color(post.workout_type))
            Text(headerSubtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
        }
    }

    private var headerSubtitle: String {
        var parts = [Self.activityNoun(post.workout_type, pace: post.stats_snapshot?.pace)]
        if let d = post.stats_snapshot?.distance, d > 0 {
            parts.append(post.feed_role == "extra" ? "+\(d.distanceFormatted) extra" : d.distanceFormatted)
        }
        parts.append(post.relativeTime)
        return parts.joined(separator: " · ")
    }

    /// "Walk" / "Run" — the noun form of `ActivityCardView.verb`, with the
    /// same pace-aware fallback for `.other`-typed workouts.
    static func activityNoun(_ type: String?, pace: Double?) -> String {
        switch ActivityCardView.verb(type, paceSecondsPerMile: pace) {
        case "Ran": return "Run"
        case "Walked": return "Walk"
        case "Hiked": return "Hike"
        case "Cycled": return "Ride"
        default: return "Workout"
        }
    }

    /// Name style shared by the header's tappable name segments.
    private func nameText(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .lineLimit(1)
    }

    /// "Beat the ghost" chip, shown when the post's workout won its race.
    ///
    /// The margin is the whole story — "GHOST −14s" says you beat the thing you
    /// were chasing by fourteen seconds, in the width of a word. `fixedSize()`
    /// because on a collab header carrying two names, the chip must never be
    /// what gets squeezed — let the names truncate instead.
    private func ghostChip(margin: Double) -> some View {
        HStack(spacing: 4) {
            GhostSprite(size: 11, color: .white, floats: false)
            Text("−\(max(1, Int(margin.rounded())))s")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .monospacedDigit()
        }
        .foregroundColor(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: [Color(red: 0.42, green: 0.31, blue: 0.85),
                             Color(red: 0.24, green: 0.18, blue: 0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        )
        .fixedSize()
    }

    /// Buddy Walk header: a stack of avatars plus a byline that collapses past
    /// three names. Deliberately a separate branch from the two-person collab
    /// header below rather than a generalization of it — that one is tuned and
    /// shipped, and a walk with one friend must keep looking exactly as it does
    /// today.
    private var multiCollabHeader: some View {
        let others = post.acceptedCoauthors
        return HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                Button { onTapAuthor?() } label: {
                    AvatarView(name: post.displayName, imageURL: post.profile_image_url, size: 40)
                }
                .buttonStyle(.plain)
                .allowsHitTesting(onTapAuthor != nil)

                // Only ever two overlap on the author; more than that and the
                // stack reads as mush at 40pt. The count lives in the byline.
                ForEach(Array(others.prefix(2).enumerated()), id: \.element.id) { index, coauthor in
                    AvatarView(
                        name: coauthor.displayName,
                        imageURL: coauthor.profile_image_url,
                        size: 26
                    )
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.7), lineWidth: 2))
                    .offset(x: 24 + CGFloat(index) * 16, y: 8)
                }
            }
            .padding(.trailing, CGFloat(min(others.count, 2)) * 16)

            VStack(alignment: .leading, spacing: 1) {
                // One tap target, and it opens EVERYONE: "rob, Megs & 2
                // others" used to route to the author alone, so the two
                // people folded into "others" were unreachable from the card
                // that credits them. The list names each person and opens
                // their profile.
                Button {
                    MADHaptics.tap()
                    showCrew = true
                } label: {
                    nameText(post.multiCollabByline)
                }
                .buttonStyle(.plain)

                subtitleLine
            }
        }
        // On the HEADER node: the card root already owns the flyover cover
        // and the share sheet, the media node owns splits — a fourth
        // presentation on any of those drops one.
        .sheet(isPresented: $showCrew) {
            PostCrewSheet(post: post) { member in
                // Dismiss first, then open — a profile raised in the sheet's
                // own dismissal transaction is dropped (the HypersListSheet
                // rule). `member` nil means the author.
                showCrew = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    if let member { onTapCrewMember?(member) } else { onTapAuthor?() }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if post.isMultiCollab {
                multiCollabHeader
            } else if post.hasAcceptedCoauthor {
                // Collab post: overlapping avatars + "a & b", like Instagram's
                // collab header — and like Instagram, each avatar/name is its
                // OWN tap target routing to that person's profile.
                // The overlap is PADDING, not `.offset` — an offset draws
                // outside the layout bounds, so the cluster measured 40pt tall
                // while occupying 44, and everything else in the header (the
                // chips especially) centered 2pt high against it.
                ZStack(alignment: .bottomTrailing) {
                    Button { onTapAuthor?() } label: {
                        AvatarView(name: post.displayName, imageURL: post.profile_image_url, size: 40)
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(onTapAuthor != nil)
                    .padding(.trailing, 8)
                    .padding(.bottom, 4)
                    Button { onTapCoauthor?() } label: {
                        AvatarView(name: post.coauthorDisplayName,
                                   imageURL: post.coauthor_profile_image_url, size: 26)
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.7), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(onTapCoauthor != nil)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 0) {
                        Button { onTapAuthor?() } label: { nameText(post.displayName) }
                            .buttonStyle(.plain)
                            .allowsHitTesting(onTapAuthor != nil)
                        Text(" & ")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                        Button { onTapCoauthor?() } label: { nameText(post.coauthorDisplayName) }
                            .buttonStyle(.plain)
                            .allowsHitTesting(onTapCoauthor != nil)
                    }
                    subtitleLine
                }
            } else {
                Button {
                    onTapAuthor?()
                } label: {
                    HStack(spacing: 10) {
                        AvatarView(name: post.displayName, imageURL: post.profile_image_url, size: 40)
                        VStack(alignment: .leading, spacing: 1) {
                            nameText(post.displayName)
                            subtitleLine
                        }
                    }
                }
                .buttonStyle(.plain)
                .allowsHitTesting(onTapAuthor != nil)
            }
            if let win = post.stats_snapshot?.ghostWin { ghostChip(margin: win.margin) }
            Spacer()
            Menu {
                if post.is_self {
                    if let onEditCaption {
                        Button(action: onEditCaption) {
                            Label("Edit caption", systemImage: "pencil")
                        }
                    }
                    // The route was the one thing about a post you could only
                    // decide before sharing, and it's the thing people most
                    // often want back. Withdrawing the slide doesn't touch the
                    // trace, so turning it on again restores the same map.
                    if let onSetIncludeRoute, post.is_auto != true,
                       let showing = post.include_route {
                        Button {
                            onSetIncludeRoute(!showing)
                        } label: {
                            Label(showing ? "Hide the route map" : "Show the route map",
                                  systemImage: showing ? "map.slash" : "map")
                        }
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label(post.share_to_feed == false ? "Delete story" : "Delete post",
                              systemImage: "trash")
                    }
                } else if let onLeaveCollab {
                    // Accepted coauthor: the post is the AUTHOR's to edit or
                    // delete, but leaving it is theirs. Reporting/blocking a
                    // post you're an author of makes no sense, so neither shows.
                    //
                    // Your words under your own picture, first because it is
                    // the only thing here that ADDS to the post. The author
                    // has had "Edit caption" since captions existed; a
                    // credited participant could only ever type one in the
                    // composer at the instant they added the photo, so anyone
                    // who didn't had a slide on the card that could never
                    // carry their voice — and the card, correctly, shows
                    // nothing under it, which reads as their words being lost.
                    // Only offered once there IS a slide of theirs to caption.
                    if let onEditMyCollabCaption, myCoauthorRow?.media_url != nil {
                        Button(action: onEditMyCollabCaption) {
                            Label(myCoauthorRow?.caption?.isEmpty == false
                                  ? "Edit my caption" : "Add my caption",
                                  systemImage: "pencil")
                        }
                    }
                    // Curating comes BEFORE leaving, and isn't destructive:
                    // most people who don't want a tag on their grid still
                    // want the tag. `coauthor_on_profile` is nil on servers
                    // that don't know about the grid split — no toggle then.
                    if let onSetCollabOnProfile, let onProfile = post.coauthor_on_profile {
                        Button {
                            onSetCollabOnProfile(!onProfile)
                        } label: {
                            Label(onProfile ? "Remove from my grid" : "Add to my grid",
                                  systemImage: onProfile ? "minus.square" : "square.grid.3x3")
                        }
                    }
                    if let onSetCollabOnFeed, let onFeed = post.coauthor_on_feed {
                        Button {
                            onSetCollabOnFeed(!onFeed)
                        } label: {
                            Label(onFeed ? "Hide from my friends' feeds"
                                         : "Show in my friends' feeds",
                                  systemImage: onFeed ? "eye.slash" : "eye")
                        }
                    }
                    // Being credited on someone's post is not consent to
                    // publish your own GPS trace, and the answer can differ
                    // per walk — hence a per-post override above the global
                    // setting rather than only the global one.
                    if let onSetMyCollabRoute, let mine = myCoauthorRow,
                       mine.include_route != nil || mine.route != nil {
                        let showing = mine.include_route ?? true
                        Button {
                            onSetMyCollabRoute(!showing)
                        } label: {
                            Label(showing ? "Hide my route on this post"
                                          : "Show my route on this post",
                                  systemImage: showing ? "map.slash" : "map")
                        }
                    }
                    Button(role: .destructive, action: onLeaveCollab) {
                        Label("Remove me from this post", systemImage: "person.badge.minus")
                    }
                } else {
                    Button(action: onReport) { Label("Report", systemImage: "flag") }
                    Button(role: .destructive, action: onBlock) {
                        Label("Block \(post.displayName)", systemImage: "hand.raised")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(6)
                    .contentShape(Rectangle())
            }
        }
    }

    /// Route slide coordinates — hidden for auto posts, whose media already IS
    /// the rendered route/stats card (a second identical slide would be noise).
    /// The SLIDE only: the Flyover chip reads `post.routeCoordinates` directly,
    /// so an auto card still flies — the server ships its route for exactly
    /// that (AUTHOR_ROUTE_SQL), and a user whose history is mostly auto posts
    /// otherwise had no Flyover anywhere on the feed.
    private var routeSlideCoordinates: [CLLocationCoordinate2D]? {
        guard post.is_auto != true else { return nil }
        return post.routeCoordinates
    }

    /// Image slides, real moment first: when the run has a story photo it
    /// leads, and the post media (photo or route/stats card) becomes the
    /// second slide — never a cramped corner thumbnail. Photos the server
    /// withheld arrive blank and drop out here; `photoSlides` puts a single
    /// lock in their place, ahead of whatever survived.
    private var photoURLs: [URL] {
        if let storyPhotoURL {
            return [storyPhotoURL, post.mediaURL].compactMap { $0 }
        }
        return [post.mediaURL].compactMap { $0 }
    }

    /// Whether to append a branded workout-stats card as the run's second
    /// slide. Only when there's no route map to show instead, the media isn't
    /// already a stats card (auto post), and we actually have stats — so every
    /// photo post reads "photo → the run", not a lone photo.
    private var workoutCardStats: PostStats? {
        guard post.is_auto != true,
              routeSlideCoordinates == nil,
              storyPhotoURL == nil,
              let stats = post.stats_snapshot,
              (stats.distance ?? 0) > 0
        else { return nil }
        return stats
    }

    /// Footer button: toggle hype with the same clap burst the double-tap uses.
    private func celebrateAndHype() {
        hypeBurst += 1
        MADHaptics.action()
        onHype()
    }

    /// Double-tap anywhere on the post body: clap burst + hype (once — a
    /// re-double-tap replays the burst without double-counting). Your own
    /// post included: self-hypes are allowed, like liking your own photo.
    private func doubleTapHype() {
        let now = Date()
        guard now.timeIntervalSince(lastDoubleTapAt) > 0.35 else { return }
        lastDoubleTapAt = now
        hypeBurst += 1
        MADHaptics.action()
        if !post.is_hyped { onHype() }
    }

    /// Shown in place of a WITHHELD PHOTO — a frosted "run to unlock" card,
    /// matching the app's earn-to-view story gate. It's one slide among the
    /// rest, so it clips like a photo slide rather than squaring off next to
    /// them.
    private var lockedMediaCard: some View {
        ZStack {
            LinearGradient(
                colors: [MADTheme.Colors.madRed.opacity(0.30), Color.black.opacity(0.65)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                Text("Finish your mile to unlock")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("Today's photos open up once you complete your own mile.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
    }

    /// One page of the media carousel.
    private enum MediaSlide {
        /// Stands in for the photo(s) the server withheld.
        case locked
        case photo(url: URL, badged: Bool)
        /// A crew member's own photo on a buddy walk's shared post — captioned
        /// with their name, because on a card with four pictures on it "whose
        /// is this" is the question every slide raises.
        case crewPhoto(url: URL, userId: String, name: String, username: String?, caption: String?)
        case route(coords: [CLLocationCoordinate2D])
        case statsCard(stats: PostStats)
    }

    /// Each credited participant's photo, in the order the server credited
    /// them — the same order the route colours use, so slide 3 belongs to the
    /// person whose line is the third in the legend.
    private var crewPhotoSlides: [MediaSlide] {
        post.acceptedCoauthors.compactMap { coauthor -> MediaSlide? in
            guard let url = coauthor.mediaURL else { return nil }
            return .crewPhoto(url: url, userId: coauthor.user_id,
                              name: coauthor.displayName,
                              username: coauthor.username, caption: coauthor.caption)
        }
    }

    /// The PHOTO face's pages in swipe order: the lock (standing in for ANY
    /// withheld photo, however many were held back) → the photos that survived
    /// the gate → the crew's photos. The route/stats card is not a page here
    /// any more — it's the MAP face.
    ///
    /// The lock only ever replaces a picture, so a viewer who hasn't run yet
    /// can still flip to a friend's map, just not see their photo.
    private var photoSlides: [MediaSlide] {
        var slides: [MediaSlide] = []
        if post.isPhotoLocked { slides.append(.locked) }
        for url in photoURLs {
            // Badge an auto route/stats card that trails a photo (or its lock)
            // so the swipe reads "photo → stats".
            slides.append(.photo(url: url, badged: !slides.isEmpty && post.is_auto == true))
        }
        // The crew's photos ride BEHIND the author's: a buddy walk reads "their
        // shot → everyone else's shots". Empty on every ordinary post.
        slides.append(contentsOf: crewPhotoSlides)
        return myPhotoFirst(slides)
    }

    /// On a walk I was on and added a photo to, MY slide leads.
    ///
    /// A buddy walk is ONE post, so there is no "my post" to open — my
    /// picture of it is a slide on somebody else's card, three swipes in,
    /// and the card I see is led by a photo I didn't take. Everyone on the
    /// walk sees their own first, which is as close as one shared card gets
    /// to each person having posted it.
    ///
    /// Order-only, and only for a slide that is mine: the author's own view is
    /// unchanged (their photo already leads), a viewer who wasn't on the walk
    /// sees the author-first order, and nothing is added or removed. The lock
    /// stays first when it's there — it stands in for a photo this viewer
    /// hasn't earned, and moving it behind one would read as the gate being
    /// off.
    private func myPhotoFirst(_ slides: [MediaSlide]) -> [MediaSlide] {
        guard let me = UserDefaults.standard.string(forKey: "backendUserId"),
              me != post.user_id,
              let mine = post.acceptedCoauthors.first(where: { $0.user_id == me }),
              let myURL = mine.mediaURL,
              let index = slides.firstIndex(where: {
                  if case .crewPhoto(let url, _, _, _, _) = $0 { return url == myURL }
                  return false
              })
        else { return slides }
        var reordered = slides
        let slide = reordered.remove(at: index)
        // Behind the lock, never in front of it.
        reordered.insert(slide, at: post.isPhotoLocked ? 1 : 0)
        return reordered
    }

    /// What the MAP face shows: the route — the crew's lines too, or only
    /// theirs when the author walked indoors (a group card with bare numbers
    /// while the routes it's about exist is the old bug in miniature) — else
    /// the run as the indoor card. nil = nothing to flip to.
    private var mapSlide: MediaSlide? {
        if let coords = routeSlideCoordinates { return .route(coords: coords) }
        if !companionRoutes.isEmpty, post.is_auto != true { return .route(coords: []) }
        if let stats = workoutCardStats { return .statsCard(stats: stats) }
        return nil
    }

    private enum MediaFace: Equatable {
        case photo, map
    }

    /// Every page in swipe order: the photo face's slides, then the map face.
    private var mediaPages: [MediaSlide] {
        photoSlides + (mapSlide.map { [$0] } ?? [])
    }

    /// The map face's page index, when there is one.
    private var mapPageIndex: Int? {
        mapSlide == nil ? nil : photoSlides.count
    }

    /// The face on screen, read off the page — so a swipe and a toggle tap
    /// can't disagree about what's showing.
    private var currentFace: MediaFace {
        if let mapPageIndex, mediaPage >= mapPageIndex { return .map }
        return photoSlides.isEmpty ? .map : .photo
    }

    private var hasFaceToggle: Bool { !photoSlides.isEmpty && mapSlide != nil }

    /// "MAP" when there's a route to draw, "STATS" for the indoor card —
    /// never "indoor": routeless can also mean maps switched off.
    private var mapFaceTitle: String {
        if case .statsCard = mapSlide { return "STATS" }
        return "MAP"
    }

    @ViewBuilder
    private func slideView(_ slide: MediaSlide) -> some View {
        switch slide {
        case .locked:
            lockedMediaCard
        case .photo(let url, let badged):
            ZoomablePhotoSlide(
                url: url,
                badge: badged ? ("Stats", "chart.bar.fill") : nil,
                onDoubleTap: doubleTapHype
            )
        case .crewPhoto(let url, _, let name, _, _):
            ZoomablePhotoSlide(
                url: url,
                badge: (name, "person.fill"),
                onDoubleTap: doubleTapHype
            )
        case .route(let coords):
            routeSlide(coords)
        case .statsCard(let stats):
            workoutCardSlide(stats)
        }
    }

    /// One 4:5 media box: a swipeable carousel of every page (photos first,
    /// the map last), the FLYOVER/SPLITS chips leading and the PHOTO | MAP
    /// toggle trailing, jumping between the two faces. Every one of those is
    /// overlaid on this container — i.e. AFTER every slide's
    /// `.instagramZoomable` — or the zoom gesture host eats their taps. The
    /// hype burst plays centered over whichever page is showing.
    @ViewBuilder
    private var media: some View {
        let pages = mediaPages
        Group {
            if pages.count > 1 {
                TabView(selection: $mediaPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, slide in
                        slideView(slide).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .interactive))
            } else if let only = pages.first {
                slideView(only)
            } else {
                emptyMedia
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .overlay(HypeBurstView(trigger: hypeBurst))
        // On the MEDIA node: the card root already owns the flyover cover
        // and the share sheet, and two presentations on one node drop one.
        .sheet(isPresented: $showSplits) {
            // On a walk together the sheet opens on ME when I was there —
            // the first question anyone asks of a shared card is their own
            // number, and everyone else is one tap away in the picker.
            WorkoutSplitsSheet(
                walkers: crewWalkers,
                workoutType: post.workout_type,
                isIndoor: post.is_indoor,
                groupDistance: post.buddy_group?.distance_miles,
                initialWalkerId: crewWalkers.first(where: { $0.id == currentUserId })?.id
            )
        }
    }

    /// FLYOVER · SPLITS · PHOTO | MAP — the host's controls, in a row UNDER
    /// the media rather than on it.
    ///
    /// They were overlaid, and there is no corner of a 4:5 card that is
    /// reliably empty. The route face bakes its stats across the bottom
    /// (distance bottom-left, brand mark bottom-right); the indoor card draws
    /// its activity capsule and date across the top; a photo badges itself
    /// top-left with the crew member's name; and an AUTO post is a baked route
    /// card served as a PHOTO, so it wears the bottom band while counting as
    /// the photo face. Placing the chips per-face dodged each of those in turn
    /// and produced the two things actually worth avoiding: a FLYOVER pill
    /// sitting on somebody's "1.53 MI", and controls that move as you swipe.
    ///
    /// Under the media there is no collision to dodge, so the position is the
    /// same on every card and every face — and the chips stop competing with
    /// the photograph, which is the thing the card is for.
    /// The row must fit the CARD, and on the narrowest phone all three
    /// controls together are wider than it is. A squeezed `HStack` does not
    /// re-arrange — it hands the shortfall to the innermost `Text`, which
    /// wraps, so the pills rendered "FLYOVE / R" and "PHOT / O" with the row
    /// itself still nominally in one line. The labels now refuse to wrap
    /// (constant words, so a published width is bounded), which makes fitting
    /// the row this view's job: one line where it fits, otherwise the same
    /// three controls stacked — candidates that differ in ARRANGEMENT only,
    /// never in content, so a wrong guess can only change the layout and
    /// never silently delete a control.
    @ViewBuilder
    private var mediaControls: some View {
        if canPlayFlyover || hasSplits || hasFaceToggle {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    mediaControlChips
                    Spacer(minLength: 8)
                    if hasFaceToggle { faceToggle }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        mediaControlChips
                        Spacer(minLength: 0)
                    }
                    if hasFaceToggle {
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            faceToggle
                        }
                    }
                }
            }
        }
    }

    /// The leading half of the control row, shared by both arrangements so the
    /// two candidates cannot drift into offering different things.
    @ViewBuilder
    private var mediaControlChips: some View {
        if canPlayFlyover { flyoverChip }
        if hasSplits { splitsChip }
    }

    /// The post's per-mile splits, shaped for drawing. Empty on older servers,
    /// stitched rollups and auto posts — the chip then simply isn't there.
    private var splitBars: [WorkoutSplitBar] {
        WorkoutSplitBar.bars(from: post.splits)
    }

    /// The chip draws when ANYONE on the walk has splits. On a buddy card the
    /// author is often the person whose phone didn't record any, and gating on
    /// theirs alone hid the whole crew's.
    private var hasSplits: Bool {
        !splitBars.isEmpty
            || post.acceptedCoauthors.contains { !($0.splits ?? []).isEmpty }
    }

    private var splitsChip: some View {
        SplitsChipButton(accent: ActivityCardView.color(post.workout_type)) {
            showSplits = true
        }
    }

    /// No media at all — the empty-state placeholder.
    private var emptyMedia: some View {
        ZoomablePhotoSlide(
            url: nil,
            badge: nil,
            onDoubleTap: doubleTapHype
        )
    }

    /// PHOTO | MAP, trailing end of the control row. Photo leads. Lifted off
    /// the card's ground rather than the black glass it wore on a photo —
    /// a 55%-black capsule on a dark card reads as a hole in it.
    private var faceToggle: some View {
        HStack(spacing: 2) {
            faceSegment("PHOTO", .photo)
            faceSegment(mapFaceTitle, .map)
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func faceSegment(_ title: String, _ target: MediaFace) -> some View {
        let selected = currentFace == target
        return Button {
            guard !selected else { return }
            MADHaptics.tap()
            withAnimation(.easeInOut(duration: 0.25)) {
                mediaPage = target == .map ? (mapPageIndex ?? 0) : 0
            }
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(0.5)
                .foregroundColor(selected ? .black : .white.opacity(0.85))
                // "PHOTO" and "MAP"/"STATS" are constants, so this can't
                // publish a runaway width — and it is what stopped a narrow
                // card rendering the segment as "PHOT / O".
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Capsule().fill(selected ? Color.white.opacity(0.94) : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(title.lowercased())")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// ▶ FLYOVER, top-left of the media — the shared chip, in the workout's colour.
    private var flyoverChip: some View {
        FlyoverChipButton(accent: ActivityCardView.color(post.workout_type)) {
            flyoverLaunch = makeFlyoverLaunch(routeSlideCoordinates ?? [])
        }
    }

    /// The run itself as the animated indoor card — the second face when a
    /// photo post has no GPS route to show (track or treadmill face by the
    /// viewer's dashboard style). The card-level double-tap covers it. Zooms
    /// like every other slide; the card is pure SwiftUI so its zoom copy
    /// renders on demand at pinch-begin as a still frame of the same inputs.
    private func workoutCardSlide(_ stats: PostStats) -> some View {
        indoorCard(stats, still: false)
            .frame(maxWidth: .infinity)
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .instagramZoomable(
                imageProvider: {
                    // SAME construction as the live card (one helper), still
                    // frame only — a divergent zoom copy is the live-vs-baked
                    // drift class WorkoutStatTileGrid exists to prevent.
                    let renderer = ImageRenderer(content:
                        indoorCard(stats, still: true)
                            .frame(width: RunStatsCardView.designSize.width,
                                   height: RunStatsCardView.designSize.height)
                    )
                    renderer.scale = 2
                    renderer.isOpaque = true
                    return renderer.uiImage
                },
                onDoubleTap: doubleTapHype
            )
    }

    private func indoorCard(_ stats: PostStats, still: Bool) -> IndoorWorkoutCard {
        IndoorWorkoutCard(
            stats: stats,
            workoutType: post.workout_type,
            splits: WorkoutSplitBar.bars(from: post.splits),
            avatar: RouteArtAvatar(name: post.displayName, imageURL: post.profile_image_url),
            isIndoor: post.is_indoor,
            still: still
        )
    }

    /// Stats to overlay on the live route slide — same band the auto post
    /// bakes into its image, so a route NEVER shows as a bare map when the
    /// post carries numbers.
    private var routeOverlayStats: RunStatsInput? {
        guard let stats = post.stats_snapshot, let distance = stats.distance, distance > 0
        else { return nil }
        return RunStatsInput(
            distance: distance,
            paceSecondsPerMile: stats.pace,
            durationSeconds: stats.duration,
            streak: stats.streak,
            calories: stats.calories,
            steps: stats.steps,
            workoutId: nil,
            dateText: stats.date
        )
    }

    /// Everyone else's trace, in the order the server credited them so the
    /// colours are stable between reads. Empty for an ordinary post, and for
    /// any crew member who walked indoors or shares no maps.
    /// Every credited person's colour, keyed by user id — the ONE assignment.
    ///
    /// Colours are assigned across the WHOLE credited crew and then filtered,
    /// never assigned to the filtered list: a coauthor who walked indoors must
    /// not shift everybody behind them onto a different colour, or the same
    /// walk keys differently depending on whose route happened to load. It's a
    /// map rather than an array for the same reason the route legend and the
    /// splits picker both read it: the person you tap in one has to be the
    /// person whose line you were looking at in the other.
    ///
    /// `avoiding:` is what keeps the first companion off the author's own
    /// accent — a walking crew card drew blue beside blue without it.
    private var crewColors: [String: Color] {
        let palette = CrewRoutePalette.companionColors(
            count: post.acceptedCoauthors.count,
            avoiding: ActivityCardView.color(post.workout_type)
        )
        var out: [String: Color] = [:]
        for (index, coauthor) in post.acceptedCoauthors.enumerated() {
            out[coauthor.user_id] = palette[index]
        }
        return out
    }

    private var companionRoutes: [CompanionRoute] {
        let colors = crewColors
        return post.acceptedCoauthors.compactMap { coauthor -> CompanionRoute? in
            guard let coords = coauthor.routeCoordinates,
                  let color = colors[coauthor.user_id] else { return nil }
            return CompanionRoute(
                id: coauthor.user_id,
                coordinates: coords,
                color: color
            )
        }
    }

    /// Everyone who walked, for the splits sheet: the author first (it's their
    /// card), then the crew in credited order — the same order the route
    /// colours and the photo slides use.
    ///
    /// Includes people with no splits on purpose. A crew member whose phone
    /// hasn't handed us any is still someone who was on the walk, and a picker
    /// that silently omits them reads as the app having lost them; the sheet
    /// says so in words instead.
    private var crewWalkers: [WorkoutSplitsSheet.Walker] {
        let colors = crewColors
        var walkers: [WorkoutSplitsSheet.Walker] = [
            WorkoutSplitsSheet.Walker(
                id: post.user_id,
                name: post.is_self ? "You" : post.displayName,
                color: ActivityCardView.color(post.workout_type),
                distance: post.stats_snapshot?.distance,
                durationSeconds: post.stats_snapshot?.duration,
                movingSeconds: nil,
                bars: splitBars,
                servedPace: post.stats_snapshot?.pace
            )
        ]
        for coauthor in post.acceptedCoauthors {
            walkers.append(
                WorkoutSplitsSheet.Walker(
                    id: coauthor.user_id,
                    name: coauthor.user_id == currentUserId ? "You" : coauthor.displayName,
                    color: colors[coauthor.user_id] ?? .white,
                    distance: coauthor.distance_miles,
                    durationSeconds: coauthor.duration_seconds,
                    movingSeconds: coauthor.moving_seconds,
                    bars: WorkoutSplitBar.bars(from: coauthor.splits)
                )
            )
        }
        return walkers
    }

    /// The signed-in user, for "You" and for whose slide leads.
    private var currentUserId: String? {
        UserDefaults.standard.string(forKey: "backendUserId")
    }

    /// "3.2 mi between the 3 of you" — the walk, not the walker.
    ///
    /// A buddy post's own stat strip shows the AUTHOR's distance, which is
    /// correct (it's their post and their photo) and also, on a card whose
    /// whole subject is that several people went out together, the smaller and
    /// less interesting of the two numbers. The recap has always led with the
    /// combined figure; the card never showed it at all.
    @ViewBuilder
    private var crewGroupLine: some View {
        if let group = post.buddy_group, group.crew_size > 1, group.distance_miles > 0 {
            HStack(spacing: 6) {
                Image(systemName: "figure.2")
                    .font(.system(size: 12, weight: .bold))
                Text("\(group.distance_miles.milesText) mi between the \(group.crew_size) of you")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
            }
            .foregroundColor(ActivityCardView.color(post.workout_type))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(ActivityCardView.color(post.workout_type).opacity(0.14))
            )
            .padding(.horizontal, 2)
        }
    }

    /// The names-to-colours key under a combined map. Without it a card with
    /// four lines on it is just four lines — the whole point is seeing which
    /// one is yours. Each chip is a BUTTON: tap a walker to bring their line
    /// to the front and dim the rest (two people who walked the same loop
    /// are laned apart, but a tap is how you're sure); tap again to clear.
    @ViewBuilder
    private var crewRouteLegend: some View {
        let companions = companionRoutes
        if !companions.isEmpty {
            let byId: [String: String] = Dictionary(
                post.acceptedCoauthors.map { ($0.user_id, $0.displayName) },
                uniquingKeysWith: { first, _ in first }
            )
            // Each line's own distance, on its own chip: the map already says
            // who is who, and this is the other half of the same question.
            let milesById: [String: Double] = Dictionary(
                post.acceptedCoauthors.compactMap { c in
                    c.distance_miles.map { (c.user_id, $0) }
                },
                uniquingKeysWith: { first, _ in first }
            )
            // Wraps rather than truncates: five names on one line would clip
            // whoever came last, which on a card about being together is the
            // one thing it must not do.
            FlowLayout(spacing: 10) {
                legendChip(
                    id: Self.authorRouteId,
                    name: post.displayName,
                    color: ActivityCardView.color(post.workout_type),
                    miles: post.stats_snapshot?.distance
                )
                ForEach(companions) { companion in
                    legendChip(
                        id: companion.id,
                        name: byId[companion.id] ?? "a friend",
                        color: companion.color,
                        miles: milesById[companion.id]
                    )
                }
            }
            .padding(.horizontal, 2)
        }
    }

    /// Sentinel the art view uses for the poster's own line.
    private static let authorRouteId = "author"

    private func legendChip(
        id: String,
        name: String,
        color: Color,
        miles: Double? = nil
    ) -> some View {
        let selected = highlightedRouteId == id
        let dimmed = highlightedRouteId != nil && !selected
        return Button {
            MADHaptics.tap()
            withAnimation(.easeInOut(duration: 0.2)) {
                highlightedRouteId = selected ? nil : id
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: selected ? "scope" : "hand.tap.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(dimmed ? 0.35 : 0.8))
                Capsule()
                    .fill(color)
                    .frame(width: selected ? 18 : 14, height: 4)
                Text(name)
                    .font(.system(size: 12, weight: selected ? .heavy : .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(dimmed ? 0.4 : (selected ? 0.95 : 0.75)))
                    .lineLimit(1)
                if let miles, miles > 0 {
                    Text(miles.distanceFormatted)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(dimmed ? 0.3 : 0.55))
                }
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(color)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(selected ? color.opacity(0.18) : Color.white.opacity(0.07))
            )
            .overlay(
                Capsule().strokeBorder(
                    selected ? color.opacity(0.78) : Color.white.opacity(0.13),
                    lineWidth: selected ? 1.5 : 1
                )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selected ? "\(name)'s route, highlighted" : "Highlight \(name)'s route")
    }

    /// Riders for the crew's lines, keyed the same way `companionRoutes` is
    /// (user id), so each badge lands on its owner's line.
    private var companionRouteAvatars: [String: RouteArtAvatar] {
        Dictionary(
            post.acceptedCoauthors.map {
                ($0.user_id, RouteArtAvatar(name: $0.displayName, imageURL: $0.profile_image_url))
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func routeSlide(_ coords: [CLLocationCoordinate2D]) -> some View {
        RouteArtView(
            coordinates: coords,
            routeColor: ActivityCardView.color(post.workout_type),
            companionRoutes: companionRoutes,
            authorAvatar: RouteArtAvatar(name: post.displayName, imageURL: post.profile_image_url),
            companionAvatars: companionRouteAvatars,
            onSnapshot: { routeArtSnapshot = $0 },
            paletteDate: RelativeTime.date(from: post.created_at),
            highlightedRouteId: highlightedRouteId
        )
        .frame(maxWidth: .infinity)
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .overlay {
            if let stats = routeOverlayStats {
                // The overlay lays out at the baked card's 360×450 design
                // size; the slide is the same 4:5, so scaling by width alone
                // reproduces the auto post's look pixel-for-pixel.
                GeometryReader { geo in
                    RouteStatsOverlayView(stats: stats, workoutType: post.workout_type ?? "running")
                        .scaleEffect(geo.size.width / RunStatsCardView.designSize.width,
                                     anchor: .topLeading)
                }
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
        // Same pinch-zoom as the photo slides. The floating copy (canvas +
        // route + stats band) is composed at pinch-begin — nothing big is
        // baked per card up front.
        .instagramZoomable(
            imageProvider: { routeZoomComposite(coords) },
            onDoubleTap: doubleTapHype
        )
    }

    /// The whole crew flies — construction shared with the `?flyover=1` deep
    /// link via `FlyoverLaunch.forPost`; the card only adds the hype wiring
    /// (closures belong to the surface, not the factory).
    private func makeFlyoverLaunch(_ coords: [CLLocationCoordinate2D]) -> FlyoverLaunch? {
        guard var launch = FlyoverLaunch.forPost(post) else { return nil }
        launch.initiallyHyped = post.is_hyped
        launch.onHype = { onHype() }
        return launch
    }

    private var canPlayFlyover: Bool {
        // The raw route, not the slide's: an auto post hides its route slide
        // (the media is already the route) but flies like any other card.
        let hasRoute = (post.routeCoordinates?.count ?? 0) >= 2 || !companionRoutes.isEmpty
        return hasRoute && (isMine || post.flyover_allowed != false)
    }

    /// The route slide's floating zoom copy, on demand. 720×900 keeps the
    /// photo slides' 4:5 so the lift is pixel-identical.
    private func routeZoomComposite(_ coords: [CLLocationCoordinate2D]) -> UIImage? {
        let type = post.workout_type ?? "running"
        let stats = routeOverlayStats
        return RouteArtView.zoomComposite(
            coordinates: coords,
            routeColor: ActivityCardView.color(post.workout_type),
            companionRoutes: companionRoutes,
            authorAvatar: RouteArtAvatar(name: post.displayName, imageURL: post.profile_image_url),
            companionAvatars: companionRouteAvatars,
            underlay: routeArtSnapshot,
            paletteDate: RelativeTime.date(from: post.created_at),
            highlightedRouteId: highlightedRouteId,
            size: CGSize(width: 720, height: 900)
        ) {
            if let stats {
                RouteStatsOverlayView(stats: stats, workoutType: type)
                    .frame(width: RunStatsCardView.designSize.width,
                           height: RunStatsCardView.designSize.height,
                           alignment: .topLeading)
                    .scaleEffect(720 / RunStatsCardView.designSize.width, anchor: .topLeading)
            }
        }
    }

    /// "rob added you to this post" — Accept / Decline, shown only to the
    /// invited coauthor while the invite is pending.
    private var coauthorInviteBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(MADTheme.Colors.madRed)
            Text("\(post.displayName) added you to this post")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(2)
            Spacer()
            Button("Accept") { onRespondCoauthor?(true) }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(MADTheme.Colors.redGradient))
            Button("Decline") { onRespondCoauthor?(false) }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 14) {
                hypeControl
                footerIconButton(
                    icon: "bubble.right",
                    label: commentActionLabel,
                    accessibilityLabel: "Comments",
                    action: { onOpenComments?() }
                )
                .disabled(onOpenComments == nil)
                if isMine || (onShare != nil && post.share_to_feed != false) {
                    footerIconButton(
                        icon: "paperplane",
                        label: nil,
                        accessibilityLabel: "Share",
                        action: sharePostOrRoute
                    )
                }
                Spacer(minLength: 0)
                if let streak = post.stats_snapshot?.streak, streak > 0 {
                    streakChip(streak)
                }
            }
            captionLine
            commentPreview
            if let timestamp = absoluteTimestamp {
                Text(timestamp)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.46))
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel("Posted \(timestamp)")
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    /// Clap + count. The clap hypes — your own post too — and the count opens
    /// who hyped (the old "N hypes" line, folded into the row; each name in
    /// that list opens a profile).
    private var hypeControl: some View {
        HStack(spacing: 4) {
            HypeButton(
                isHyped: post.is_hyped,
                isBusy: isHyping,
                isOutOfHypes: isOutOfHypes && !post.is_hyped,
                style: .compactIcon,
                action: celebrateAndHype
            )
            if let count = post.hype_count, count > 0 {
                Button {
                    onTapHypeCount?()
                } label: {
                    Text("\(count)")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.92))
                        .frame(minHeight: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onTapHypeCount == nil)
                .accessibilityLabel("\(count) hype\(count == 1 ? "" : "s")")
            }
        }
    }

    /// "6 DAY STREAK" — the streak the post was made on, in the app's orange.
    private func streakChip(_ streak: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10, weight: .bold))
            Text("\(streak) DAY STREAK")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .monospacedDigit()
        }
        .foregroundColor(.orange)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.orange.opacity(0.12)))
        .overlay(Capsule().strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
        .fixedSize()
        .accessibilityLabel("\(streak) day streak")
    }

    private var commentActionLabel: String? {
        guard let count = post.comment_count, count > 0 else { return nil }
        return "\(count)"
    }

    /// One Share button with one meaning.
    ///
    /// It used to fork: a route IMAGE on your own post, a LINK on anybody
    /// else's, from the same unlabelled paperplane — a control that does two
    /// different things is one nobody learns. Your own walk now opens the story
    /// studio (every face, Instagram included); somebody else's still shares
    /// the link, because exporting a friend's route hands their loop to the
    /// open web and route art is own-content only.
    private func sharePostOrRoute() {
        guard isMine else {
            onShare?()
            return
        }
        MADHaptics.tap()
        TelemetryService.record(ShareTelemetry.opened)
        storyShare = storyContent()
    }

    /// This card, as a story. The photo is taken from the feed's own cache —
    /// it is the picture already on screen, so it is there — and its absence
    /// simply drops the Photo face rather than blocking the share.
    private func storyContent() -> MADStoryContent {
        let stats = post.stats_snapshot
        let cachedPhoto = (post.storyPhotoURL ?? post.mediaURL)
            .flatMap { FeedImageCache.image(for: $0) }
        return MADStoryContent(
            distanceMiles: stats?.distance,
            paceSecondsPerMile: stats?.pace,
            durationSeconds: stats?.duration,
            streak: stats?.streak,
            activityName: Self.activityNoun(post.workout_type, pace: stats?.pace),
            date: nil,
            dateText: stats?.date,
            coordinates: post.routeCoordinates ?? [],
            routeColor: ActivityCardView.color(post.workout_type),
            photo: cachedPhoto,
            avatar: RouteArtAvatar(name: post.displayName,
                                   imageURL: post.profile_image_url)
        )
    }

    /// Whose words sit under the card: the author's on the author's slides and
    /// the map, and a crew member's own under THEIR slide — Instagram's rule
    /// for a shared carousel. A buddy post is one card with everyone's
    /// picture on it, and the author's caption under a friend's photo reads
    /// as the friend saying it.
    private var currentCaption: (id: String, name: String, username: String?, text: String)? {
        let pages = mediaPages
        if mediaPage < pages.count,
           case .crewPhoto(_, let userId, let name, let username, let caption) = pages[mediaPage] {
            guard let caption, !caption.isEmpty else { return nil }
            return (userId, name, username, caption)
        }
        guard let caption = post.caption, !caption.isEmpty else { return nil }
        return (post.user_id, post.displayName, post.username, caption)
    }

    /// Everyone's words, for the MAP face.
    ///
    /// A photo slide belongs to one person, so it carries one caption — theirs.
    /// The map belongs to the whole walk, and it is the one face where the
    /// author's caption alone reads as the only thing anybody said about it.
    /// So the map shows every caption on the post, author first, each under
    /// its own name — the same rows the photo faces show one at a time.
    private var allCaptions: [(id: String, name: String, username: String?, text: String)] {
        var out: [(id: String, name: String, username: String?, text: String)] = []
        if let caption = post.caption, !caption.isEmpty {
            out.append((post.user_id, post.displayName, post.username, caption))
        }
        for coauthor in post.acceptedCoauthors {
            guard let caption = coauthor.caption, !caption.isEmpty else { continue }
            out.append((coauthor.user_id, coauthor.displayName, coauthor.username, caption))
        }
        return out
    }

    @ViewBuilder
    private var captionLine: some View {
        // The map is the whole walk's face, so it carries the whole walk's
        // words; a photo carries the words of whoever took it.
        // The id is the person whose words these are, never the post's author:
        // a crew caption filed under `post.user_id` gave the author's identity
        // to somebody else's line, so swiping between two captioned slides
        // reused the same row rather than replacing it.
        let rows: [(id: String, name: String, username: String?, text: String)] =
            currentFace == .map
                ? allCaptions
                : currentCaption.map { [$0] } ?? []
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(rows, id: \.id) { row in
                    captionRow(name: row.name, username: row.username, text: row.text)
                }
            }
            .padding(.top, 1)
        }
    }

    /// A name and the words after it, as ONE flowing line — the name a link to
    /// that person's profile, the @mentions inside the words links to theirs.
    ///
    /// The name used to be a plain `Text` beside the caption, so the most
    /// prominent name on the card was the one thing on it that didn't open
    /// anybody. Both are links in a single `Text` rather than Buttons, which is
    /// what lets a comment-preview row stay one tap target for the thread while
    /// the name inside it still reaches the profile.
    private func captionRow(name: String, username: String?, text: String) -> some View {
        var line = MentionText.nameLink(name, username: username)
        line += AttributedString(" ")
        line += MentionText.attributed(text)
        return Text(line)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundColor(.white.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Profile links route in-app — the scheme is ours alone, so a tap
            // is consumed here whether or not this surface routes profiles;
            // handing `mad-mention://` to the system would open nothing.
            .environment(\.openURL, OpenURLAction { url in
                if let username = MentionText.username(from: url) {
                    onTapMention?(username)
                    return .handled
                }
                return .systemAction
            })
    }

    /// The last two comments, under the caption — Instagram's rule.
    ///
    /// A conversation nobody sees until they tap through is happening in a
    /// room off the side of the feed. Two lines is enough to show that people
    /// are talking without turning a card into a thread, and the "View all N"
    /// link above them (only once there are more than two) is the way in.
    ///
    /// The block opens comments, including the comment lines themselves —
    /// tapping a comment wants the comment. The commenter's NAME is the one
    /// exception, and it is a link rather than a nested Button precisely so it
    /// can be: it reaches their profile while the rest of the row still opens
    /// the thread, which is Instagram's split.
    @ViewBuilder
    private var commentPreview: some View {
        let preview = post.comment_preview ?? []
        if !preview.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                if let count = post.comment_count, count > preview.count {
                    Button {
                        onOpenComments?()
                    } label: {
                        Text("View all \(count) comments")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(onOpenComments == nil)
                }
                ForEach(preview) { comment in
                    Button {
                        onOpenComments?()
                    } label: {
                        captionRow(name: comment.displayName,
                                   username: comment.username,
                                   text: comment.content)
                    }
                    .buttonStyle(.plain)
                    .disabled(onOpenComments == nil)
                }
            }
            .padding(.top, 1)
        }
    }

    private func footerIconButton(
        icon: String,
        label: String?,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                if let label {
                    Text(label)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                }
            }
            .foregroundColor(.white.opacity(0.92))
            .frame(minWidth: 36, minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var absoluteTimestamp: String? {
        guard let date = RelativeTime.date(from: post.created_at) else { return nil }
        let thisYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        return (thisYear ? Self.timestampFormatter : Self.timestampWithYearFormatter).string(from: date)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d · h:mm a"
        return formatter
    }()

    private static let timestampWithYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy · h:mm a"
        return formatter
    }()
}

/// One 4:5 media slide with cached loading and Instagram pinch-zoom. The
/// loaded UIImage feeds the zoom overlay so the floating copy is pixel-
/// identical to what's in the card.
struct ZoomablePhotoSlide: View {
    let url: URL?
    var badge: (text: String, icon: String)? = nil
    var onDoubleTap: (() -> Void)? = nil

    @State private var loadedImage: UIImage?

    var body: some View {
        FeedImageView(url: url, loadedImage: $loadedImage)
            .frame(maxWidth: .infinity)
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
            .instagramZoomable(image: loadedImage, onDoubleTap: onDoubleTap)
            .overlay(alignment: .topLeading) {
                if let badge {
                    HStack(spacing: 5) {
                        Image(systemName: badge.icon)
                            .font(.system(size: 11, weight: .bold))
                        Text(badge.text)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .padding(10)
                    .allowsHitTesting(false)
                }
            }
    }
}

/// Everyone on a buddy walk's post, as a list — the author first, then the
/// crew in the order they were credited (the same order the route colours
/// and the photo slides use). Tapping a row hands that person back to the
/// host, which owns profile navigation; the sheet never presents one itself.
struct PostCrewSheet: View {
    let post: PostItem
    /// Called with the tapped crew member, or nil for the author.
    let onSelect: (PostCoauthorItem?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: MADTheme.Spacing.sm) {
                        row(
                            name: post.displayName,
                            imageURL: post.profile_image_url,
                            role: "Posted this",
                            hasPhoto: true
                        ) { onSelect(nil) }
                        ForEach(post.acceptedCoauthors) { member in
                            row(
                                name: member.displayName,
                                imageURL: member.profile_image_url,
                                role: member.mediaURL != nil ? "Added a photo" : "On the walk",
                                hasPhoto: member.mediaURL != nil
                            ) { onSelect(member) }
                        }
                    }
                    .padding(MADTheme.Spacing.md)
                }
            }
            .navigationTitle("\(post.acceptedCoauthors.count + 1) on this walk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(
        name: String,
        imageURL: String?,
        role: String,
        hasPhoto: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            MADHaptics.tap()
            action()
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                AvatarView(name: name, imageURL: imageURL, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(MADTheme.Typography.smallBold)
                        .foregroundStyle(MADTheme.Colors.madWhite)
                        .lineLimit(1)
                    Text(role)
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.55))
                }
                Spacer(minLength: MADTheme.Spacing.xs)
                if hasPhoto {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.45))
                        .accessibilityHidden(true)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.35))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .fill(MADTheme.Colors.madWhite.opacity(0.08))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
