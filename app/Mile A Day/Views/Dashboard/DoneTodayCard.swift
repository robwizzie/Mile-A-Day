import SwiftUI
import HealthKit

/// The home page AFTER the mile, when today's walk hasn't been shared.
///
/// The day's card used to keep offering "Start your mile" all day, so the
/// screen's one big action was wrong for everyone who had already done it.
/// Once the day is done this takes its place, and it is ONLY the share
/// prompt: the hero's done line already says the mile is in (with Replay and
/// Go again beside it), so a card that said it again was a second "done".
///
/// - **Not posted yet**: today's photo theme, then **Post a photo** (the one
///   photo prompt every door uses, `PhotoPromptView` via the celebration
///   queue), **Add to story** (the opt-in finish frame) and the **Flamey
///   card** (the share studio). "Not today" folds it away until tomorrow.
/// - **Posted, folded, or nothing to share** (a steps-only day): nothing.
///   It used to stay as a whole card saying "Shared. Nice one."
struct DoneTodayCard: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager

    @AppStorage("doneCardFoldedDayV1") private var foldedDay = ""
    @State private var showStorySheet = false
    @State private var showShareCard = false

    private static func todayStamp() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private var workoutId: String? { RunPostService.dailyMileWorkoutId() }

    private var posted: Bool {
        guard let id = workoutId else { return false }
        return PostedWorkoutRegistry.hasPost(for: id)
    }

    private var folded: Bool { foldedDay == Self.todayStamp() }

    /// A photo needs a walk or run to belong to; a steps-only day has none.
    private var canShare: Bool { workoutId != nil && FreshPostWindowManager.shared.canPostToday }

    private var workoutType: String {
        guard let id = workoutId,
              let w = healthManager.cachedWorkouts.first(where: { $0.uuid.uuidString == id })
        else { return "walking" }
        return w.workoutActivityType == .running ? "running" : "walking"
    }

    var body: some View {
        if canShare && !posted && !folded {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Share today's walk")
                    .madFont(size: 17, weight: .heavy, design: .rounded)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Button {
                    MADHaptics.tap()
                    withAnimation(.easeInOut(duration: 0.25)) { foldedDay = Self.todayStamp() }
                } label: {
                    Text("Not today")
                        .madFont(size: 13, weight: .semibold, design: .rounded)
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
            }

            shareSection
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardCardSurface(style: .fun))
        .sheet(isPresented: $showStorySheet) {
            if let id = workoutId {
                AddFinishStorySheet(
                    stats: RunPostService.todayStats(workoutId: id),
                    onAdded: {},
                    onPostPhoto: {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { postPhoto() }
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showShareCard) {
            EnhancedShareView(
                user: userManager.currentUser,
                currentDistance: healthManager.todaysDistance,
                progress: ProgressCalculator.calculateProgress(
                    current: healthManager.todaysDistance, goal: userManager.currentUser.goalMiles),
                isGoalCompleted: true,
                fastestPace: userManager.currentUser.fastestMilePace > 0
                    ? userManager.currentUser.fastestMilePace : healthManager.fastestMilePace,
                mostMiles: healthManager.cachedCurrentStreakStats.mostMiles > 0
                    ? healthManager.cachedCurrentStreakStats.mostMiles : healthManager.mostMilesInOneDay
            )
        }
    }

    private var shareSection: some View {
        let theme = DailyPhotoTheme.today
        return VStack(alignment: .leading, spacing: 12) {
            // The reason to take the photo: one light prompt a day.
            HStack(spacing: 8) {
                Text(theme.emoji)
                    .font(.system(size: 20))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Today's photo theme")
                        .madFont(size: 11, weight: .semibold, design: .rounded)
                        .foregroundColor(.white.opacity(0.5))
                    Text(theme.title)
                        .madFont(size: 15, weight: .bold, design: .rounded)
                        .foregroundColor(.white)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
            .accessibilityElement(children: .combine)

            Button {
                postPhoto()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .accessibilityHidden(true)
                    Text("Post a photo")
                }
                .madFont(size: 16, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MADTheme.Colors.madRed))
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                secondaryButton("Add to story", icon: "plus.circle") {
                    showStorySheet = true
                }
                secondaryButton("Flamey card", icon: "flame") {
                    showShareCard = true
                }
            }
        }
    }

    private func secondaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            MADHaptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .accessibilityHidden(true)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .madFont(size: 14, weight: .bold, design: .rounded, maxScale: 1.3)
            .foregroundColor(.white.opacity(0.9))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    /// The one photo prompt, through the celebration queue like every other
    /// door (`PhotoPromptView` → composer), so a post from here behaves exactly
    /// like one made straight after the walk.
    private func postPhoto() {
        guard let id = workoutId else { return }
        MADHaptics.action()
        CelebrationManager.shared.addCelebration(.postRunPhotoPrompt(workoutId: id, workoutType: workoutType))
    }
}

/// One light photo prompt a day, the same for everyone on the same date, so
/// friends' photos tend to answer the same question. Rotates through the list
/// by day of the year; no server involved.
struct DailyPhotoTheme {
    let emoji: String
    let title: String

    static let all: [DailyPhotoTheme] = [
        .init(emoji: "☁️", title: "Sky check"),
        .init(emoji: "👟", title: "Show us your shoes"),
        .init(emoji: "🌳", title: "Best tree you passed"),
        .init(emoji: "🐶", title: "Any dogs out there?"),
        .init(emoji: "🏠", title: "Your street today"),
        .init(emoji: "🌅", title: "Catch the light"),
        .init(emoji: "🎨", title: "Find something red"),
        .init(emoji: "🛣️", title: "The road ahead"),
        .init(emoji: "🌸", title: "Something growing"),
        .init(emoji: "🧢", title: "Walk selfie"),
        .init(emoji: "🪨", title: "Weird thing you spotted"),
        .init(emoji: "💧", title: "Water, anywhere"),
        .init(emoji: "🏙️", title: "Look up"),
        .init(emoji: "🌙", title: "Out after dark"),
        .init(emoji: "☕️", title: "What kept you going"),
        .init(emoji: "🚏", title: "A sign you passed"),
        .init(emoji: "🍂", title: "Ground level"),
        .init(emoji: "👯", title: "Who came with you?"),
        .init(emoji: "🌧️", title: "Whatever the weather"),
        .init(emoji: "🏁", title: "Where you finished"),
    ]

    static var today: DailyPhotoTheme {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return all[(day - 1) % all.count]
    }
}
