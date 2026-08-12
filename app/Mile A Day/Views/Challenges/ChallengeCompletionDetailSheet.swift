import SwiftUI

// MARK: - Challenge Completion Detail Sheet
//
// One sheet for every place a past completion is tapped (the last-14-days
// grid and the All Completions history list). The header and the day's
// workouts render immediately from cached local data; the challenge-specific
// "how you did it" section — duel scores, the shared photo, who was hyped or
// nudged, pace/steps/distance numbers — arrives from
// `GET /users/:id/challenges/:localDate/detail` while the sheet is open.
// A failed or empty fetch quietly degrades to the generic header + workouts
// layout this sheet had before details existed.

struct ChallengeCompletionDetailSheet: View {
    let completion: ChallengeCompletion
    @ObservedObject var healthManager: HealthKitManager

    @State private var detail: RemoteChallengeService.CompletionDetailDTO?
    @State private var isLoadingDetail = false
    @State private var hasFetchedDetail = false

    // MARK: Local workout data (same source the old sheet used)

    private var workouts: [WorkoutRecord] {
        healthManager.workoutIndex?.workouts(for: completion.date) ?? []
    }

    private var totalDistance: Double {
        workouts.reduce(0) { $0 + $1.distance }
    }

    private var totalDuration: TimeInterval {
        workouts.reduce(0) { $0 + $1.duration }
    }

    private var averagePace: TimeInterval? {
        guard totalDistance > 0 else { return nil }
        return (totalDuration / 60.0) / totalDistance // min/mi
    }

    private var descriptionText: String {
        if let d = detail?.description, !d.isEmpty { return d }
        return completion.description
    }

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    challengeHeader
                    challengeDetailSection
                    if workouts.isEmpty {
                        emptyWorkoutState
                    } else {
                        daySummaryCard
                        workoutsListSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 32)
            }
        }
        .task { await loadDetail() }
    }

    @MainActor
    private func loadDetail() async {
        guard !hasFetchedDetail else { return }
        hasFetchedDetail = true
        guard let userId = UserManager.shared.currentUser.backendUserId else { return }
        let localDate = completion.localDate ?? Self.ymdFormatter.string(from: completion.date)
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        do {
            detail = try await RemoteChallengeService.fetchCompletionDetail(
                userId: userId,
                localDate: localDate
            )
        } catch {
            // Header, day stats and workouts all render from local data —
            // the sheet just stays in its generic layout.
            print("[ChallengeCompletionDetailSheet] detail fetch failed: \(error)")
        }
    }

    /// Fallback for pre-update cached completions that don't carry the
    /// server's localDate string yet. `completion.date` is device-local
    /// start-of-day, so the device-local calendar reproduces the string.
    private static let ymdFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: Header

    private var challengeHeader: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.green, Color(red: 0.18, green: 0.78, blue: 0.42)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                Image(systemName: completion.icon)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }
            Text(completion.title)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            if !descriptionText.isEmpty {
                Text(descriptionText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            Text(completion.date.formattedShortDate)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
        }
    }

    // MARK: Challenge-specific detail

    @ViewBuilder
    private var challengeDetailSection: some View {
        if let detail {
            if let h2h = detail.h2h {
                H2HCompletionCard(h2h: h2h)
            } else if let post = detail.post {
                SharedPhotoCard(post: post)
            } else if let social = detail.social {
                SocialFriendsCard(social: social, isNudge: detail.challengeKey == "wingman")
            } else if let steps = detail.steps {
                StepsCompletionCard(steps: steps)
            } else if let pace = detail.pace {
                PaceCompletionCard(pace: pace)
            } else if let distance = detail.distance {
                DistanceCompletionCard(distance: distance)
            } else if let timeWindow = detail.timeWindow {
                TimeWindowCompletionCard(timeWindow: timeWindow)
            } else if let friend = detail.friend {
                FriendAddedCard(friend: friend)
            } else if let activity = detail.activity {
                ActivityCompletionCard(activity: activity, challengeKey: detail.challengeKey)
            }
        } else if isLoadingDetail {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(.white.opacity(0.6))
                Text("Loading challenge details…")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    // MARK: Day summary (local HealthKit)

    private var daySummaryCard: some View {
        HStack(spacing: 12) {
            statTile(value: String(format: "%.2f mi", totalDistance), label: "Miles", icon: "figure.run")
            statTile(value: formatDuration(totalDuration), label: "Time", icon: "clock.fill")
            if let pace = averagePace {
                statTile(value: formatPaceMinutes(pace), label: "Avg pace", icon: "speedometer")
            } else {
                statTile(value: "—", label: "Avg pace", icon: "speedometer")
            }
        }
    }

    private func statTile(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.green)
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .textCase(.uppercase)
                .tracking(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: Workouts list (local HealthKit)

    private var workoutsListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("WORKOUTS")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                Text("\(workouts.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }
            VStack(spacing: 8) {
                ForEach(workouts.sorted(by: { $0.localEndTime > $1.localEndTime }), id: \.id) { record in
                    workoutRow(record)
                }
            }
        }
    }

    private func workoutRow(_ record: WorkoutRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconFor(record.workoutType))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.green)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.green.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text(record.workoutType.capitalized)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(Self.timeOfDayFormatter.string(from: record.localEndTime))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.2f mi", record.distance))
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text(formatDuration(record.duration))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.05))
        )
    }

    private var emptyWorkoutState: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.3))
            Text("No workout details for this day")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
            Text("HealthKit history may not be cached this far back.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.05))
        )
    }

    // MARK: Formatting helpers

    private func iconFor(_ type: String) -> String {
        switch type.lowercased() {
        case "running": return "figure.run"
        case "walking": return "figure.walk"
        case "cycling": return "figure.outdoor.cycle"
        case "hiking": return "figure.hiking"
        default: return "figure.mixed.cardio"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func formatPaceMinutes(_ minPerMi: Double) -> String {
        let m = Int(minPerMi)
        let s = Int(round((minPerMi - Double(m)) * 60))
        let ss = s < 10 ? "0\(s)" : "\(s)"
        return "\(m):\(ss)/mi"
    }

    private static let timeOfDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
}

// MARK: - Shared card styling

private struct DetailCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
            )
    }
}

extension View {
    fileprivate func detailCard() -> some View {
        modifier(DetailCardBackground())
    }
}

private func detailLabel(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .tracking(1.2)
        .foregroundColor(.white.opacity(0.55))
}

private func progressBar(progress: Double, colors: [Color]) -> some View {
    GeometryReader { geo in
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.1))
                .frame(height: 8)
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                )
                .frame(width: max(0, min(progress, 1)) * geo.size.width, height: 8)
        }
    }
    .frame(height: 8)
}

// MARK: - Head-to-Head: the finished duel + record vs that rival

private struct H2HCompletionCard: View {
    let h2h: RemoteChallengeService.CompletionH2hDTO

    private var myImage: String? { UserManager.shared.currentUser.profileImageUrl }
    private var rivalName: String { h2h.rival.displayName }
    private var won: Bool { h2h.result == "won" }
    private var tied: Bool { h2h.result == "tied" }
    private var accent: Color { won ? .green : (tied ? .yellow : .orange) }

    private var verdict: String {
        if won { return "You won the duel" }
        if tied { return "The duel ended dead even" }
        return "\(rivalName) logged more miles"
    }

    private var recordText: String {
        "\(h2h.record.wins)W · \(h2h.record.losses)L · \(h2h.record.ties)T"
    }

    var body: some View {
        VStack(spacing: 12) {
            detailLabel("THE DUEL")

            HStack(spacing: 10) {
                duelSide(name: "You", image: myImage, miles: h2h.myMiles, highlight: won)

                VStack(spacing: 6) {
                    Text("VS")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                    Text(won ? "W" : (tied ? "T" : "L"))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(accent)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(accent.opacity(0.18)))
                        .overlay(Circle().stroke(accent.opacity(0.4), lineWidth: 1))
                }
                .frame(width: 70)

                duelSide(
                    name: rivalName,
                    image: h2h.rival.profileImageUrl,
                    miles: h2h.rivalMiles,
                    highlight: !won && !tied
                )
            }

            HStack(spacing: 6) {
                Image(systemName: won ? "trophy.fill" : "flag.2.crossed.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(won ? .yellow : accent)
                Text(verdict)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            Divider()
                .overlay(Color.white.opacity(0.1))

            HStack {
                Text("All-time vs \(rivalName)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                Spacer()
                Text(recordText)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
            }

            if h2h.mutual {
                Text("\(rivalName) got the same matchup — you were racing each other")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
            }
        }
        .detailCard()
    }

    private func duelSide(name: String, image: String?, miles: Double, highlight: Bool) -> some View {
        VStack(spacing: 4) {
            AvatarView(name: name, imageURL: image, size: 40)
                .overlay(
                    Circle().strokeBorder(highlight ? accent : .clear, lineWidth: 2)
                )
            Text(name)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
            // Server-final duel scores, rounded to 2dp by the resolver — plain
            // %.2f matches them exactly (`.milesText` floors).
            Text(String(format: "%.2f mi", miles))
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(highlight ? accent : .white.opacity(0.75))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Share the Journey: the photo that completed it

private struct SharedPhotoCard: View {
    let post: RemoteChallengeService.CompletionPostDTO

    private var postedTimeText: String? {
        guard let date = BuddyDate.parse(post.createdAt) else { return nil }
        return Self.timeFormatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            detailLabel("YOUR POST")

            if let url = ProfileImageService.fullImageURL(for: post.mediaUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ZStack {
                        Rectangle().fill(Color.white.opacity(0.06))
                        ProgressView()
                            .tint(.white.opacity(0.5))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if let caption = post.caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(3)
            }

            if let time = postedTimeText {
                Text("Posted at \(time)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .detailCard()
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
}

// MARK: - Hype Squad / Wingman: who was cheered on or nudged

private struct SocialFriendsCard: View {
    let social: RemoteChallengeService.CompletionSocialDTO
    let isNudge: Bool

    private var headline: String {
        let n = social.friends.count
        if n == 1, let only = social.friends.first {
            return isNudge ? "You nudged \(only.displayName)" : "You cheered on \(only.displayName)"
        }
        return isNudge ? "You nudged \(n) friends" : "You cheered on \(n) friends"
    }

    private var subline: String? {
        guard social.totalActions > social.friends.count else { return nil }
        return isNudge ? "\(social.totalActions) nudges sent" : "\(social.totalActions) hypes sent"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            detailLabel(isNudge ? "WINGMAN" : "HYPE SQUAD")

            HStack(spacing: 6) {
                Image(systemName: isNudge ? "hand.wave.fill" : "hands.clap.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isNudge ? .orange : .pink)
                Text(headline)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            VStack(spacing: 8) {
                ForEach(social.friends, id: \.userId) { friend in
                    HStack(spacing: 10) {
                        AvatarView(name: friend.displayName, imageURL: friend.profileImageUrl, size: 32)
                        Text(friend.displayName)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: isNudge ? "hand.wave.fill" : "hands.clap.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.05))
                    )
                }
            }

            if let subline {
                Text(subline)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .detailCard()
    }
}

// MARK: - 10K Steps

private struct StepsCompletionCard: View {
    let steps: RemoteChallengeService.CompletionStepsDTO

    private var progress: Double {
        guard steps.goalSteps > 0 else { return 1 }
        return Double(steps.steps) / Double(steps.goalSteps)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            detailLabel("STEPS")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(steps.steps.formatted())")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                Text("of \(steps.goalSteps.formatted()) steps")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }
            progressBar(progress: progress, colors: [.mint, .green])
        }
        .detailCard()
    }
}

// MARK: - Speed Round / Beat Your Pace

private struct PaceCompletionCard: View {
    let pace: RemoteChallengeService.CompletionPaceDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            detailLabel("PACE")
            if let best = pace.bestPaceSecondsPerMile {
                HStack(spacing: 12) {
                    paceTile(title: "Your best mile", value: paceText(best), color: .green)
                    if let target = pace.targetPaceSecondsPerMile {
                        paceTile(title: "Target", value: paceText(target), color: .white.opacity(0.7))
                    }
                }
            } else {
                // beat_your_pace with no prior splits completes by hitting the
                // daily goal — there's no mile split to show.
                Text("Completed by hitting your daily goal")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .detailCard()
    }

    private func paceTile(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(color)
                .monospacedDigit()
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .textCase(.uppercase)
                .tracking(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func paceText(_ secondsPerMile: Double) -> String {
        let total = Int(secondsPerMile.rounded())
        return String(format: "%d:%02d /mi", total / 60, total % 60)
    }
}

// MARK: - Distance challenges (Double Down, Bonus Mile, 5K/10K Day, Walk It Out)

private struct DistanceCompletionCard: View {
    let distance: RemoteChallengeService.CompletionDistanceDTO

    private var walking: Bool { distance.scope == "walking" }

    private var progress: Double {
        guard distance.targetMiles > 0 else { return 1 }
        return distance.miles / distance.targetMiles
    }

    private var goalText: String {
        let target = String(format: "%g", distance.targetMiles)
        return walking ? "of \(target) mi walked" : "of \(target) mi goal"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            detailLabel("DISTANCE")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.2f mi", distance.miles))
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                Text(goalText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }
            progressBar(progress: progress, colors: [.cyan, .blue])
        }
        .detailCard()
    }
}

// MARK: - Early Bird / Night Owl

private struct TimeWindowCompletionCard: View {
    let timeWindow: RemoteChallengeService.CompletionTimeWindowDTO

    private var isEarly: Bool { timeWindow.window == "early" }
    private var windowTitle: String { isEarly ? "Early Bird" : "Night Owl" }

    private var finishText: String {
        guard let display = clockDisplay(timeWindow.finishedLocalTime) else {
            return isEarly ? "Finished your mile before 9 AM" : "Finished your mile after 8 PM"
        }
        return "Finished your mile at \(display)"
    }

    /// "HH:MM" (the workout's own wall clock, sent by the server) → "h:mm AM".
    private func clockDisplay(_ hm: String?) -> String? {
        guard let hm else { return nil }
        let parts = hm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        let hour12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", hour12, m, h >= 12 ? "PM" : "AM")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isEarly ? "sunrise.fill" : "moon.stars.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(isEarly ? .yellow : .purple)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.08)))

            VStack(alignment: .leading, spacing: 2) {
                Text(windowTitle)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text(finishText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            if let miles = timeWindow.qualifyingMiles {
                Text(String(format: "%.2f mi", miles))
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .monospacedDigit()
            }
        }
        .detailCard()
    }
}

// MARK: - Make a Friend

private struct FriendAddedCard: View {
    let friend: RemoteChallengeService.CompletionFriendDTO

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(name: friend.displayName, imageURL: friend.profileImageUrl, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("You added \(friend.displayName)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("Your first friend on MAD")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
            Spacer()
            Image(systemName: "person.badge.plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.cyan)
        }
        .detailCard()
    }
}

// MARK: - Cross-Train / Two-a-Day

private struct ActivityCompletionCard: View {
    let activity: RemoteChallengeService.CompletionActivityDTO
    let challengeKey: String

    private var isCrossTrain: Bool { challengeKey == "cross_train" }

    private var variantCaption: String? {
        switch activity.variant {
        case "walk_today": return "Recovery day — the goal was a walking mile"
        case "run_today": return "The goal was to log your mile as a run"
        case "mixed": return "The goal was both a walk and a run"
        default: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            detailLabel(isCrossTrain ? "YOUR MIX" : "YOUR DAY")

            HStack(spacing: 12) {
                activityTile(icon: "figure.run", title: "Run", value: String(format: "%.2f mi", activity.runMiles))
                activityTile(icon: "figure.walk", title: "Walk", value: String(format: "%.2f mi", activity.walkMiles))
                if !isCrossTrain {
                    activityTile(icon: "number", title: "Workouts", value: "\(activity.workoutCount)")
                }
            }

            if let variantCaption {
                Text(variantCaption)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .detailCard()
    }

    private func activityTile(icon: String, title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.green)
            Text(value)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }
}
