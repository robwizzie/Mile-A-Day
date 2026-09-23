import SwiftUI

// MARK: - Weekly Recap
//
// "Your week" — the Saturday-evening push, the feed's weekend teaser, the
// dashboard's week card and the inbox row all open it. It reads the server's
// recap (`GET /users/:id/weekly-recap`, Sunday→Saturday in the user's own
// days) and falls back to a phone-built one against an older server.
//
// It exists to be SHARED — the week is the most Instagram-able unit this app
// has (a streak number and seven green days) — so the one big action is
// "Share your week", which opens the Share Studio on the WEEK templates.
// Everything above it is the story that card tells, in the app's own day
// language: green = goal met, blue (`SavedDayStyle`) = a token carried it,
// an orange arc = some miles short of the goal.

struct WeeklyRecapView: View {
    /// nil = the latest week: the one in progress, except on a Sunday, when
    /// the week that just ended is the one worth looking at.
    var weekStart: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var shownWeek: String = ""
    @State private var recap: WeeklyRecap?
    @State private var loadError: WeeklyRecapService.LoadError?
    @State private var isLoading = true
    @State private var revealed = false
    @State private var storyShare: MADStoryContent?
    @State private var didRecordOpen = false

    private var currentWeekStart: String { WeeklyRecap.weekStart(containing: Date()) }

    private var defaultWeek: String {
        if let weekStart, !weekStart.isEmpty { return weekStart }
        let isSunday = Calendar.current.component(.weekday, from: Date()) == 1
        if isSunday, let previous = WeeklyRecap.shift(currentWeekStart, weeks: -1) { return previous }
        return currentWeekStart
    }

    private var canGoForward: Bool {
        guard let next = WeeklyRecap.shift(shownWeek, weeks: 1) else { return false }
        return next <= currentWeekStart
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ShareGround(glow: MADTheme.Colors.madRed, center: UnitPoint(x: 0.85, y: 0.02), strength: 0.32, radius: 520)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Group {
                    if isLoading && recap == nil {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let recap {
                        content(recap)
                    } else {
                        errorState
                    }
                }
            }

            if let recap, (recap.totalMiles ?? 0) > 0 {
                shareButton(recap)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            if shownWeek.isEmpty { shownWeek = defaultWeek }
            if !didRecordOpen {
                didRecordOpen = true
                TelemetryService.record(ShareTelemetry.weeklyRecapOpened)
            }
            await load()
        }
        .sheet(item: $storyShare) { content in
            ShareStudioView(content: content, initialTemplate: .weekStory)
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        ZStack {
            Text("Your week")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.62))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.13)))
                        .frame(width: 44, height: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
    }

    private var weekSwitcher: some View {
        HStack(spacing: 0) {
            Button { step(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 44, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Previous week")
            Spacer(minLength: 0)
            Text((recap?.rangeText ?? "").uppercased())
                .font(.system(size: 12, weight: .black, design: .rounded))
                .tracking(2.2)
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button { step(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 44, height: 36)
                    .contentShape(Rectangle())
            }
            .disabled(!canGoForward)
            .opacity(canGoForward ? 1 : 0.25)
            .accessibilityLabel("Next week")
        }
        .foregroundColor(.white.opacity(0.75))
        .buttonStyle(.plain)
    }

    // MARK: Content

    private func content(_ recap: WeeklyRecap) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                weekSwitcher
                    .reveal(revealed, index: 0, reduceMotion: reduceMotion)
                hero(recap)
                    .reveal(revealed, index: 1, reduceMotion: reduceMotion)
                stripCard(recap)
                    .reveal(revealed, index: 2, reduceMotion: reduceMotion)
                statsGrid(recap)
                    .reveal(revealed, index: 3, reduceMotion: reduceMotion)
                if let streak = recap.currentStreak, streak > 0 {
                    streakCard(recap, streak: streak)
                        .reveal(revealed, index: 4, reduceMotion: reduceMotion)
                }
                if let challenge = recap.weeklyChallenge, challenge.name?.isEmpty == false {
                    challengeCard(challenge)
                        .reveal(revealed, index: 5, reduceMotion: reduceMotion)
                }
                if let friends = recap.friends, !friends.top.isEmpty {
                    friendsCard(friends)
                        .reveal(revealed, index: 6, reduceMotion: reduceMotion)
                }
                if !recap.highlights.isEmpty {
                    highlightsCard(recap.highlights)
                        .reveal(revealed, index: 7, reduceMotion: reduceMotion)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 120)
            .lockedToScrollWidth()
        }
        .scrollIndicators(.hidden)
        .refreshable { await load() }
    }

    private func hero(_ recap: WeeklyRecap) -> some View {
        let total = recap.totalMiles ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            Text(total > 0 ? "YOU COVERED" : "A QUIET WEEK")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(2.4)
                .foregroundColor(MADTheme.Colors.warning)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(total.distanceText)
                    .font(.system(size: 84, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(DistanceUnits.current.plural)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
            HStack(spacing: 8) {
                if let delta = recap.deltaFraction {
                    WeekDeltaChip(delta: delta)
                }
                if recap.isComplete == false {
                    Text("Week in progress")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            if total <= 0 {
                Text("Nothing logged this week yet. One mile starts it.")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func stripCard(_ recap: WeeklyRecap) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                label("GOAL DAYS")
                Spacer()
                Text("\(recap.goalDays) of 7")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
            }
            ShareWeekStrip(recap: recap, dot: 36)
            HStack(spacing: 14) {
                legend(MADTheme.Colors.success, "Goal met")
                if recap.days.contains(where: \.covered) {
                    legend(SavedDayStyle.tint, "Saved")
                }
                legend(MADTheme.Colors.warning, "Some miles")
            }
        }
        .recapCard()
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private func statsGrid(_ recap: WeeklyRecap) -> some View {
        let tiles: [(String, String, String)] = [
            recap.workouts.map { ("figure.walk", "\($0)", $0 == 1 ? "Workout" : "Workouts") },
            recap.totalDurationSeconds.flatMap { $0 > 0 ? ("clock.fill", Self.durationText($0), "Time moving") : nil },
            recap.longestWorkoutMiles.flatMap { $0 > 0 ? ("arrow.up.right", ShareCopy.distance($0) ?? "", "Longest") : nil },
            recap.fastestMilePaceSeconds.flatMap { pace -> (String, String, String)? in
                guard pace > 0 else { return nil }
                return ("bolt.fill",
                        RunStatsStickerView.paceText(pace.pacePerDisplayUnit) + " " + DistanceUnits.current.paceSuffix,
                        "Fastest \(DistanceUnits.current.singular)")
            },
        ].compactMap { $0 }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                         spacing: 12) {
            ForEach(tiles, id: \.2) { tile in
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: tile.0)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                        .accessibilityHidden(true)
                    Text(tile.1)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(tile.2)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .recapCard(padding: 14)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func streakCard(_ recap: WeeklyRecap, streak: Int) -> some View {
        HStack(spacing: 14) {
            ShareStyleFlame(size: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(streak) day streak")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(recap.streakGain.map { "+\($0) this week" } ?? "Still going")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(MADTheme.Colors.warning)
            }
            Spacer(minLength: 0)
        }
        .recapCard()
        .accessibilityElement(children: .combine)
    }

    private func challengeCard(_ challenge: WeeklyRecap.Challenge) -> some View {
        let done = challenge.completed == true
        let progress: Double = {
            guard let value = challenge.value, let target = challenge.target, target > 0 else { return done ? 1 : 0 }
            return min(1, value / target)
        }()
        let icon = challenge.icon.flatMap { UIImage(systemName: $0) != nil ? $0 : nil } ?? "trophy.fill"
        return VStack(alignment: .leading, spacing: 12) {
            label("WEEKLY CHALLENGE")
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(done ? .black : .white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(done ? MADTheme.Colors.success : Color.white.opacity(0.1)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(challenge.name ?? "")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text(done ? "Completed" : challengeProgressText(challenge))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(done ? MADTheme.Colors.success : .white.opacity(0.55))
                }
                Spacer(minLength: 0)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(done ? MADTheme.Colors.success : MADTheme.Colors.warning)
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 6)
        }
        .recapCard()
    }

    private func challengeProgressText(_ challenge: WeeklyRecap.Challenge) -> String {
        guard let value = challenge.value, let target = challenge.target else { return "Not finished" }
        if challenge.unit == "miles" {
            return "\(value.distanceText) of \(target.distanceText) \(DistanceUnits.current.abbreviation)"
        }
        return "\(Int(value.rounded())) of \(Int(target.rounded()))"
    }

    private func friendsCard(_ friends: WeeklyRecap.Friends) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                label("AMONG FRIENDS")
                Spacer()
                if let rank = friends.rank, let of = friends.of {
                    Text("#\(rank) of \(of)")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            ForEach(Array(friends.top.enumerated()), id: \.element.id) { index, friend in
                HStack(spacing: 12) {
                    Text(friend.isMe ? "\(friends.rank ?? index + 1)" : "\(index + 1)")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(index == 0 && !friend.isMe ? MADTheme.Colors.warning : .white.opacity(0.6))
                        .frame(width: 22)
                    AvatarView(name: friend.displayName, imageURL: friend.profileImageUrl, size: 34)
                    Text(friend.isMe ? "You" : friend.displayName)
                        .font(.system(size: 15, weight: friend.isMe ? .heavy : .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(ShareCopy.distance(friend.miles) ?? "0.00 \(DistanceUnits.current.abbreviation)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(friend.isMe ? Color.white.opacity(0.08) : Color.clear)
                )
                .accessibilityElement(children: .combine)
            }
        }
        .recapCard()
    }

    private func highlightsCard(_ highlights: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            label("HIGHLIGHTS")
            ForEach(highlights, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(MADTheme.Colors.warning)
                        .accessibilityHidden(true)
                    Text(line)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .recapCard()
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .black, design: .rounded))
            .tracking(1.8)
            .foregroundColor(.white.opacity(0.45))
    }

    private func shareButton(_ recap: WeeklyRecap) -> some View {
        Button {
            MADHaptics.action()
            TelemetryService.record(ShareTelemetry.opened)
            storyShare = recap.storyContent
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .accessibilityHidden(true)
                Text("Share your week")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(MADTheme.Colors.redGradient)
                    .shadow(color: MADTheme.Colors.madRed.opacity(0.45), radius: 18, x: 0, y: 8)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(
            LinearGradient(colors: [.clear, Color.black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .frame(height: 140)
                .allowsHitTesting(false),
            alignment: .bottom
        )
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            Image(systemName: loadError == .weekInFuture ? "calendar" : "wifi.exclamationmark")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(.white.opacity(0.3))
                .accessibilityHidden(true)
            Text(loadError == .weekInFuture ? "This week hasn't started yet" : "Couldn't load your week")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            if loadError != .weekInFuture {
                Button("Try again") { Task { await load() } }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(MADTheme.Colors.madRed)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Data

    private func step(_ weeks: Int) {
        guard let next = WeeklyRecap.shift(shownWeek, weeks: weeks),
              weeks < 0 || next <= currentWeekStart else { return }
        MADHaptics.tap()
        shownWeek = next
        Task { await load() }
    }

    private func load() async {
        let week = shownWeek.isEmpty ? defaultWeek : shownWeek
        isLoading = true
        revealed = false
        let result = await WeeklyRecapService.load(weekStart: week)
        guard week == shownWeek || shownWeek.isEmpty else { return }
        isLoading = false
        switch result {
        case .success(let value):
            recap = value
            loadError = nil
        case .failure(let error):
            recap = nil
            loadError = error
        }
        if reduceMotion {
            revealed = true
        } else {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { revealed = true }
        }
    }

    static func durationText(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m) min"
    }
}

// MARK: - Pieces

private extension View {
    /// The recap's card: the app's flat 5% fill with an 8% hairline.
    func recapCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    /// Staggered entrance — rise and fade in order. Reduce Motion: in place.
    func reveal(_ shown: Bool, index: Int, reduceMotion: Bool) -> some View {
        self
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.85)
                        .delay(Double(index) * 0.06), value: shown)
    }
}

#Preview {
    WeeklyRecapView()
}
