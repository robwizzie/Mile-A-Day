import SwiftUI
import UIKit

// MARK: - Stats

/// Last month, summarized from the local workout index. Nil when the month
/// has no workouts (new users never see an empty recap).
struct MonthlyRecapStats {
    let monthName: String      // "July"
    let monthKey: String       // "2026-07" — the seen-marker key
    let totalMiles: Double
    let activeDays: Int
    let daysInMonth: Int
    let bestDayMiles: Double
    let workoutCount: Int
    let streakAtMonthEnd: Int

    var isPerfect: Bool { activeDays >= daysInMonth }

    static func computePreviousMonth(
        healthManager: HealthKitManager,
        goal: Double,
        streak: Int,
        now: Date = Date()
    ) -> MonthlyRecapStats? {
        let cal = Calendar.current
        guard
            let startOfThisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)),
            let startOfPrev = cal.date(byAdding: .month, value: -1, to: startOfThisMonth),
            let index = healthManager.workoutIndex
        else { return nil }

        var byDay: [Date: Double] = [:]
        var workoutCount = 0
        for entry in index.workoutsByDate.values.flatMap({ $0 })
        where entry.localDate >= startOfPrev && entry.localDate < startOfThisMonth {
            byDay[cal.startOfDay(for: entry.localDate), default: 0] += entry.distance
            workoutCount += 1
        }
        guard !byDay.isEmpty else { return nil }

        let effectiveGoal = goal > 0 ? goal : 1.0
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM"
        let keyFormatter = DateFormatter()
        keyFormatter.dateFormat = "yyyy-MM"

        return MonthlyRecapStats(
            monthName: monthFormatter.string(from: startOfPrev),
            monthKey: keyFormatter.string(from: startOfPrev),
            totalMiles: byDay.values.reduce(0, +),
            activeDays: byDay.values.filter {
                ProgressCalculator.isGoalCompleted(current: $0, goal: effectiveGoal)
            }.count,
            daysInMonth: cal.range(of: .day, in: .month, for: startOfPrev)?.count ?? 30,
            bestDayMiles: byDay.values.max() ?? 0,
            workoutCount: workoutCount,
            streakAtMonthEnd: streak
        )
    }
}

/// Once-per-month auto-present marker.
enum MonthlyRecapManager {
    private static let seenKey = "monthlyRecapSeenMonth"

    static func shouldAutoPresent(_ stats: MonthlyRecapStats) -> Bool {
        stats.activeDays > 0
            && UserDefaults.standard.string(forKey: seenKey) != stats.monthKey
    }

    static func markSeen(_ monthKey: String) {
        UserDefaults.standard.set(monthKey, forKey: seenKey)
    }
}

// MARK: - Sheet

/// "Your July" — auto-presents once when the calendar flips, and hands the
/// user a share-ready card. The growth loop: the app offers the post, the
/// user just has to be proud of it.
struct MonthlyRecapView: View {
    let stats: MonthlyRecapStats
    @Environment(\.dismiss) private var dismiss
    @State private var shareImage: UIImage?
    @State private var showShareSheet = false

    private var gold: Color { Color(red: 1.0, green: 0.84, blue: 0.35) }
    private var completionFraction: Double {
        guard stats.daysInMonth > 0 else { return 0 }
        return min(Double(stats.activeDays) / Double(stats.daysInMonth), 1)
    }

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    monthHero

                    VStack(spacing: 12) {
                        recapMetricRow(
                            icon: "calendar",
                            tint: .green,
                            value: "\(stats.activeDays)",
                            label: "goal days",
                            detail: "of \(stats.daysInMonth)"
                        )
                        recapMetricRow(
                            icon: "trophy.fill",
                            tint: gold,
                            value: String(format: "%.1f", stats.bestDayMiles),
                            label: "best day",
                            detail: "miles"
                        )
                        recapMetricRow(
                            icon: "figure.run",
                            tint: MADTheme.Colors.walkBlue,
                            value: "\(stats.workoutCount)",
                            label: "workouts",
                            detail: String(format: "%.1f mi total", stats.totalMiles)
                        )
                    }

                    if stats.streakAtMonthEnd > 0 {
                        streakCarryCard
                    }

                    actionButtons
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 18)
            }
        }
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showShareSheet) {
            if let shareImage {
                ShareSheet(items: [shareImage])
            }
        }
    }

    private var monthHero: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("MONTHLY RECAP")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.6)
                        .foregroundColor(MADTheme.Colors.madRed)
                    Text("Your \(stats.monthName)")
                        .font(.system(size: 31, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text(heroSubtitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                monthlyProgressRing
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", stats.totalMiles))
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.78)
                Text("mi")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.58))
                Spacer(minLength: 0)
            }

            if stats.isPerfect {
                HStack(spacing: 7) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("PERFECT MONTH")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.1)
                    Spacer(minLength: 0)
                    Text("every day")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                }
                .foregroundColor(gold)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(Capsule().fill(gold.opacity(0.14)))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    MADTheme.Colors.madRed.opacity(0.18),
                                    gold.opacity(0.10),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.24), radius: 18, x: 0, y: 12)
    }

    private var monthlyProgressRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 8)
            Circle()
                .trim(from: 0, to: completionFraction)
                .stroke(
                    LinearGradient(
                        colors: stats.isPerfect ? [gold, .orange] : [.green, MADTheme.Colors.walkBlue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int(round(completionFraction * 100)))%")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                Text("days")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(width: 76, height: 76)
    }

    private var heroSubtitle: String {
        if stats.isPerfect {
            return "A clean sweep. Every day held the line."
        }
        return "\(stats.activeDays) goal day\(stats.activeDays == 1 ? "" : "s") banked last month."
    }

    private var streakCarryCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom))
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.orange.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(stats.streakAtMonthEnd)-day streak carried forward")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("You brought the fire into \(currentMonthName).")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.58))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.20), lineWidth: 1)
                )
        )
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                shareRecap()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .bold))
                    Text("Share \(stats.monthName)")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(MADTheme.Colors.redGradient)
                )
                .shadow(color: MADTheme.Colors.madRed.opacity(0.28), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain)

            Button {
                dismiss()
            } label: {
                Text("Keep Running")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.62))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }

    private var currentMonthName: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f.string(from: Date())
    }

    private func recapMetricRow(icon: String, tint: Color, value: String, label: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(tint.opacity(0.14)))

            Text(value)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text(detail)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.52))
            }

            Spacer(minLength: 0)
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func shareRecap() {
        MADHaptics.action()
        let renderer = ImageRenderer(content: MonthlyRecapShareCard(stats: stats))
        renderer.scale = 3.0
        renderer.isOpaque = false
        if let image = renderer.uiImage {
            shareImage = image
            showShareSheet = true
        }
    }
}

// MARK: - Share card

/// The postable version — same 600×750 language as the records share cards.
struct MonthlyRecapShareCard: View {
    let stats: MonthlyRecapStats

    private var gold: Color { Color(red: 1.0, green: 0.84, blue: 0.35) }

    var body: some View {
        VStack(spacing: 24) {
            Text("MY \(stats.monthName.uppercased())")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .tracking(3)
                .foregroundColor(.white.opacity(0.85))
                .padding(.top, 44)

            VStack(spacing: 2) {
                Text(String(format: "%.1f", stats.totalMiles))
                    .font(.system(size: 100, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                Text("miles")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }

            if stats.isPerfect {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                    Text("PERFECT MONTH")
                        .tracking(2)
                }
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(gold)
            }

            VStack(spacing: 12) {
                GlassStatRow(
                    icon: "calendar",
                    text: "\(stats.activeDays) of \(stats.daysInMonth) days completed",
                    color: .green,
                    isDarkMode: true
                )
                GlassStatRow(
                    icon: "trophy.fill",
                    text: String(format: "Best day: %.1f mi", stats.bestDayMiles),
                    color: gold,
                    isDarkMode: true
                )
                if stats.streakAtMonthEnd > 0 {
                    GlassStatRow(
                        icon: "flame.fill",
                        text: "\(stats.streakAtMonthEnd)-day streak and counting",
                        color: .orange,
                        isDarkMode: true
                    )
                }
            }
            .padding(.horizontal, 60)

            Spacer()

            ShareCardFooter()
        }
        .frame(width: 600, height: 750)
        .background(
            ShareCardBackground(
                accentColor: Color(red: 0.85, green: 0.25, blue: 0.35),
                isDarkMode: true
            )
        )
        .padding(8)
    }
}
