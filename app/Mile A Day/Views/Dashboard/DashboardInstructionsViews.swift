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

                        Text("Start a run in-app or log workouts from Apple Fitness — everything syncs automatically.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                }

                HStack(spacing: 10) {
                    Button {
                        showInstructions = true
                    } label: {
                        Text("Show me how")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(MADTheme.Colors.madRed.opacity(0.8))
                            )
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            hasSeenInstructions = true
                        }
                    } label: {
                        Text("Got it!")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.10))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                            )
                    }
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
                VStack(spacing: 22) {
                    heroHeader

                    stepsCard

                    proTipsCard
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

    private var heroHeader: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(
                    LinearGradient(
                        colors: [MADTheme.Colors.madRed, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Getting Started")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(MADTheme.Colors.primaryText)

            Text("Track your daily mile in a few easy steps")
                .font(MADTheme.Typography.body)
                .foregroundColor(MADTheme.Colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
    }

    private var stepsCard: some View {
        VStack(spacing: 10) {
            InstructionRow(
                number: 1,
                icon: "figure.run",
                color: MADTheme.Colors.madRed,
                title: "Run or walk a mile",
                description: "Start a workout right in Mile A Day, or log it from Apple Fitness, your Apple Watch, or any HealthKit-compatible app."
            )
            InstructionRow(
                number: 2,
                icon: "target",
                color: .green,
                title: "Hit your daily goal",
                description: "Cover at least one mile (or your custom goal). Multiple workouts in a day add up."
            )
            InstructionRow(
                number: 3,
                icon: "arrow.triangle.2.circlepath",
                color: .blue,
                title: "Open Mile A Day",
                description: "Your progress syncs automatically from HealthKit. Pull down on the dashboard to refresh."
            )
            InstructionRow(
                number: 4,
                icon: "flame.fill",
                color: .orange,
                title: "Build your streak",
                description: "Complete your goal every day to keep your streak alive. Tap your streak to share it with friends."
            )
            InstructionRow(
                number: 5,
                icon: "medal.fill",
                color: .purple,
                title: "Earn medals & compete",
                description: "Unlock medals for milestones, pin your favorites, and challenge friends in competitions."
            )
        }
    }

    private var proTipsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.yellow)
                Text("Pro Tips")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(MADTheme.Colors.primaryText)
            }

            VStack(spacing: 8) {
                TipRow(icon: "applewatch", color: .blue, text: "Apple Watch workouts sync automatically.")
                TipRow(icon: "widget.small", color: .purple, text: "Add widgets to your Home Screen for at-a-glance stats.")
                TipRow(icon: "gearshape.fill", color: .gray, text: "Tap the gear icon on the dashboard to change your daily goal.")
                TipRow(icon: "person.2.fill", color: .green, text: "Add friends to compete and stay motivated.")
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
                                colors: [Color.yellow.opacity(0.25), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
}

/// A single instruction row: number badge + inline icon + title on one line, description below.
struct InstructionRow: View {
    let number: Int
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                // Numbered badge
                Text("\(number)")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [color, color.opacity(0.75)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: color.opacity(0.4), radius: 4, x: 0, y: 2)
                    )

                // Inline icon
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 20, alignment: .leading)

                // Title (same row as icon)
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(MADTheme.Colors.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)
            }

            Text(description)
                .font(.system(size: 13))
                .foregroundColor(MADTheme.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
                .padding(.leading, 32) // align under the title, past badge + icon
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(color.opacity(0.22), lineWidth: 1)
                )
        )
    }
}

/// Compact pro-tip row with inline icon and text.
struct TipRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(color.opacity(0.15))
                )

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(MADTheme.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
