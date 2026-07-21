import SwiftUI
import HealthKit

// MARK: - Stats model

/// Last-7-days summary computed locally from HealthKit — no network needed.
struct WeeklyRecapStats {
    let totalMiles: Double
    let workoutCount: Int
    let activeDays: Int
    /// Seconds per mile of the best qualifying workout (distance >= 0.95 mi).
    let bestPaceSecondsPerMile: Double?
    let streak: Int
    let startDate: Date
    let endDate: Date

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// "Jun 27 – Jul 3"
    var dateRangeText: String {
        "\(Self.dayFormatter.string(from: startDate)) – \(Self.dayFormatter.string(from: endDate))"
    }

    static func compute(from workouts: [HKWorkout], streak: Int, start: Date, end: Date) -> WeeklyRecapStats {
        var totalMiles = 0.0
        var days = Set<Date>()
        var bestPace: Double?
        let cal = Calendar.current

        for workout in workouts {
            let miles = workout.totalDistance?.doubleValue(for: HKUnit.mile()) ?? 0
            totalMiles += miles
            days.insert(cal.startOfDay(for: workout.startDate))
            if miles >= 0.95 {
                let pace = workout.duration / miles // seconds per mile
                if pace > 0, pace < (bestPace ?? .greatestFiniteMagnitude) {
                    bestPace = pace
                }
            }
        }

        return WeeklyRecapStats(
            totalMiles: totalMiles,
            workoutCount: workouts.count,
            activeDays: days.count,
            bestPaceSecondsPerMile: bestPace,
            streak: streak,
            startDate: start,
            endDate: end
        )
    }
}

// MARK: - Sheet

/// "Your Week" — a branded, shareable 4:5 recap card of the last 7 days,
/// computed locally from HealthKit. Presented as a sheet from the feed teaser.
struct WeeklyRecapView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var stats: WeeklyRecapStats?
    @State private var isLoading = true
    @State private var shareImage: UIImage?
    @State private var showingShareSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: MADTheme.Colors.madRed))
                } else if let stats, stats.workoutCount > 0 {
                    ScrollView {
                        VStack(spacing: MADTheme.Spacing.lg) {
                            WeeklyRecapCardView(stats: stats)
                                .aspectRatio(4.0 / 5.0, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous))
                                .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
                                .padding(.horizontal, MADTheme.Spacing.lg)
                                .padding(.top, MADTheme.Spacing.md)

                            shareButton
                                .padding(.horizontal, MADTheme.Spacing.lg)
                                .padding(.bottom, MADTheme.Spacing.xl)
                        }
                    }
                } else {
                    emptyWeekState
                }
            }
            .navigationTitle("Your Week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(MADTheme.Colors.madRed)
                        .fontWeight(.semibold)
                }
            }
            .preferredColorScheme(.dark)
            .task { await loadStats() }
            .sheet(isPresented: $showingShareSheet) {
                if let shareImage {
                    ShareSheet(items: [shareImage])
                }
            }
        }
    }

    // MARK: - Share

    private var shareButton: some View {
        Button {
            shareCard()
        } label: {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                Text("Share")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                    .fill(MADTheme.Colors.redGradient)
            )
        }
        .buttonStyle(.plain)
    }

    /// Flatten the card to a ~1080px-wide image (same approach as the post
    /// composer's flatten()) and hand it to the share sheet.
    @MainActor
    private func shareCard() {
        guard let stats else { return }
        let designWidth: CGFloat = 320
        let card = WeeklyRecapCardView(stats: stats)
            .frame(width: designWidth, height: designWidth * 5 / 4)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1080 / designWidth
        renderer.isOpaque = true
        guard let image = renderer.uiImage else { return }
        shareImage = image
        showingShareSheet = true
    }

    // MARK: - Empty state

    private var emptyWeekState: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: "figure.run")
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(.white.opacity(0.25))
            Text("A quiet week")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("No walks or runs recorded in the last 7 days. Get a mile in and your recap will be here next week.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, MADTheme.Spacing.xl)
        }
    }

    // MARK: - Data

    private func loadStats() async {
        guard isLoading else { return }
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now)) ?? now

        let workouts = await withCheckedContinuation { (continuation: CheckedContinuation<[HKWorkout], Never>) in
            HealthKitManager.shared.getWorkoutsForDateRange(start: start, end: now) { workouts in
                continuation.resume(returning: workouts)
            }
        }

        stats = WeeklyRecapStats.compute(
            from: workouts,
            streak: UserManager.shared.currentUser.streak,
            start: start,
            end: now
        )
        isLoading = false
    }
}

// MARK: - Card

/// The branded 4:5 recap card — mirrors RunStatsCardView's gradient, glow and
/// typography so shared images look like one family.
struct WeeklyRecapCardView: View {
    let stats: WeeklyRecapStats

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.09, blue: 0.12), .black],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [MADTheme.Colors.madRed.opacity(0.35), .clear],
                center: .init(x: 0.5, y: 0.22), startRadius: 10, endRadius: 360
            )

            VStack(spacing: 14) {
                Spacer()

                // Brand row
                MADLogoMark(size: 46)

                Text("YOUR WEEK")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(4)
                    .foregroundColor(.white.opacity(0.45))

                Text(String(format: "%.1f", stats.totalMiles))
                    .font(.system(size: 76, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                Text("MILES")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(6)
                    .foregroundColor(.white.opacity(0.65))

                // Stat chips — two rows so all four fit the 4:5 canvas.
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        chip("figure.run", "\(stats.workoutCount) \(stats.workoutCount == 1 ? "workout" : "workouts")")
                        chip("calendar", "\(stats.activeDays) \(stats.activeDays == 1 ? "active day" : "active days")")
                    }
                    HStack(spacing: 8) {
                        if let pace = stats.bestPaceSecondsPerMile {
                            chip("speedometer", "\(RunStatsStickerView.paceText(pace)) /mi")
                        }
                        if stats.streak > 0 {
                            chip("flame.fill", "\(stats.streak) day streak", tint: .orange)
                        }
                    }
                }
                .padding(.top, 4)

                Spacer()

                Text(stats.dateRangeText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.bottom, 26)
            }
            .padding(.horizontal, 22)
        }
    }

    private func chip(_ icon: String, _ text: String, tint: Color = .white) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(text).font(.system(size: 13, weight: .heavy, design: .rounded)).monospacedDigit()
        }
        .foregroundColor(tint)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Capsule().fill(Color.white.opacity(0.1)))
    }
}

#Preview {
    WeeklyRecapView()
}
