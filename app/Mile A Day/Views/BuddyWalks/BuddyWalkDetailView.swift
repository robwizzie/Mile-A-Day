import SwiftUI
import CoreLocation

/// One past buddy walk, whole.
///
/// The shared post exactly as the feed shows it — every crew member's photo
/// in the carousel, the map with everyone's line behind the PHOTO | MAP
/// toggle, the flyover, hypes and comments — or, for a walk nobody posted,
/// the routes themselves; then the crew's standings and the walk's facts.
/// The history's cards and the Walks Together tiles both open THIS, so a tap
/// on a photo and a tap on the details can never land in two different
/// places again.
///
/// Presented as a sheet; carries its own NavigationStack.
struct BuddyWalkDetailView: View {
    let walk: BuddyWalkRecord
    /// "Walk again" hand-off, when the host has one (the history screen
    /// does). Hidden otherwise.
    var onWalkAgain: ((String?) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var buddy = BuddySessionService.shared
    /// One stable service for profiles opened from here and for route reads.
    @StateObject private var friendService = FriendService()

    // The post, when the walk has one the viewer may see.
    @State private var post: PostItem?
    @State private var isLoadingPost = false
    @State private var postUnavailable = false
    @State private var isHyping = false
    @State private var commentsPost: PostItem?
    @State private var hypersContext: HypersListContext?
    @State private var pendingProfileUser: BackendUser?
    @State private var profileUser: BackendUser?
    @State private var sharingURL: ShareURL?
    @State private var reportingPost: PostItem?

    // Routes fetched per participant when there is no post to carry them.
    @State private var routes: [String: [CLLocationCoordinate2D]] = [:]
    @State private var isLoadingRoutes = false
    @State private var routeArtSnapshot: RouteMapSnapshot?
    @State private var flyoverLaunch: FlyoverLaunch?

    @State private var showRecap = false

    private var viewerId: String? { buddy.currentUserId }
    private var currentUserId: String? { UserDefaults.standard.string(forKey: "backendUserId") }
    private var accent: Color { walk.accentColor }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: MADTheme.Spacing.md) {
                        headline
                        mediaSection
                        crewCard
                        factsCard
                        if walk.postId == nil {
                            recapRow
                        }
                        if let onWalkAgain {
                            walkAgainButton(onWalkAgain)
                        }
                    }
                    .padding(.horizontal, MADTheme.Spacing.screenGutter)
                    .padding(.top, MADTheme.Spacing.sm)
                    .padding(.bottom, MADTheme.Spacing.xl)
                }
            }
            .navigationTitle(walk.dayText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
            }
            .task { await load() }
            .fullScreenCover(item: $flyoverLaunch) { launch in
                RouteFlyoverPlayerView(launch: launch)
            }
            // Every sheet on its own node — two on one node and SwiftUI
            // silently drops one (ios.md).
            .background(
                Color.clear.sheet(isPresented: $showRecap) {
                    BuddyRecapView(sessionId: walk.id)
                }
            )
            .background(
                Color.clear.sheet(item: $commentsPost) { target in
                    // Coauthors moderate too: a collab reads is_self == false for
                    // them, but the server allows their deletes.
                    CommentsSheet(
                        post: target,
                        canModerate: target.is_self
                            || (target.coauthor_status == "accepted"
                                && target.coauthor_user_id == currentUserId)
                    ) { newCount in
                        post?.comment_count = newCount
                    }
                }
            )
            .background(
                Color.clear.sheet(item: $hypersContext, onDismiss: {
                    if let pending = pendingProfileUser {
                        pendingProfileUser = nil
                        profileUser = pending
                    }
                }) { context in
                    HypersListSheet(context: context) { hyper in
                        guard hyper.user_id != currentUserId else { return }
                        pendingProfileUser = BackendUser(
                            user_id: hyper.user_id, username: hyper.username, email: nil,
                            first_name: hyper.first_name, last_name: hyper.last_name,
                            bio: nil, profile_image_url: hyper.profile_image_url,
                            apple_id: nil, auth_provider: nil, role: nil
                        )
                    }
                }
            )
            .background(
                Color.clear.sheet(item: $profileUser) { user in
                    NavigationStack {
                        UserProfileDetailView(user: user, friendService: friendService)
                    }
                }
            )
            .background(
                Color.clear.sheet(item: $sharingURL) { share in
                    ShareLinkSheet(url: share.url)
                }
            )
            .background(
                Color.clear.sheet(item: $reportingPost) { target in
                    ReportPostSheet(postId: target.post_id) { reportingPost = nil }
                }
            )
        }
    }

    // MARK: - Headline

    /// Who, how far together, what kind of walk.
    private var headline: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            crewAvatars

            VStack(alignment: .leading, spacing: 3) {
                Text(walk.crewText(excluding: viewerId))
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(MADTheme.Colors.madWhite)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 5) {
                    Image(systemName: walk.mode.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(accent)
                    Text("\(walk.groupDistanceMiles.milesText) mi together · \(walk.durationText)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    /// Everyone's face, overlapped — the viewer first.
    private var crewAvatars: some View {
        let ordered = walk.participants.sorted { a, _ in a.userId == viewerId }
        let shown = Array(ordered.prefix(3))
        return HStack(spacing: -12) {
            ForEach(shown) { person in
                AvatarView(name: person.displayName, imageURL: person.profileImageUrl, size: 44)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.7), lineWidth: 2))
            }
        }
        .padding(.trailing, 4)
    }

    // MARK: - Media

    /// The post as the feed draws it; the routes alone when there is no post.
    @ViewBuilder
    private var mediaSection: some View {
        if let post {
            PostCardView(
                post: post,
                storyPhotoURL: post.storyPhotoURL,
                isHyping: isHyping,
                onHype: { Task { await hype(post) } },
                onReport: { reportingPost = post },
                onBlock: { Task { await block(post) } },
                onDelete: { Task { await delete(post) } },
                onEditCaption: nil,
                onTapAuthor: post.is_self ? nil : { open(userId: post.user_id, username: post.username,
                                                       first: post.first_name, last: post.last_name,
                                                       image: post.profile_image_url) },
                onTapCoauthor: (post.hasAcceptedCoauthor && post.coauthor_user_id != currentUserId)
                    ? { open(userId: post.coauthor_user_id ?? "", username: post.coauthor_username,
                             first: post.coauthor_first_name, last: post.coauthor_last_name,
                             image: post.coauthor_profile_image_url) }
                    : nil,
                onTapMention: { username in openMention(username) },
                onTapHypeCount: {
                    hypersContext = HypersListContext(
                        contextType: "post", contextId: post.post_id, targetUserId: post.user_id)
                },
                onOpenComments: { commentsPost = post },
                onShare: { sharingURL = ShareURL(url: PostShareLink.url(for: post.post_id)) }
            )
        } else if isLoadingPost {
            loadingCard
        } else if walk.postId != nil, postUnavailable {
            noticeCard(icon: "eye.slash", text: "This walk's post isn't available any more.")
        } else {
            routesCard
        }
    }

    private var loadingCard: some View {
        ProgressView()
            .tint(MADTheme.Colors.madWhite)
            .frame(maxWidth: .infinity)
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .profileCard()
    }

    private func noticeCard(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.4))
            Text(text)
                .font(MADTheme.Typography.caption)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(MADTheme.Spacing.md)
        .profileCard()
    }

    // MARK: Routes (walks nobody posted)

    /// Participants whose trace the viewer may draw.
    private var routeParticipants: [BuddyWalkParticipant] {
        walk.participants.filter { $0.hasRoute == true && $0.workoutId != nil }
    }

    /// The line drawn in the walk's own colour: the viewer's, when they have
    /// one, else whoever is first.
    private var leadParticipant: BuddyWalkParticipant? {
        routeParticipants.first { $0.userId == viewerId } ?? routeParticipants.first
    }

    private var companionParticipants: [BuddyWalkParticipant] {
        routeParticipants.filter { $0.userId != leadParticipant?.userId }
    }

    /// Colours assigned across the whole crew, then looked up — the same rule
    /// the feed's legend keeps (never colour a filtered list).
    private var companionColors: [Color] {
        CrewRoutePalette.companionColors(count: companionParticipants.count, avoiding: accent)
    }

    private var companionRoutes: [CompanionRoute] {
        companionParticipants.enumerated().compactMap { pair in
            guard let coords = routes[pair.element.userId], coords.count >= 2 else { return nil }
            return CompanionRoute(id: pair.element.userId, coordinates: coords, color: companionColors[pair.offset])
        }
    }

    private var leadCoordinates: [CLLocationCoordinate2D] {
        guard let lead = leadParticipant else { return [] }
        return routes[lead.userId] ?? []
    }

    private var hasDrawableRoute: Bool {
        leadCoordinates.count >= 2 || !companionRoutes.isEmpty
    }

    @ViewBuilder
    private var routesCard: some View {
        if !routeParticipants.isEmpty {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                ProfileCardLabel(text: routeParticipants.count > 1 ? "THE ROUTES" : "THE ROUTE")

                ZStack(alignment: .topLeading) {
                    if hasDrawableRoute, let lead = leadParticipant {
                        RouteArtView(
                            coordinates: leadCoordinates,
                            routeColor: accent,
                            companionRoutes: companionRoutes,
                            authorAvatar: RouteArtAvatar(name: lead.displayName, imageURL: lead.profileImageUrl),
                            companionAvatars: Dictionary(
                                companionParticipants.map {
                                    ($0.userId, RouteArtAvatar(name: $0.displayName, imageURL: $0.profileImageUrl))
                                },
                                uniquingKeysWith: { first, _ in first }
                            ),
                            onSnapshot: { routeArtSnapshot = $0 },
                            paletteDate: walk.startedAtDate
                        )
                        .frame(maxWidth: .infinity)
                        .aspectRatio(4.0 / 5.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))

                        flyoverChip.padding(10)
                    } else {
                        ZStack {
                            Color.white.opacity(0.04)
                            if isLoadingRoutes {
                                ProgressView().tint(MADTheme.Colors.madWhite)
                            } else {
                                Text("Couldn't load the route")
                                    .font(MADTheme.Typography.caption)
                                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.5))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .aspectRatio(4.0 / 5.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
                    }
                }

                if routeParticipants.count > 1 {
                    routeLegend
                }
            }
            .padding(MADTheme.Spacing.md)
            .profileCard()
        } else if walk.photos.isEmpty {
            noticeCard(icon: "map", text: "No route or photos were shared from this walk.")
        }
    }

    /// Names to colours — the whole point of a map with several lines on it.
    private var routeLegend: some View {
        FlowLayout(spacing: 8) {
            if let lead = leadParticipant {
                legendChip(name: lead.userId == viewerId ? "You" : lead.displayName, color: accent)
            }
            ForEach(Array(companionParticipants.enumerated()), id: \.element.id) { index, person in
                legendChip(name: person.userId == viewerId ? "You" : person.displayName,
                           color: companionColors[index])
            }
        }
    }

    private func legendChip(name: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 14, height: 4)
            Text(name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.8))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }

    /// ▶ FLYOVER over the routes — the shared chip.
    private var flyoverChip: some View {
        FlyoverChipButton(accent: accent) {
            flyoverLaunch = makeFlyoverLaunch()
        }
    }

    /// The whole crew flies. Same construction shape as `FlyoverLaunch.forPost`,
    /// built from the walk's own rows because there is no post to build it from.
    private func makeFlyoverLaunch() -> FlyoverLaunch? {
        guard let lead = leadParticipant else { return nil }
        let companions: [FlyoverCompanion] = companionParticipants.enumerated().compactMap { pair in
            guard let coords = routes[pair.element.userId], coords.count >= 2 else { return nil }
            return FlyoverCompanion(
                id: pair.element.userId,
                coordinates: coords,
                color: companionColors[pair.offset],
                avatar: RouteArtAvatar(name: pair.element.displayName, imageURL: pair.element.profileImageUrl)
            )
        }
        let coords = leadCoordinates
        guard coords.count >= 2 || !companions.isEmpty else { return nil }
        let pace: Double? = (lead.distanceMiles > 0 && lead.durationSeconds > 0)
            ? Double(lead.durationSeconds) / lead.distanceMiles : nil
        return FlyoverLaunch(
            coordinates: coords,
            workoutType: walk.activityType,
            stats: PostStats(
                distance: lead.distanceMiles > 0 ? lead.distanceMiles : nil,
                pace: pace,
                duration: lead.durationSeconds > 0 ? Double(lead.durationSeconds) : nil,
                streak: nil, date: nil, calories: nil, steps: nil
            ),
            author: RouteArtAvatar(name: lead.displayName, imageURL: lead.profileImageUrl),
            companions: companions,
            officialDistanceMiles: lead.distanceMiles > 0 ? lead.distanceMiles : nil
        )
    }

    // MARK: - Crew

    /// Everyone on the walk with what they did: place (competitive modes),
    /// distance, time and pace, and — the honest version of the recap's
    /// "syncing" — whether that number is a synced workout or the live figure.
    private var crewCard: some View {
        let ranked = walk.participants.sorted { a, b in
            if let pa = a.place, let pb = b.place, pa != pb { return pa < pb }
            return a.distanceMiles > b.distanceMiles
        }
        let showsPlaces = !walk.mode.isCooperative
        return VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            HStack {
                ProfileCardLabel(text: "THE CREW")
                Spacer()
                Text("\(walk.participants.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            VStack(spacing: 0) {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, person in
                    crewRow(person, showsPlace: showsPlaces)
                    if index < ranked.count - 1 {
                        Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 56)
                    }
                }
            }
        }
        .padding(MADTheme.Spacing.md)
        .profileCard()
    }

    private func crewRow(_ person: BuddyWalkParticipant, showsPlace: Bool) -> some View {
        let isYou = person.userId == viewerId
        let isWinner = showsPlace && person.place == 1
        let pace: String? = (person.distanceMiles > 0 && person.durationSeconds > 0)
            ? "\(RunStatsStickerView.paceText(Double(person.durationSeconds) / person.distanceMiles)) /mi"
            : nil
        var detail: [String] = []
        if person.durationSeconds > 0 { detail.append(RunStatsStickerView.durationText(Double(person.durationSeconds))) }
        if let pace { detail.append(pace) }

        return Button {
            guard !isYou, person.isNamed else { return }
            open(userId: person.userId, username: person.username, first: person.firstName,
                 last: nil, image: person.profileImageUrl)
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                if showsPlace, let place = person.place {
                    Group {
                        if place == 1 {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.yellow)
                        } else {
                            Text("\(place)")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.5))
                        }
                    }
                    .frame(width: 22)
                }

                AvatarView(name: person.displayName, imageURL: person.profileImageUrl, size: 40)
                    .overlay(Circle().strokeBorder(isYou ? accent : .clear, lineWidth: 2))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(isYou ? "You" : person.displayName)
                            .font(MADTheme.Typography.bodyBold)
                            .foregroundStyle(MADTheme.Colors.madWhite)
                            .lineLimit(1)
                        if person.isHost {
                            Text("HOST")
                                .font(.system(size: 8, weight: .black, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.1)))
                        }
                    }
                    if !detail.isEmpty {
                        Text(detail.joined(separator: " · "))
                            .font(MADTheme.Typography.caption)
                            .monospacedDigit()
                            .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.55))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: MADTheme.Spacing.sm)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(person.distanceMiles.milesText) mi")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isWinner || isYou ? accent : MADTheme.Colors.madWhite.opacity(0.85))
                    if !person.isSynced {
                        // The number is the walk's live figure, not a synced
                        // workout — said plainly, and never as a spinner.
                        Text("not synced")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.4))
                    }
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Facts

    /// When, how long, what for.
    private var factsCard: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            ProfileCardLabel(text: "THE WALK")
            VStack(spacing: 8) {
                if let date = walk.date {
                    factRow("Date", date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                }
                if let start = walk.startedAtDate, let end = walk.endedAtDate {
                    factRow("Time", "\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))")
                }
                factRow("Length", walk.durationText)
                factRow("Together", "\(walk.groupDistanceMiles.milesText) mi")
                if let goal = walk.goalValue, goal > 0 {
                    let hit = walk.groupDistanceMiles >= goal
                    factRow("Goal", "\(goal.milesText) mi\(hit ? " · hit" : "")")
                }
                if !walk.mode.isCooperative, let winner = walk.winnerUserId {
                    let name = winner == viewerId
                        ? "You"
                        : (walk.participants.first { $0.userId == winner }?.displayName ?? "A friend")
                    factRow("Winner", name)
                }
            }
        }
        .padding(MADTheme.Spacing.md)
        .profileCard()
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(MADTheme.Typography.caption)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.5))
            Spacer(minLength: MADTheme.Spacing.sm)
            Text(value)
                .font(MADTheme.Typography.smallBold)
                .monospacedDigit()
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.9))
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Actions

    /// A walk nobody posted: the recap is where posting it lives, and it
    /// still says what's missing when the window has closed.
    private var recapRow: some View {
        Button {
            MADHaptics.tap()
            showRecap = true
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(accent.opacity(0.16)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recap & post this walk")
                        .font(MADTheme.Typography.smallBold)
                        .foregroundStyle(MADTheme.Colors.madWhite)
                    Text("Standings and the share flow, as on the day")
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.55))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.35))
            }
            .padding(MADTheme.Spacing.md)
            .profileCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func walkAgainButton(_ handler: @escaping (String?) -> Void) -> some View {
        let partner = walk.others(excluding: viewerId).first
        return Button {
            MADHaptics.action()
            dismiss()
            // The host's hand-off dismisses its own sheet and presents the
            // start flow; give this sheet its beat first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                handler(partner?.userId)
            }
        } label: {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "figure.2")
                    .font(.system(size: 15, weight: .semibold))
                Text(partner.map { "Walk with \($0.displayName) again" } ?? "Start a buddy walk")
                    .font(MADTheme.Typography.bodyBold)
            }
            .foregroundStyle(MADTheme.Colors.madWhite)
            .frame(maxWidth: .infinity)
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .fill(accent)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading

    private func load() async {
        if let postId = walk.postId {
            await loadPost(postId)
        } else {
            await loadRoutes()
        }
    }

    private func loadPost(_ postId: String) async {
        guard post == nil, !isLoadingPost else { return }
        isLoadingPost = true
        defer { isLoadingPost = false }
        do {
            let entry = try await PostService.fetchPost(postId: postId)
            if let item = entry.asPostItem() {
                post = item
            } else {
                postUnavailable = true
            }
        } catch {
            print("[BuddyWalkDetail] post load failed: \(error)")
            postUnavailable = true
        }
        // The post carries everyone's line; only a walk without one needs the
        // per-workout route reads.
        if post == nil { await loadRoutes() }
    }

    /// One route read per participant with a trace, in parallel. Each is
    /// consent-gated server-side exactly like a friend's workout detail.
    private func loadRoutes() async {
        let targets = routeParticipants.filter { routes[$0.userId] == nil }
        guard !targets.isEmpty else { return }
        isLoadingRoutes = true
        defer { isLoadingRoutes = false }
        let service = friendService
        let loaded: [(String, [CLLocationCoordinate2D])] = await withTaskGroup(
            of: (String, [CLLocationCoordinate2D])?.self
        ) { group in
            for person in targets {
                guard let workoutId = person.workoutId else { continue }
                let userId = person.userId
                group.addTask {
                    let raw = try? await service.fetchWorkoutRoute(for: userId, workoutId: workoutId)
                    guard let coords = decodeRouteCoordinates(raw), coords.count >= 2 else { return nil }
                    return (userId, coords)
                }
            }
            var out: [(String, [CLLocationCoordinate2D])] = []
            for await result in group {
                if let result { out.append(result) }
            }
            return out
        }
        for (userId, coords) in loaded {
            routes[userId] = coords
        }
    }

    // MARK: - Post actions

    private func open(userId: String, username: String?, first: String?, last: String?, image: String?) {
        guard !userId.isEmpty, userId != currentUserId else { return }
        profileUser = BackendUser(
            user_id: userId, username: username, email: nil,
            first_name: first, last_name: last, bio: nil,
            profile_image_url: image, apple_id: nil, auth_provider: nil, role: nil
        )
    }

    private func openMention(_ username: String) {
        let lowered = username.lowercased()
        Task {
            guard let match = try? await friendService.searchUsers(byUsername: lowered)
                .first(where: { $0.username?.lowercased() == lowered }) else { return }
            await MainActor.run {
                guard match.user_id != currentUserId else { return }
                profileUser = match
            }
        }
    }

    /// Same optimistic toggle as PostDetailView, for the one post here.
    private func hype(_ target: PostItem) async {
        guard !isHyping else { return }
        let context = HypeContext(
            contextType: "post",
            contextId: target.post_id,
            contextLabel: target.caption ?? target.displayName
        )
        await MainActor.run { isHyping = true }
        defer { Task { @MainActor in isHyping = false } }

        if target.is_hyped {
            await MainActor.run {
                post?.is_hyped = false
                post?.hype_count = max(0, (post?.hype_count ?? 1) - 1)
            }
            do {
                _ = try await HypeService.removeHype(targetUserId: target.user_id, context: context)
                await MainActor.run { MADHaptics.tap() }
            } catch {
                await MainActor.run {
                    post?.is_hyped = true
                    post?.hype_count = (post?.hype_count ?? 0) + 1
                }
            }
            return
        }

        await MainActor.run {
            post?.is_hyped = true
            post?.hype_count = (post?.hype_count ?? 0) + 1
        }
        do {
            _ = try await HypeService.sendHype(targetUserId: target.user_id, context: context)
            await MainActor.run { MADHaptics.success() }
        } catch APIError.conflict {
            // Already hyped server-side — keep the optimistic state.
        } catch {
            await MainActor.run {
                post?.is_hyped = false
                post?.hype_count = max(0, (post?.hype_count ?? 1) - 1)
            }
        }
    }

    private func block(_ target: PostItem) async {
        guard !target.is_self else { return }
        try? await BlockService.block(userId: target.user_id)
        await MainActor.run { dismiss() }
    }

    private func delete(_ target: PostItem) async {
        guard target.is_self else { return }
        try? await PostService.deletePost(postId: target.post_id)
        await MainActor.run { post = nil }
    }
}
