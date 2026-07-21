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

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

            VStack(spacing: MADTheme.Spacing.md) {
                VStack(spacing: 6) {
                    Text("MONTHLY RECAP")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.6)
                        .foregroundColor(MADTheme.Colors.madRed)
                        .padding(.top, MADTheme.Spacing.xl)

                    Text("Your \(stats.monthName)")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)

                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(String(format: "%.1f", stats.totalMiles))
                            .font(.system(size: 52, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                        Text("miles")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                if stats.isPerfect {
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("PERFECT MONTH — EVERY SINGLE DAY")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(1.1)
                    }
                    .foregroundColor(gold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(gold.opacity(0.14)))
                }

                HStack(spacing: 10) {
                    recapStat(
                        value: "\(stats.activeDays)/\(stats.daysInMonth)",
                        label: "days completed",
                        icon: "calendar",
                        tint: .green
                    )
                    recapStat(
                        value: String(format: "%.1f", stats.bestDayMiles),
                        label: "best day (mi)",
                        icon: "trophy.fill",
                        tint: gold
                    )
                    recapStat(
                        value: "\(stats.workoutCount)",
                        label: "workouts",
                        icon: "figure.run",
                        tint: MADTheme.Colors.walkBlue
                    )
                }
                .padding(.horizontal, MADTheme.Spacing.md)

                if stats.streakAtMonthEnd > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.orange)
                        Text("Carried a \(stats.streakAtMonthEnd)-day streak into \(currentMonthName)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.75))
                    }
                }

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Button {
                        shareRecap()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .bold))
                            Text("Share Your \(stats.monthName)")
                                .font(.system(size: 16, weight: .heavy, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(MADTheme.Colors.redGradient)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        dismiss()
                    } label: {
                        Text("Keep Running")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.bottom, MADTheme.Spacing.md)
            }
        }
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showShareSheet) {
            if let shareImage {
                ShareSheet(items: [shareImage])
            }
        }
    }

    private var currentMonthName: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f.string(from: Date())
    }

    private func recapStat(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(tint)
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
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
