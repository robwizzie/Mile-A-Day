import SwiftUI

// MARK: - Instructions Banner

struct InstructionsBanner: View {
    @Binding var showInstructions: Bool
    @AppStorage("hasSeenInstructions") private var hasSeenInstructions = false

    var body: some View {
        if !hasSeenInstructions {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [MADTheme.Colors.madRed, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Welcome to Mile A Day!")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("Start a run in-app or log workouts from Apple Fitness. Tap the ")
                            + Text(Image(systemName: "info.circle"))
                                .foregroundColor(.white.opacity(0.7))
                            + Text(" icon anytime for help.")
                    }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        hasSeenInstructions = true
                    }
                } label: {
                    Text("Got it!")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(MADTheme.Colors.madRed.opacity(0.8))
                        )
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
    }
}

// MARK: - Instructions View

struct InstructionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // Hero header
                    VStack(spacing: 12) {
                        Image(systemName: "figure.run.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [MADTheme.Colors.madRed, .orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Text("Getting Started")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(MADTheme.Colors.primaryText)

                        Text("Track your daily mile in a few easy steps")
                            .font(MADTheme.Typography.body)
                            .foregroundColor(MADTheme.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity)

                    // Steps
                    VStack(spacing: 0) {
                        InstructionStep(
                            number: "1",
                            title: "Go for a Run or Walk",
                            description: "Start a workout right in Mile A Day, use Apple Fitness, your Apple Watch, or any HealthKit-compatible app to record a workout.",
                            icon: "figure.run",
                            color: MADTheme.Colors.madRed,
                            isLast: false
                        )

                        InstructionStep(
                            number: "2",
                            title: "Hit Your Daily Goal",
                            description: "Walk or run at least one mile (or your custom goal). Any combo of workouts in a day counts!",
                            icon: "target",
                            color: .green,
                            isLast: false
                        )

                        InstructionStep(
                            number: "3",
                            title: "Open Mile A Day",
                            description: "Your progress syncs automatically from HealthKit. Pull down to refresh anytime.",
                            icon: "arrow.triangle.2.circlepath",
                            color: .blue,
                            isLast: false
                        )

                        InstructionStep(
                            number: "4",
                            title: "Build Your Streak",
                            description: "Complete your goal every day to keep your streak alive. Tap your streak to share cards with friends!",
                            icon: "flame.fill",
                            color: .orange,
                            isLast: false
                        )

                        InstructionStep(
                            number: "5",
                            title: "Earn Medals & Compete",
                            description: "Unlock medals for milestones, challenge friends in competitions, and climb the leaderboard.",
                            icon: "medal.fill",
                            color: .purple,
                            isLast: true
                        )
                    }
                    .padding(MADTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(colorScheme == .dark ? 0.15 : 0.3),
                                                Color.clear
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)

                    // Pro tips section
                    VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.yellow)
                            Text("Pro Tips")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(MADTheme.Colors.primaryText)
                        }

                        VStack(spacing: 10) {
                            TipItem(icon: "applewatch", text: "Apple Watch workouts sync automatically", color: .blue)
                            TipItem(icon: "widget.small", text: "Add widgets to your Home Screen for quick stats", color: .purple)
                            TipItem(icon: "gearshape.fill", text: "Customize your daily goal from the stats section", color: .gray)
                            TipItem(icon: "person.2.fill", text: "Add friends to compete and stay motivated", color: .green)
                        }
                    }
                    .padding(MADTheme.Spacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.yellow.opacity(0.2),
                                                Color.clear
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
                }
                .padding(.horizontal, MADTheme.Spacing.lg)
                .padding(.bottom, MADTheme.Spacing.xl)
            }
            .background(MADTheme.Colors.secondaryBackground)
            .navigationTitle("Instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(MADTheme.Colors.madRed)
                }
            }
        }
    }
}

struct InstructionStep: View {
    let number: String
    let title: String
    let description: String
    let icon: String
    let color: Color
    var isLast: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Timeline column - fixed width for consistent alignment
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 36, height: 36)
                        .shadow(color: color.opacity(0.3), radius: 4, x: 0, y: 2)

                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }

                if !isLast {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.4), color.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 36)

            // Content — top of title aligns with top of circle via shared .top alignment
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(MADTheme.Colors.primaryText)
                    .frame(minHeight: 36, alignment: .leading)

                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(MADTheme.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .padding(.bottom, isLast ? 0 : 20)
        }
    }
}

struct TipItem: View {
    var icon: String = "lightbulb.fill"
    let text: String
    var color: Color = .yellow

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
                .frame(width: 24, alignment: .center)

            Text(text)
                .font(.system(size: 14))
                .foregroundColor(MADTheme.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
