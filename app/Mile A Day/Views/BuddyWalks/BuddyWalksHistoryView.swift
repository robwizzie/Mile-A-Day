import SwiftUI

/// Every buddy walk and run you've taken, as a scrapbook.
///
/// Until this screen a shared walk left almost no trace: the recap was
/// reachable for a few minutes from the dashboard and then gone, the photos
/// scrolled away down the feed, and the only surviving record was a "12 walks ·
/// 14.2 mi" line inside the sheet you use to START one. So the thing the
/// feature is actually for — the accumulating history with one person — was the
/// thing you could not look at.
///
/// The screen is deliberately built around the PHOTOS. A list of distances is a
/// log; the picture from the top of the hill is the reason anyone opens a
/// history at all, and it's what makes the next walk get scheduled. Every walk
/// is one tap from its full recap, and every partner is one tap from walking
/// with them again — that last part is the point of the whole screen, not a
/// footer on it.
///
/// Presented modally (it carries its own NavigationStack) from the profile, the
/// buddy start sheet, a friend's profile, and the post-walk recap.
struct BuddyWalksHistoryView: View {
    /// Open already narrowed to one person — the friend-profile entry point.
    /// The rail below still lets the viewer widen it back out.
    var friendId: String?
    var friendName: String?
    /// Where "walk again" should go, when the host can do something better
    /// than the default hand-off. The start sheet passes one so the CTA simply
    /// ticks the friend on the form the user is already filling in — asking the
    /// Dashboard to present a start sheet while one is already up drops the
    /// presentation and the button reads as dead.
    var onWalkAgain: ((String?) -> Void)?

    /// Explicit because the filter has to START on `friendId`. Seeding it from
    /// a `.task` instead means the first load runs unfiltered and is then
    /// thrown away — two round trips, and everyone's walks flash under a
    /// "You and Sam" headline in between.
    init(
        friendId: String? = nil,
        friendName: String? = nil,
        onWalkAgain: ((String?) -> Void)? = nil
    ) {
        self.friendId = friendId
        self.friendName = friendName
        self.onWalkAgain = onWalkAgain
        _filterUserId = State(initialValue: friendId)
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var buddy = BuddySessionService.shared

    @State private var walks: [BuddyWalkRecord] = []
    @State private var totals: BuddyHistoryTotals?
    @State private var nextBefore: String?
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var loadFailed = false

    /// Which partner the list is narrowed to, nil for everyone. Drives
    /// `.task(id:)`, so changing it IS the reload.
    @State private var filterUserId: String?

    @State private var recapSessionId: String?
    @State private var photoPostId: String?

    private var viewerId: String? { buddy.currentUserId }

    /// The person the list is currently about, when it's about one person.
    private var focusedPartner: BuddyPartner? {
        guard let filterUserId else { return nil }
        return buddy.partners.first { $0.userId == filterUserId }
    }

    /// Nil whenever the list is about EVERYONE — every "with <name>" string on
    /// the screen keys off this, so a fallback that leaked a name while
    /// unfiltered would relabel the whole archive after one friend's walk.
    private var focusedName: String? {
        guard let filterUserId else { return nil }
        if let partner = focusedPartner { return partner.displayName }
        if filterUserId == friendId, let friendName, !friendName.isEmpty {
            return friendName
        }
        // Opened from a friend's profile before the partner list has landed:
        // the walks themselves already name them.
        return walks.first?.others(excluding: viewerId).first?.displayName
    }

    /// Runs red, walks blue — but a history spans both, so the screen's accent
    /// follows whatever the most recent walk was rather than picking one.
    private var accent: Color {
        walks.first?.accentColor ?? MADTheme.workoutColor("walking")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
                content
            }
            .navigationTitle("Walks Together")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: filterUserId) { await reload() }
        .task {
            // The rail is built from the partner list, which the start sheet
            // and dashboard also warm. Refreshing is cheap and means this
            // screen works as a first stop on a cold launch.
            await buddy.loadPartners()
        }
        .sheet(
            isPresented: Binding(
                get: { recapSessionId != nil },
                set: { if !$0 { recapSessionId = nil } }
            )
        ) {
            if let recapSessionId {
                BuddyRecapView(sessionId: recapSessionId)
            }
        }
        // Attached to a DIFFERENT node than the recap sheet: two `.sheet`
        // modifiers on one node makes SwiftUI silently drop one (ios.md).
        .background(
            Color.clear.sheet(
                isPresented: Binding(
                    get: { photoPostId != nil },
                    set: { if !$0 { photoPostId = nil } }
                )
            ) {
                if let photoPostId {
                    PostDetailLoaderView(postId: photoPostId)
                }
            }
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && walks.isEmpty {
            ProgressView().tint(MADTheme.Colors.madWhite)
        } else {
            ScrollView {
                LazyVStack(spacing: MADTheme.Spacing.lg) {
                    header
                    partnerRail
                    if walks.isEmpty {
                        emptyState
                    } else {
                        timeline
                        walkAgainCTA
                    }
                    Color.clear.frame(height: MADTheme.Spacing.lg)
                }
                .padding(.horizontal, MADTheme.Spacing.screenGutter)
                .padding(.top, MADTheme.Spacing.sm)
            }
            .refreshable { await reload() }
        }
    }

    // MARK: - Header

    /// The number that makes a shared habit feel like a thing you HAVE.
    ///
    /// Miles are the viewer's own across those walks, matching the partner
    /// list — a pooled figure double-counts the same walk from each side, so
    /// two people would see different numbers for the same history.
    private var header: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            crestRow

            // A hero "0.00 mi" over an empty archive is a scoreboard telling
            // someone they've done nothing. With no walks yet the crest and the
            // line below carry it, and the pitch does the rest.
            if hasWalks {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text((totals?.miles ?? 0).milesText)
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(MADTheme.Colors.madWhite)
                    Text("mi")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.55))
                }
            }

            Text(headlineSubtitle)
                .font(MADTheme.Typography.subheadline)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.65))
                .multilineTextAlignment(.center)

            if let since = sinceText {
                Text(since)
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.lg)
        .padding(.horizontal, MADTheme.Spacing.md)
        .madLiquidGlass(cornerRadius: MADTheme.CornerRadius.extraLarge)
    }

    /// Faces when the history is about someone, an icon when it's about
    /// everyone. Either way it's the same 76pt crest the recap and start sheet
    /// use, so the three read as one family.
    @ViewBuilder
    private var crestRow: some View {
        if let partner = focusedPartner {
            AvatarView(
                name: partner.displayName,
                imageURL: partner.profileImageUrl,
                size: 76
            )
            .overlay(Circle().strokeBorder(accent.opacity(0.5), lineWidth: 2))
        } else {
            ZStack {
                Circle().fill(accent.opacity(0.18)).frame(width: 76, height: 76)
                Circle()
                    .strokeBorder(accent.opacity(0.45), lineWidth: 1.5)
                    .frame(width: 76, height: 76)
                Image(systemName: "figure.2")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(accent)
            }
        }
    }

    private var hasWalks: Bool { (totals?.walks ?? walks.count) > 0 }

    private var headlineSubtitle: String {
        let walkCount = totals?.walks ?? walks.count
        guard walkCount > 0 else {
            return focusedName.map { "You haven't walked with \($0) yet" }
                ?? "No walks together yet"
        }
        let walkWord = walkCount == 1 ? "walk" : "walks"
        if let name = focusedName {
            return "across \(walkCount) \(walkWord) with \(name)"
        }
        let partnerCount = totals?.partners ?? 0
        let peopleWord = partnerCount == 1 ? "person" : "people"
        return partnerCount > 0
            ? "across \(walkCount) \(walkWord) with \(partnerCount) \(peopleWord)"
            : "across \(walkCount) \(walkWord)"
    }

    /// "Since June 2026". Only once there's enough history for it to mean
    /// something — "Since today" on a first walk is noise.
    private var sinceText: String? {
        guard let raw = totals?.firstWalkDate,
              (totals?.walks ?? 0) > 1,
              let date = Self.dayFormatter.date(from: raw)
        else { return nil }
        return "Since \(date.formatted(.dateTime.month(.wide).year()))"
    }

    /// Parsed in the device's zone and rendered in the device's zone — see
    /// `BuddyWalkRecord.date` for why mixing the two shifts every label a day.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // MARK: - Partner rail

    /// Who you walk with, as a filter. Hidden with fewer than two partners —
    /// a one-chip filter row is a control that can't do anything.
    @ViewBuilder
    private var partnerRail: some View {
        if buddy.partners.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    railChip(
                        title: "Everyone",
                        subtitle: nil,
                        imageURL: nil,
                        isActive: filterUserId == nil
                    ) { setFilter(nil) }

                    ForEach(buddy.partners) { partner in
                        railChip(
                            title: partner.displayName,
                            subtitle: "\(partner.walks)",
                            imageURL: partner.profileImageUrl,
                            isActive: filterUserId == partner.userId
                        ) { setFilter(partner.userId) }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            // The rail scrolls sideways inside a vertical ScrollView, so it
            // must not be able to widen the page — a chip carrying a name is
            // DATA, and a `.fixedSize` on one publishes a minimum width no
            // ancestor can shrink (ios.md).
            .frame(maxWidth: .infinity)
        }
    }

    private func railChip(
        title: String,
        subtitle: String?,
        imageURL: String?,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            MADHaptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if let imageURL {
                    AvatarView(name: title, imageURL: imageURL, size: 26)
                } else {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            isActive ? MADTheme.Colors.madWhite
                                : MADTheme.Colors.madWhite.opacity(0.6))
                }
                Text(title)
                    .font(MADTheme.Typography.smallBold)
                    .foregroundStyle(
                        isActive
                            ? MADTheme.Colors.madWhite
                            : MADTheme.Colors.madWhite.opacity(0.7)
                    )
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(MADTheme.Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.45))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(
                        isActive
                            ? accent.opacity(0.28)
                            : MADTheme.Colors.madWhite.opacity(0.07))
            )
            .overlay(
                Capsule().strokeBorder(
                    isActive ? accent.opacity(0.7) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func setFilter(_ userId: String?) {
        guard filterUserId != userId else { return }
        // Cleared here rather than in `reload`, so the old person's walks can't
        // sit under the new person's headline for a round trip.
        walks = []
        totals = nil
        nextBefore = nil
        isLoading = true
        filterUserId = userId
    }

    // MARK: - Timeline

    /// Walks under month headers. Grouping is done by walking the (already
    /// sorted) list rather than with `Dictionary(grouping:)`, which loses the
    /// order the server sorted them into.
    private var monthSections: [MonthSection] {
        var sections: [MonthSection] = []
        for walk in walks {
            let key = walk.monthKey
            if sections.last?.month == key {
                sections[sections.count - 1].walks.append(walk)
            } else {
                sections.append(MonthSection(month: key, walks: [walk]))
            }
        }
        return sections
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
            ForEach(monthSections) { section in
                VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                    Text(section.month)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.4))

                    ForEach(section.walks) { walk in
                        walkCard(walk)
                            .onAppear {
                                if walk.id == walks.last?.id { Task { await loadMore() } }
                            }
                    }
                }
            }

            if isLoadingMore {
                ProgressView()
                    .tint(MADTheme.Colors.madWhite)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MADTheme.Spacing.sm)
            }
        }
    }

    // MARK: - Walk card

    private func walkCard(_ walk: BuddyWalkRecord) -> some View {
        VStack(spacing: 0) {
            if let photo = walk.photos.first {
                photoHero(photo, walk: walk)
            }
            walkDetails(walk)
        }
        .background(
            RoundedRectangle(
                cornerRadius: MADTheme.CornerRadius.large, style: .continuous
            )
            .fill(MADTheme.Colors.madWhite.opacity(0.06))
        )
        // Clip BEFORE the stroke: a photo runs to the card's edge, and an
        // overlay drawn first then clipped loses half its line width to the
        // clip — the hairline reads as thinner on the photo cards than on the
        // ones without.
        .clipShape(
            RoundedRectangle(
                cornerRadius: MADTheme.CornerRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(
                cornerRadius: MADTheme.CornerRadius.large, style: .continuous
            )
            .strokeBorder(MADTheme.Colors.madWhite.opacity(0.10), lineWidth: 1)
        )
    }

    /// The photo from that walk, big. Tapping it opens the post itself (where
    /// the rest of the pictures, the caption and the hypes live); tapping
    /// anywhere else on the card opens the recap.
    private func photoHero(_ photo: BuddyWalkPhoto, walk: BuddyWalkRecord) -> some View {
        Button {
            MADHaptics.tap()
            photoPostId = photo.postId
        } label: {
            // Sized exactly the way the feed sizes a slide (ZoomablePhotoSlide)
            // — `maxWidth: .infinity` then a FIXED aspect ratio, so the card's
            // height comes from the card's width and not from whatever shape
            // the photo happens to be. A column of walk cards each a different
            // height reads as a jumble; the photo is cropped to fill either way.
            BuddyHistoryPhotoView(url: photo.url)
                .frame(maxWidth: .infinity)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if walk.photos.count > 1 {
                        Text("1/\(walk.photos.count)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(MADTheme.Colors.madWhite)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                            .padding(10)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func walkDetails(_ walk: BuddyWalkRecord) -> some View {
        Button {
            MADHaptics.tap()
            recapSessionId = walk.id
        } label: {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                HStack(spacing: MADTheme.Spacing.md) {
                    // Only when there's no photo above — with one, the tinted
                    // circle competes with the picture for the same corner.
                    if walk.photos.isEmpty {
                        ZStack {
                            Circle()
                                .fill(walk.accentColor.opacity(0.18))
                                .frame(width: 44, height: 44)
                            Image(systemName: walk.mode.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(walk.accentColor)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(walk.crewText(excluding: viewerId))
                            .font(MADTheme.Typography.bodyBold)
                            .foregroundStyle(MADTheme.Colors.madWhite)
                            .lineLimit(1)
                        Text(subtitleText(walk))
                            .font(MADTheme.Typography.caption)
                            .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.55))
                            .lineLimit(1)
                    }

                    Spacer(minLength: MADTheme.Spacing.sm)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(walk.groupDistanceMiles.milesText) mi")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(walk.accentColor)
                        Text("together")
                            .font(MADTheme.Typography.caption)
                            .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.45))
                    }
                }

                crewStrip(walk)
            }
            .padding(MADTheme.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "Tue, Aug 11 · 42m · Sam won". The verdict only appears for the modes
    /// that have one — a co-op walk has no winner by design, and inventing a
    /// leader for it would misread the whole mode.
    private func subtitleText(_ walk: BuddyWalkRecord) -> String {
        var parts = [walk.dayText, walk.durationText]
        if !walk.mode.isCooperative, let winner = walk.winnerUserId {
            if winner == viewerId {
                parts.append("you won")
            } else if let name = walk.participants.first(where: { $0.userId == winner })?
                .displayName {
                parts.append("\(name) won")
            }
        } else if walk.mode == .coopGoal, let goal = walk.goalValue, goal > 0,
            walk.groupDistanceMiles >= goal {
            // Only the hit. A co-op walk that fell short was still a walk you
            // took together, and stamping "missed" on it a month later is the
            // opposite of what this screen is for.
            parts.append("goal hit")
        }
        return parts.joined(separator: " · ")
    }

    /// Everyone's share, in one line. Bars are scaled to the walk's longest
    /// distance so "how did we compare" is read at a glance rather than by
    /// subtracting — the same treatment the recap gives the full standings.
    ///
    /// Capped, and the bar is dropped past a pair. A buddy walk holds up to
    /// EIGHT people: eight avatar-plus-distance-plus-bar entries want ~640pt on
    /// a ~390pt row, and an HStack that can't fit its children doesn't wrap, it
    /// squeezes — the fixed-width bars don't yield, so the names and numbers
    /// are what collapse. The recap behind one tap has the full standings.
    private func crewStrip(_ walk: BuddyWalkRecord) -> some View {
        let shown = Array(walk.participants.prefix(4))
        let overflow = walk.participants.count - shown.count
        let top = walk.participants.map(\.distanceMiles).max() ?? 0
        let showsBars = walk.participants.count <= 2

        return HStack(spacing: MADTheme.Spacing.sm) {
            ForEach(shown) { participant in
                let isYou = participant.userId == viewerId
                HStack(spacing: 6) {
                    AvatarView(
                        name: participant.displayName,
                        imageURL: participant.profileImageUrl,
                        size: 22
                    )
                    .overlay(
                        Circle().strokeBorder(
                            isYou ? walk.accentColor : .clear, lineWidth: 1.5)
                    )
                    Text(participant.distanceMiles.milesText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(
                            MADTheme.Colors.madWhite.opacity(isYou ? 0.9 : 0.6))
                        .lineLimit(1)
                    if showsBars && top > 0 {
                        Capsule()
                            .fill(walk.accentColor.opacity(isYou ? 0.9 : 0.4))
                            .frame(
                                width: max(8, 26 * (participant.distanceMiles / top)),
                                height: 4)
                    }
                }
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Call to action

    /// The screen's whole purpose in one button: you just looked at eleven
    /// walks with this person, so the next thing you should be able to do is
    /// the twelfth.
    private var walkAgainCTA: some View {
        let name = focusedName
        return Button {
            MADHaptics.action()
            startWalk(with: filterUserId)
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(MADTheme.Colors.madWhite.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: "figure.2")
                        .font(.system(size: 16, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.map { "Walk with \($0) again" } ?? "Start a buddy walk")
                        .font(MADTheme.Typography.bodyBold)
                    Text("Pick a time — they'll get an invite")
                        .font(MADTheme.Typography.caption)
                        .opacity(0.85)
                }
                Spacer(minLength: MADTheme.Spacing.sm)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .opacity(0.85)
            }
            .foregroundStyle(MADTheme.Colors.madWhite)
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(
                    cornerRadius: MADTheme.CornerRadius.large, style: .continuous
                )
                .fill(accent)
            )
        }
        .buttonStyle(.plain)
    }

    /// Hand the buddy flow off to the Dashboard, which owns every buddy
    /// presentation (BuddyFlowModifier).
    ///
    /// Three steps in order, none of them optional: dismiss this sheet, switch
    /// to the tab that can present, and only THEN ask for the start sheet. Two
    /// presentations in one transaction race and SwiftUI silently drops one —
    /// the same reason `PostDeepLink.openAfterDismiss` exists.
    private func startWalk(with userId: String?) {
        // Pre-select the person, using the same "last setup" the start sheet
        // already restores from. Semantically right rather than a hack: they
        // are, at this moment, exactly who you last chose to walk with.
        if let userId {
            UserDefaults.standard.set(userId, forKey: "buddyLastInviteesV1")
        }
        if let onWalkAgain {
            onWalkAgain(userId)
            dismiss()
            return
        }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotificationCenter.default.post(
                name: NSNotification.Name("MAD_SwitchTab"),
                object: nil,
                userInfo: ["tab": 0]
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(name: .madStartBuddyWalk, object: nil)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: loadFailed ? "wifi.exclamationmark" : "figure.2")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.35))
            Text(emptyTitle)
                .font(MADTheme.Typography.headline)
                .foregroundStyle(MADTheme.Colors.madWhite)
                .multilineTextAlignment(.center)
            Text(emptySubtitle)
                .font(MADTheme.Typography.caption)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, MADTheme.Spacing.md)
            if !loadFailed {
                walkAgainCTA.padding(.top, MADTheme.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.xl)
    }

    private var emptyTitle: String {
        if loadFailed { return "Couldn't load your walks" }
        if let name = focusedName { return "No walks with \(name) yet" }
        return "No walks together yet"
    }

    private var emptySubtitle: String {
        if loadFailed { return "Check your connection and pull to refresh." }
        if let name = focusedName {
            return "Walk at the same time as \(name) and it lands here — with "
                + "whatever photos you take on it."
        }
        return
            "Walk or run at the same time as a friend and it lands here — miles, "
            + "crew and photos from the day."
    }

    // MARK: - Loading

    private func reload() async {
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            let response = try await buddy.loadHistory(friendId: filterUserId)
            walks = response.sessions
            // Only page one carries totals; a nil here on a later page is
            // normal, so it must never blank what we already have.
            if let fresh = response.totals { totals = fresh }
            nextBefore = response.nextBefore
        } catch {
            loadFailed = true
            print("[BuddyWalksHistoryView] load failed: \(error)")
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, let cursor = nextBefore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let response = try await buddy.loadHistory(
                friendId: filterUserId, before: cursor)
            // Guard against a duplicate append: `onAppear` on the last card can
            // fire more than once while the request is in flight, and the
            // cursor only clears when it returns.
            let known = Set(walks.map(\.id))
            walks.append(contentsOf: response.sessions.filter { !known.contains($0.id) })
            nextBefore = response.nextBefore
        } catch {
            // Silent: the list the user is looking at is intact, and an alert
            // for a page they haven't reached yet is noise.
            print("[BuddyWalksHistoryView] loadMore failed: \(error)")
        }
    }
}

/// A month's worth of walks.
///
/// A struct rather than the `(month:walks:)` tuple this started as: Swift has
/// no key paths into tuple elements, so `ForEach(sections, id: \.month)`
/// doesn't compile.
private struct MonthSection: Identifiable {
    let month: String
    var walks: [BuddyWalkRecord]

    var id: String { month }
}

/// A walk photo, backed by the feed's shared image cache.
///
/// `FeedImageView` publishes the decoded `UIImage` through a binding so the
/// feed's zoom overlay can float a copy of it; nothing here needs that, so the
/// binding is parked in local state. Going through it anyway means a photo the
/// user already scrolled past in the feed is drawn from cache instead of
/// re-downloaded — which matters here, where a screen can hold a dozen.
private struct BuddyHistoryPhotoView: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        FeedImageView(url: url, loadedImage: $image)
    }
}
