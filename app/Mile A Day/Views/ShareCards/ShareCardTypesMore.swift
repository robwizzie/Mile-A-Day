import SwiftUI
import HealthKit

// MARK: - Additional Share Card Types

struct MostMilesShareCard: View {
    let mostMiles: Double
    @Environment(\.colorScheme) var colorScheme

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var accentColor: Color {
        .purple
    }

    var body: some View {
        ZStack {
            ShareCardBackground(accentColor: accentColor, isDarkMode: isDarkMode)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 24) {
                    Text("Most Miles")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("in a single day")
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))

                    Text(String(format: "%.2f", mostMiles))
                        .font(.system(size: 100, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("miles")
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                }

                Spacer()

                ShareCardFooter()
            }
            .padding(30)
        }
        .frame(width: 600, height: 750)
        .padding(8)
        .clipped()
    }
}

struct TotalMilesShareCard: View {
    let totalMiles: Double
    let streak: Int
    @Environment(\.colorScheme) var colorScheme

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var accentColor: Color {
        .red
    }

    var body: some View {
        ZStack {
            ShareCardBackground(accentColor: accentColor, isDarkMode: isDarkMode)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 24) {
                    Text("TOTAL DISTANCE")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text(String(format: "%.1f", totalMiles))
                        .font(.system(size: 100, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("lifetime miles")
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))

                    VStack(spacing: 16) {
                        let marathons = totalMiles / 26.2
                        HStack(spacing: 12) {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white.opacity(0.8))
                            Text("\(String(format: "%.1f", marathons)) marathons")
                                .font(.system(size: 20, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                        }

                        let avgPerDay = totalMiles / Double(max(streak, 1))
                        HStack(spacing: 12) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 20))
                                .foregroundColor(.white.opacity(0.8))
                            Text("\(String(format: "%.2f", avgPerDay)) mi/day avg")
                                .font(.system(size: 20, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .padding(.top, 10)
                }

                Spacer()

                ShareCardFooter()
            }
            .padding(30)
        }
        .frame(width: 600, height: 750)
        .padding(8)
        .clipped()
    }
}

struct WeekSummaryShareCard: View {
    let currentDistance: Double
    let totalMiles: Double
    let streak: Int
    let fastestPace: TimeInterval
    @Environment(\.colorScheme) var colorScheme

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var accentColor: Color {
        .cyan
    }

    private var paceString: String {
        let minutes = Int(fastestPace)
        let seconds = Int((fastestPace - Double(minutes)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        ZStack {
            ShareCardBackground(accentColor: accentColor, isDarkMode: isDarkMode)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 24) {
                    Text("MY STATS")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    VStack(spacing: 20) {
                        HStack(spacing: 12) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.orange)
                            Text("\(streak) Day Streak")
                                .font(.system(size: 22, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                        }

                        HStack(spacing: 12) {
                            Image(systemName: "figure.run")
                                .font(.system(size: 22))
                                .foregroundColor(.blue)
                            Text("\(String(format: "%.2f", currentDistance)) mi Today")
                                .font(.system(size: 22, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                        }

                        HStack(spacing: 12) {
                            Image(systemName: "map.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.red)
                            Text("\(String(format: "%.1f", totalMiles)) mi Total")
                                .font(.system(size: 22, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                        }

                        HStack(spacing: 12) {
                            Image(systemName: "hare.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.green)
                            Text(fastestPace > 0 ? "\(paceString) /mi Best" : "No pace data")
                                .font(.system(size: 22, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                }

                Spacer()

                ShareCardFooter()
            }
            .padding(30)
        }
        .frame(width: 600, height: 750)
        .padding(8)
        .clipped()
    }
}

// MARK: - Shared Components

/// Reusable background for share cards
struct ShareCardBackground: View {
    let accentColor: Color
    let isDarkMode: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 80)
                .fill(isDarkMode ? Color.black.opacity(0.95) : Color.white.opacity(0.2))

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

            RoundedRectangle(cornerRadius: 80)
                .fill(Color.clear)
                .shadow(color: accentColor.opacity(0.7), radius: 40, x: 0, y: 0)
        }
    }
}

/// Reusable footer for share cards (MAD logo + slogan)
struct ShareCardFooter: View {
    var body: some View {
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
}

// MARK: - Glass Stat Row Component

struct GlassStatRow: View {
    let icon: String
    let text: String
    let color: Color
    let isDarkMode: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 24)

            Text(text)
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundColor(isDarkMode ? .white : .black)

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
