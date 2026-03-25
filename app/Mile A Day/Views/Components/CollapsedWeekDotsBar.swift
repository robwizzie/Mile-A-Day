//
//  CollapsedWeekDotsBar.swift
//  Mile A Day
//
//  Compact sticky dots bar showing weekday goal completion.
//  Fades in as the main chart scrolls off screen.
//

import SwiftUI

struct CollapsedWeekDotsBar: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @Environment(\.colorScheme) var colorScheme

    private let accentRed = Color(red: 0.85, green: 0.25, blue: 0.35)
    private let missedOrange = Color(red: 1.0, green: 0.6, blue: 0.0)

    private var goalDistance: Double {
        userManager.currentUser.goalMiles
    }

    private var weekDays: [DayData] {
        WeekDataProvider.weekDays(healthManager: healthManager, goalDistance: goalDistance)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(weekDays) { day in
                VStack(spacing: 3) {
                    dotIndicator(day: day)
                    Text(day.shortLabel)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(day.isToday ? accentRed : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.15 : 0.25),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        )
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func dotIndicator(day: DayData) -> some View {
        ZStack {
            if day.isFuture {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                    .frame(width: 24, height: 24)
            } else if day.metGoal {
                Circle()
                    .fill(Color.green)
                    .frame(width: 24, height: 24)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            } else if day.distance > 0 {
                Circle()
                    .fill(missedOrange.opacity(0.3))
                    .frame(width: 24, height: 24)
                Circle()
                    .fill(missedOrange)
                    .frame(width: 8, height: 8)
            } else {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                    .frame(width: 24, height: 24)
            }

            if day.isToday {
                Circle()
                    .stroke(accentRed, lineWidth: 2)
                    .frame(width: 28, height: 28)
            }
        }
    }
}
