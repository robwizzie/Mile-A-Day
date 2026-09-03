import SwiftUI

/// Post-session results.
///
/// Shows reconciled numbers where they exist and live numbers until then —
/// `final_distance_miles` is stamped asynchronously once each participant's
/// real HKWorkout syncs, which can trail the session's end by a minute or two.
struct BuddyRecapView: View {
    let sessionId: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var buddy = BuddySessionService.shared

    @ObservedObject private var freshWindow = FreshPostWindowManager.shared

    @State private var recap: BuddyRecapResponse?
    @State private var isLoading = true
    /// Item-presented (ios.md): the wizard needs the loaded session, and an
    /// isPresented flag beside separate state can race to a stale value.
    @State private var wizardSession: BuddySessionState?
    /// Adding MY photo to a walk a friend already posted. Item-presented for
    /// the same reason, and a separate node from the wizard's cover.
    @State private var crewPhotoTarget: CrewPhotoTarget?
    /// Opening the walk's post from here — the "see what we made" exit.
    @State private var openPostId: String?
    /// Every walk you've taken with these people, from the link below.
    @State private var showHistory = false

    /// What the "add your photo" composer needs: which post to join, and whose
    /// it is (the share step says so rather than making the user guess).
    struct CrewPhotoTarget: Identifiable {
        let postId: String
        let authorName: String?
        var id: String { postId }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                if isLoading {
                    ProgressView().tint(MADTheme.Colors.madWhite)
                } else if let session = recap?.session {
                    ScrollView {
                        VStack(spacing: MADTheme.Spacing.lg) {
                            headline(session)
                            standings(session)
                            postSection(session)
                            historyLink(session)
                            Color.clear.frame(height: MADTheme.Spacing.lg)
                        }
                        .padding(MADTheme.Spacing.md)
                    }
                    .fullScreenCover(item: $wizardSession) { session in
                        BuddyPostWizardView(session: session) {
                            // Published — re-read so the CTA becomes the
                            // confirmation and "See the post" gets its id,
                            // rather than the screen looking unchanged after
                            // the thing it exists for has happened.
                            Task { await load(showSpinner: false) }
                        }
                    }
                } else {
                    Text("Couldn't load the recap.")
                        .font(MADTheme.Typography.body)
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.7))
                }
            }
            .navigationTitle((recap?.session.isRunning ?? false) ? "Buddy Run" : "Buddy Walk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        buddy.clearFinishedSession()
                        dismiss()
                    }
                }
            }
        }
        // On the NavigationStack, NOT the ScrollView that already carries the
        // wizard's fullScreenCover — two presentations on one node and SwiftUI
        // silently drops one (ios.md).
        .sheet(isPresented: $showHistory) {
            BuddyWalksHistoryView()
        }
        // Its OWN node again, for the same reason: the NavigationStack above
        // already owns the history sheet.
        .background(
            Color.clear
                .fullScreenCover(item: $crewPhotoTarget) { target in
                    crewPhotoComposer(target)
                }
        )
        // And again. One post opens as ONE post (ios.md) — the loader is the
        // right door here because all this screen has is a post id.
        .background(
            Color.clear
                .sheet(
                    isPresented: Binding(
                        get: { openPostId != nil },
                        set: { if !$0 { openPostId = nil } }
                    )
                ) {
                    if let openPostId {
                        PostDetailLoaderView(postId: openPostId)
                    }
                }
        )
        .task { await load() }
    }

    /// "Add your photo" — the ordinary composer, pointed at the walk's
    /// existing card instead of at a new post of its own.
    private func crewPhotoComposer(_ target: CrewPhotoTarget) -> some View {
        PostComposerView(
            stats: crewPhotoStats(),
            // The user just tapped a camera button; open the shutter, same as
            // the post-run prompt does one tap earlier in its own flow.
            autoOpenCamera: true,
            buddyCrewNames: target.authorName.map { [$0] } ?? [],
            crewPhotoPostId: target.postId
        ) { outcome in
            crewPhotoTarget = nil
            guard case .published = outcome else { return }
            // Same 0.35s deferral the wizard documents: dismissing a cover and
            // mutating state that re-renders behind it in one transaction is
            // the race SwiftUI resolves by dropping one of them.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                Task { await load(showSpinner: false) }
            }
        }
    }

    /// Stats for the crew-photo composer's sticker.
    ///
    /// The sticker shows the WEARER's own numbers — it's their photo — so this
    /// is resolved the same way the wizard resolves the poster's, and falls
    /// back to the session's live figures when no local workout matches yet.
    private func crewPhotoStats() -> RunStatsInput {
        guard let session = recap?.session else {
            return RunStatsInput(
                distance: 0, paceSecondsPerMile: nil, durationSeconds: nil,
                streak: UserManager.shared.freshBackendStreak
                    ?? UserManager.shared.currentUser.streak,
                calories: nil, steps: nil, workoutId: nil, dateText: nil
            )
        }
        if let workoutId = RunPostService.buddyWorkoutId(
            reconciled: session.me(buddy.currentUserId)?.workoutId,
            startedAt: session.startedAtDate,
            endedAt: session.endedAtDate
        ) {
            return RunPostService.todayStats(workoutId: workoutId)
        }
        let me = session.me(buddy.currentUserId)
        let distance = me?.bestDistance ?? 0
        let duration = Double(me?.durationSeconds ?? 0)
        return RunStatsInput(
            distance: distance,
            paceSecondsPerMile: distance > 0 && duration > 0 ? duration / distance : nil,
            durationSeconds: duration > 0 ? duration : nil,
            streak: UserManager.shared.freshBackendStreak
                ?? UserManager.shared.currentUser.streak,
            calories: nil,
            steps: nil,
            workoutId: nil,
            dateText: nil
        )
    }

    // MARK: - Sections

    /// The result as a celebration: ringed mode icon, the verdict, and the
    /// group total as the biggest number on the screen. Same visual family as
    /// the start sheet's summary header and the lobby's plan header — the walk
    /// should end looking like the thing you set up, not like a settings list.
    private func headline(_ session: BuddySessionState) -> some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(session.accentColor.opacity(0.18))
                    .frame(width: 76, height: 76)
                Circle()
                    .strokeBorder(session.accentColor.opacity(0.45), lineWidth: 1.5)
                    .frame(width: 76, height: 76)
                Image(systemName: session.mode.icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(session.accentColor)
            }

            Text(headlineText(session))
                .font(MADTheme.Typography.title2)
                .foregroundStyle(MADTheme.Colors.madWhite)
                .multilineTextAlignment(.center)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(session.groupDistanceMiles.milesText)
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(MADTheme.Colors.madWhite)
                Text("mi")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.55))
            }

            Text(subheadText(session))
                .font(MADTheme.Typography.subheadline)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.65))
                .multilineTextAlignment(.center)

            // A shared goal gets its bar — "did we make it" is the whole
            // question that mode asks, so answer it visually, not just in the
            // headline's wording.
            if session.mode == .coopGoal, let goal = session.goalValue, goal > 0 {
                progressCapsule(
                    fraction: session.groupDistanceMiles / goal,
                    tint: session.accentColor
                )
                .padding(.horizontal, MADTheme.Spacing.lg)
                .padding(.top, MADTheme.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.lg)
        .padding(.horizontal, MADTheme.Spacing.md)
        .madLiquidGlass(cornerRadius: MADTheme.CornerRadius.extraLarge)
    }

    /// Everyone's share of the walk, in ONE card — divider rows like the start
    /// sheet's friend list, not floating slabs. Each row carries a thin bar
    /// scaled to the day's longest distance, so "how'd we compare" is read at
    /// a glance instead of by subtracting numbers.
    private func standings(_ session: BuddySessionState) -> some View {
        let rows = ranked(session)
        let top = rows.map(\.bestDistance).max() ?? 0

        return VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            Text(session.mode.isCooperative ? "The crew" : "How it finished")
                .font(MADTheme.Typography.headline)
                .foregroundStyle(MADTheme.Colors.madWhite)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, participant in
                    if index > 0 {
                        Divider().background(MADTheme.Colors.madWhite.opacity(0.08))
                    }
                    standingsRow(
                        participant,
                        session: session,
                        topDistance: top
                    )
                }
            }
            .background(
                RoundedRectangle(
                    cornerRadius: MADTheme.CornerRadius.large, style: .continuous
                )
                .fill(MADTheme.Colors.madWhite.opacity(0.06))
                .overlay(
                    RoundedRectangle(
                        cornerRadius: MADTheme.CornerRadius.large, style: .continuous
                    )
                    .strokeBorder(MADTheme.Colors.madWhite.opacity(0.10), lineWidth: 1)
                )
            )
        }
    }

    private func standingsRow(
        _ participant: BuddyParticipant,
        session: BuddySessionState,
        topDistance: Double
    ) -> some View {
        let isYou = participant.userId == buddy.currentUserId
        let isWinner = !session.mode.isCooperative && participant.place == 1

        return HStack(spacing: MADTheme.Spacing.md) {
            // Cooperative modes have no ranking to show — everybody either
            // made it or didn't, together.
            if !session.mode.isCooperative, let place = participant.place {
                Group {
                    if place == 1 {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.yellow)
                    } else {
                        Text("\(place)")
                            .font(MADTheme.Typography.title3)
                            .monospacedDigit()
                            .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.5))
                    }
                }
                .frame(width: 24)
            }

            AvatarView(
                name: participant.displayName,
                imageURL: participant.profileImageUrl,
                size: 44
            )
            .overlay(
                Circle().strokeBorder(
                    isYou ? session.accentColor : .clear, lineWidth: 2)
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(isYou ? "You" : participant.displayName)
                    .font(MADTheme.Typography.bodyBold)
                    .foregroundStyle(MADTheme.Colors.madWhite)
                    .lineLimit(1)

                progressCapsule(
                    fraction: topDistance > 0
                        ? participant.bestDistance / topDistance : 0,
                    tint: session.accentColor.opacity(isYou || isWinner ? 1 : 0.55)
                )
            }

            Spacer(minLength: MADTheme.Spacing.sm)

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(participant.bestDistance.milesText) mi")
                    .font(MADTheme.Typography.bodyBold)
                    .monospacedDigit()
                    .foregroundStyle(session.accentColor)

                // Until the real workout syncs, the number on screen is the
                // one accumulated from live reports. Say so rather than let it
                // silently change a minute later — but quietly: it resolves
                // itself, so it must not read like an error. ONLY while it
                // plausibly still can: a recap opened from the history for a
                // walk weeks old showed a spinner that was never going to
                // stop. Past the window the live figure simply stands.
                if participant.finalDistanceMiles == nil, Self.mayStillSync(session) {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(MADTheme.Colors.madWhite.opacity(0.4))
                        Text("syncing")
                            .font(MADTheme.Typography.caption)
                            .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.4))
                    }
                }
            }
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.vertical, MADTheme.Spacing.sm + 2)
    }

    /// A workout lands within minutes of the finish (a late Watch sync within
    /// the hour). Two hours after the walk ended, "syncing" is a lie.
    static func mayStillSync(_ session: BuddySessionState) -> Bool {
        guard let ended = session.endedAtDate else { return true }
        return Date().timeIntervalSince(ended) < 2 * 3600
    }

    /// Thin track-and-fill bar. GeometryReader because the fill's width IS a
    /// fraction of the track's — anything based on `.offset` or a guessed
    /// width draws outside what the row measured (ios.md).
    private func progressCapsule(fraction: Double, tint: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(MADTheme.Colors.madWhite.opacity(0.12))
                Capsule()
                    .fill(tint)
                    .frame(
                        width: max(6, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 6)
    }

    /// The post flow's front door — opens the crew-and-routes wizard
    /// (BuddyPostWizardView), which owns the composer hand-off. Gated on the
    /// DAY tier, not the ten-minute camera countdown (ios.md: only an
    /// affordance that literally opens the shutter takes `isCameraOpen`) — a
    /// buddy recap is exactly the screen someone opens once they're home, and
    /// the composer it leads to offers the walk's photos when the camera has
    /// closed. A recap is also reachable long after the walk (deep link,
    /// notification, a screen left open), so the CTA reflects the window
    /// rather than 403-ing on tap, and says what's missing rather than just
    /// going grey, since this is the screen's primary action.
    @ViewBuilder
    private func postSection(_ session: BuddySessionState) -> some View {
        // SERVER first, device second. `alreadyPosted` reads a UserDefaults
        // list that by construction cannot see what a friend did on their
        // phone, so on the OTHER participants' devices it was always false —
        // every one of them was shown a lit "Post this walk" and every one of
        // them posted. That is the duplicate: one walk, N cards, each
        // crediting the others, each with a fraction of the photos.
        // Credited on someone's post → that post IS this walk's, and your
        // photo belongs on it. NOT credited (you joined after they'd settled
        // their crew) → their post doesn't represent your walk at all, so fall
        // through to the ordinary CTA. Suppressing it there would be the
        // opposite failure to the duplicate: a walk you took that you're
        // silently not allowed to share.
        if let post = recap?.post, post.amICredited {
            postedState(session, post: post)
        } else if alreadyPosted(session) {
            // No server answer (older API) but this device remembers posting
            // it. Leaving the CTA lit here was the other half of "it made me
            // go through the wizard again".
            postedConfirmation(session)
        } else if freshWindow.canPostToday {
            Button {
                MADHaptics.action()
                wizardSession = session
            } label: {
                HStack(spacing: MADTheme.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(MADTheme.Colors.madWhite.opacity(0.18))
                            .frame(width: 40, height: 40)
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.isRunning ? "Post this run" : "Post this walk")
                            .font(MADTheme.Typography.bodyBold)
                        Text("Everyone's on it — see the crew and routes first")
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
                    .fill(session.accentColor)
                )
            }
            .buttonStyle(.plain)
        } else {
            Text("Finish a walk or run today to share a photo from it.")
                .font(MADTheme.Typography.caption)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, MADTheme.Spacing.md)
        }
    }

    /// The walk is on the feed. What's left depends on whether YOUR photo is.
    ///
    /// This is where the duplicate used to be born. Every participant reached
    /// this screen with a lit "Post this walk", because nothing on their phone
    /// knew a friend had already posted — so the honest answer to "can I share
    /// my picture of this walk?" was "make another post", and people did.
    /// Now the walk's card is a place your photo can go.
    @ViewBuilder
    private func postedState(
        _ session: BuddySessionState,
        post: BuddySessionPostRef
    ) -> some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            // The AUTHOR is never offered "add your photo": their picture is
            // the post's own media, and they have no `post_coauthors` row, so
            // `myPhotoAdded` is false for them by construction — reading it
            // alone would tell the person who just posted to post again.
            if isAuthor(post) || post.myPhotoAdded || !freshWindow.canPostToday {
                sharedConfirmation(session, post: post)
            } else {
                addYourPhotoButton(session, post: post)
            }
            seeThePostLink(session, post: post)
        }
    }

    private func isAuthor(_ post: BuddySessionPostRef) -> Bool {
        post.authorUserId == buddy.currentUserId
    }

    /// The CTA that replaces "post this walk" for everyone who wasn't first.
    private func addYourPhotoButton(
        _ session: BuddySessionState,
        post: BuddySessionPostRef
    ) -> some View {
        Button {
            MADHaptics.action()
            crewPhotoTarget = CrewPhotoTarget(
                postId: post.postId, authorName: post.authorName)
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(MADTheme.Colors.madWhite.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add your photo")
                        .font(MADTheme.Typography.bodyBold)
                    Text(
                        post.authorName.map { "\($0) posted this walk — put your shot on it" }
                            ?? "This walk is on the feed — put your shot on it"
                    )
                    .font(MADTheme.Typography.caption)
                    .opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
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
                .fill(session.accentColor)
            )
        }
        .buttonStyle(.plain)
    }

    /// Everything's done — the walk is up and your picture is on it.
    private func sharedConfirmation(
        _ session: BuddySessionState,
        post: BuddySessionPostRef
    ) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(session.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    isAuthor(post) ? "Shared to the feed"
                        : (post.myPhotoAdded ? "Your photo's on it" : "This walk is on the feed")
                )
                .font(MADTheme.Typography.smallBold)
                .foregroundStyle(MADTheme.Colors.madWhite)
                Text(sharedSubtitle(session, post: post))
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(MADTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(MADTheme.Colors.madWhite.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .strokeBorder(session.accentColor.opacity(0.3), lineWidth: 1)
        )
    }

    private func sharedSubtitle(
        _ session: BuddySessionState,
        post: BuddySessionPostRef
    ) -> String {
        if isAuthor(post) {
            return crewNames(session).isEmpty
                ? "One post for this walk."
                : "One post — you and \(crewNames(session))."
        }
        if post.myPhotoAdded { return "One post for this walk, with everyone on it." }
        // Credited, no photo of your own, and the day window has closed — the
        // only way left to reach this branch.
        let whose = post.authorName.map { "\($0)'s post" } ?? "The post"
        return "\(whose) covers this walk — today's photo window has closed."
    }

    /// The exit this screen never had: go look at the thing you just made.
    private func seeThePostLink(
        _ session: BuddySessionState,
        post: BuddySessionPostRef
    ) -> some View {
        Button {
            MADHaptics.tap()
            openPostId = post.postId
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 13, weight: .semibold))
                Text("See the post")
                    .font(MADTheme.Typography.smallBold)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(session.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, MADTheme.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Where the post CTA goes once the walk has been shared.
    ///
    /// A quiet confirmation rather than nothing at all: a section that simply
    /// vanishes after you use it reads as though the post failed.
    private func postedConfirmation(_ session: BuddySessionState) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(session.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Shared to the feed")
                    .font(MADTheme.Typography.smallBold)
                    .foregroundStyle(MADTheme.Colors.madWhite)
                Text(
                    crewNames(session).isEmpty
                        ? "One post for this walk."
                        : "One post — you and \(crewNames(session))."
                )
                .font(MADTheme.Typography.caption)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(MADTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(MADTheme.Colors.madWhite.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .strokeBorder(session.accentColor.opacity(0.3), lineWidth: 1)
        )
    }

    /// "Sam and Alex" — everyone on the post except the viewer.
    private func crewNames(_ session: BuddySessionState) -> String {
        let names = session.participants
            .filter { $0.status == .finished && $0.userId != buddy.currentUserId }
            .map(\.displayName)
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names[0]) and \(names.count - 1) others"
        }
    }

    /// Has this walk already been shared? Reads the same registry the photo
    /// prompt now checks, keyed on the same locally-resolved workout id the
    /// wizard posts with — the three have to agree or the dedup misses.
    private func alreadyPosted(_ session: BuddySessionState) -> Bool {
        guard let workoutId = RunPostService.buddyWorkoutId(
            reconciled: session.me(buddy.currentUserId)?.workoutId,
            startedAt: session.startedAtDate,
            endedAt: session.endedAtDate
        ) else { return false }
        return PostedWorkoutRegistry.hasPost(for: workoutId)
    }

    /// "This one and 11 more" — the walk just taken, put in the context of the
    /// ones before it. The recap is the moment the history is most worth
    /// opening: you have just finished a walk with this person, so the
    /// accumulating total is at its most persuasive right here.
    ///
    /// A plain link rather than a card: the post CTA above is this screen's
    /// primary action and must stay the loudest thing on it.
    private func historyLink(_ session: BuddySessionState) -> some View {
        Button {
            MADHaptics.tap()
            showHistory = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "figure.2")
                    .font(.system(size: 13, weight: .semibold))
                Text("See all your walks together")
                    .font(MADTheme.Typography.smallBold)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(session.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, MADTheme.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Copy

    private func headlineText(_ session: BuddySessionState) -> String {
        switch session.mode {
        case .together:
            return "Nice walk together"
        case .coopGoal:
            let goal = session.goalValue ?? 0
            return session.groupDistanceMiles >= goal ? "Goal smashed" : "Good effort together"
        case .raceGoal, .raceTime:
            guard let winner = session.winnerUserId else { return "Dead heat" }
            if winner == buddy.currentUserId { return "You won" }
            let name =
                session.participants.first { $0.userId == winner }?.displayName ?? "Your buddy"
            return "\(name) won"
        }
    }

    /// The line under the big number. The number itself is rendered above at
    /// hero size, so this only has to say what it counts.
    private func subheadText(_ session: BuddySessionState) -> String {
        switch session.mode {
        case .together:
            return "miles between you"
        case .coopGoal:
            let goal = session.goalValue ?? 0
            let goalText =
                goal == goal.rounded() ? "\(Int(goal))" : String(format: "%.1f", goal)
            return "of your \(goalText) mile goal, together"
        case .raceGoal, .raceTime:
            return session.winnerUserId == nil
                ? "miles in total — too close to call"
                : "miles covered in total"
        }
    }

    private func ranked(_ session: BuddySessionState) -> [BuddyParticipant] {
        session.activeParticipants.sorted { $0.bestDistance > $1.bestDistance }
    }

    /// `showSpinner: false` for RE-loads after posting: swapping the whole
    /// screen for a ProgressView would tear down the ScrollView that hosts the
    /// wizard's cover mid-dismissal, and the user would watch the recap they
    /// just came back to blink away for no reason.
    private func load(showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        defer { if showSpinner { isLoading = false } }
        guard let fresh = try? await buddy.recap(sessionId: sessionId) else { return }
        recap = fresh
    }
}
