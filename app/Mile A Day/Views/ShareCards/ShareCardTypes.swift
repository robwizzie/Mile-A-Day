//
//  ShareCardTypes.swift
//  Mile A Day
//
//  Individual share card types extracted from ShareCardsView.swift
//

import SwiftUI
import HealthKit

// MARK: - Individual Share Cards (Tighter Spacing)

struct StreakShareCard: View {
    let streak: Int
    let isActiveToday: Bool
    let isAtRisk: Bool
    @Environment(\.colorScheme) var colorScheme

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    // Dynamic colors based on streak status
    private var streakColor: Color {
        if isActiveToday {
            return .green
        } else if isAtRisk {
            return .red
        } else {
            return .orange
        }
    }

    private var gradientColors: [Color] {
        if isActiveToday {
            return [.green.opacity(0.4), .green.opacity(0.2), .green.opacity(0.1)]
        } else if isAtRisk {
            return [.red.opacity(0.4), .red.opacity(0.2), .red.opacity(0.1)]
        } else {
            return [.orange.opacity(0.4), .orange.opacity(0.2), .orange.opacity(0.1)]
        }
    }

    var body: some View {
        ZStack {
            // Base background color
            RoundedRectangle(cornerRadius: 80)
                .fill(isDarkMode ? Color.black.opacity(0.95) : Color.white.opacity(0.2))

            // Red tint overlay
            RoundedRectangle(cornerRadius: 80)
                .fill(
                    LinearGradient(
                        colors: [
                            MADTheme.Colors.madRed.opacity(0.25),
                            MADTheme.Colors.madRed.opacity(0.15),
                            MADTheme.Colors.madRed.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Red glow outline
            RoundedRectangle(cornerRadius: 80)
                .stroke(
                    LinearGradient(
                        colors: [
                            MADTheme.Colors.madRed.opacity(0.9),
                            MADTheme.Colors.madRed.opacity(0.6),
                            MADTheme.Colors.madRed.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 4
                )

            // Shadow for glow effect
            RoundedRectangle(cornerRadius: 80)
                .fill(Color.clear)
                .shadow(color: MADTheme.Colors.madRed.opacity(0.7), radius: 40, x: 0, y: 0)

            VStack(spacing: 0) {
                // Streak circle with fire icon (like widget) - tighter and more exciting
                ZStack {
                    // Outer glow effect
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    streakColor.opacity(0.4),
                                    streakColor.opacity(0.2),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 120,
                                endRadius: 180
                            )
                        )
                        .frame(width: 360, height: 360)
                        .blur(radius: 20)

                    // Background circle with gradient
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 260, height: 260)
                        .shadow(color: streakColor.opacity(0.6), radius: 20, x: 0, y: 0)

                    // Progress ring background
                    Circle()
                        .stroke(Color.gray.opacity(0.25), lineWidth: 7)
                        .frame(width: 285, height: 285)

                    // Progress ring (full when completed) with glow
                    Circle()
                        .trim(from: 0, to: isActiveToday ? 1.0 : 0.8)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    streakColor,
                                    streakColor.opacity(0.9),
                                    streakColor.opacity(0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .frame(width: 285, height: 285)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: streakColor.opacity(0.7), radius: 10, x: 0, y: 0)

                    // Center content with fire icon - more exciting
                    VStack(spacing: 8) {
                        // Fire icon with glow and animation effect
                        ZStack {
                            // Fire glow behind
                            Image(systemName: "flame.fill")
                                .font(.system(size: 50, weight: .bold))
                                .foregroundColor(.orange.opacity(0.4))
                                .blur(radius: 8)

                            // Main fire icon
                            Image(systemName: "flame.fill")
                                .font(.system(size: 50, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.yellow, .orange, .red],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: .orange.opacity(0.9), radius: 10, x: 0, y: 0)
                        }

                        // Streak number with glow
                        Text("\(streak)")
                            .font(.system(size: 70, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: streakColor.opacity(0.6), radius: 6, x: 0, y: 0)

                        // Days text
                        Text(streak == 1 ? "day" : "days")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .padding(.top, 30)

                Spacer(minLength: 10)

                // MAD icon and slogan at bottom
                VStack(spacing: 8) {
                    Image("mad-logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 140, height: 140)
                        .shadow(color: .black.opacity(0.4), radius: 15, x: 0, y: 5)

                    Text("Go the Extra Mile")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.bottom, 20)
            }
            .padding(30)
        }
        .frame(width: 600, height: 750) // Much tighter, more compact size
        .padding(8) // Add tiny bit of blank space around the card
        .clipped()
    }
}

struct TodaysProgressShareCard: View {
    let currentDistance: Double
    let goalDistance: Double
    let progress: Double
    let didComplete: Bool
    @Environment(\.colorScheme) var colorScheme

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var accentColor: Color {
        .blue
    }

    var body: some View {
        ZStack {
            // Base background color
            RoundedRectangle(cornerRadius: 80)
                .fill(isDarkMode ? Color.black.opacity(0.95) : Color.white.opacity(0.2))

            // Blue tint overlay
            RoundedRectangle(cornerRadius: 80)
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.25),
                            accentColor.opacity(0.15),
                            accentColor.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Blue glow outline
            RoundedRectangle(cornerRadius: 80)
                .stroke(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.9),
                            accentColor.opacity(0.6),
                            accentColor.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 4
                )

            // Shadow for glow effect
            RoundedRectangle(cornerRadius: 80)
                .fill(Color.clear)
                .shadow(color: accentColor.opacity(0.7), radius: 40, x: 0, y: 0)

            VStack(spacing: 0) {
                Spacer()

                // Progress content - centered
                VStack(spacing: 24) {
                    Text("Today's Progress")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        Text(String(format: "%.2f", currentDistance))
                            .font(.system(size: 90, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("/ \(String(format: "%.1f", goalDistance))")
                            .font(.system(size: 36, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                    }

                    Text("miles")
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.2))
                            RoundedRectangle(cornerRadius: 14)
                                .fill(didComplete ? Color.green : accentColor)
                                .frame(width: geometry.size.width * min(progress, 1.0))
                        }
                    }
                    .frame(height: 20)
                    .padding(.horizontal, 50)

                    if didComplete {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.green)
                            Text("Goal completed!")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundColor(.green)
                        }
                    } else {
                        Text("\(Int(progress * 100))% complete")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                Spacer()

                // MAD icon and slogan at bottom
                VStack(spacing: 8) {
                    Image("mad-logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 140, height: 140)
                        .shadow(color: .black.opacity(0.4), radius: 15, x: 0, y: 5)

                    Text("Go the Extra Mile")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.bottom, 20)
            }
            .padding(30)
        }
        .frame(width: 600, height: 750)
        .padding(8)
        .clipped()
    }
}

struct FastestPaceShareCard: View {
    let fastestPace: TimeInterval
    @Environment(\.colorScheme) var colorScheme

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var accentColor: Color {
        .green
    }

    private var paceString: String {
        let minutes = Int(fastestPace)
        let seconds = Int((fastestPace - Double(minutes)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        ZStack {
            // Base background color
            RoundedRectangle(cornerRadius: 80)
                .fill(isDarkMode ? Color.black.opacity(0.95) : Color.white.opacity(0.2))

            // Green tint overlay
            RoundedRectangle(cornerRadius: 80)
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.25),
                            accentColor.opacity(0.15),
                            accentColor.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Green glow outline
            RoundedRectangle(cornerRadius: 80)
                .stroke(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.9),
                            accentColor.opacity(0.6),
                            accentColor.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 4
                )

            // Shadow for glow effect
            RoundedRectangle(cornerRadius: 80)
                .fill(Color.clear)
                .shadow(color: accentColor.opacity(0.7), radius: 40, x: 0, y: 0)

            VStack(spacing: 0) {
                Spacer()

                // Pace content - centered
                VStack(spacing: 24) {
                    Text("Fastest Mile")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    if fastestPace > 0 {
                        Text(paceString)
                            .font(.system(size: 100, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("per mile")
                            .font(.system(size: 24, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))

                        let mph = 60.0 / fastestPace
                        Text(String(format: "%.1f mph", mph))
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundColor(accentColor)
                    } else {
                        Image(systemName: "figure.run")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.top, 20)

                        Text("No runs recorded yet")
                            .font(.system(size: 24, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                Spacer()

                // MAD icon and slogan at bottom
                VStack(spacing: 8) {
                    Image("mad-logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 140, height: 140)
                        .shadow(color: .black.opacity(0.4), radius: 15, x: 0, y: 5)

                    Text("Go the Extra Mile")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.bottom, 20)
            }
            .padding(30)
        }
        .frame(width: 600, height: 750)
        .padding(8)
        .clipped()
    }
}

