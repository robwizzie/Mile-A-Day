import SwiftUI

struct CompetitionsView: View {
    var body: some View {
        ZStack {
            // Gradient background
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea(.all)
            
            ScrollView {
                VStack(spacing: 24) {
                    // Coming soon header
                    VStack(spacing: 16) {
                        Image(systemName: "trophy.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(red: 217/255, green: 64/255, blue: 63/255), .orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color(red: 217/255, green: 64/255, blue: 63/255).opacity(0.3), radius: 20, x: 0, y: 10)

                        Text("Competitions")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("Coming Soon")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.top, 60)

                    // Feature preview cards
                    VStack(spacing: 16) {
                        FeaturePreviewCard(
                            icon: "person.2.fill",
                            title: "Challenge Your Friends",
                            description: "Compete with friends to see who can maintain the longest streak or run the most miles"
                        )

                        FeaturePreviewCard(
                            icon: "chart.bar.fill",
                            title: "Leaderboards",
                            description: "Climb the ranks and see how you stack up against other runners"
                        )

                        FeaturePreviewCard(
                            icon: "medal.fill",
                            title: "Weekly Challenges",
                            description: "Join community challenges and earn exclusive badges"
                        )
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
        }
        .navigationTitle("Competitions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackgroundVisibility(.automatic, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

// MARK: - Feature Preview Card
struct FeaturePreviewCard: View {
    let icon: String
    let title: String
    let description: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(Color(red: 217/255, green: 64/255, blue: 63/255))
                .frame(width: 50, height: 50)
                .background(
                    Circle()
                        .fill(Color(red: 217/255, green: 64/255, blue: 63/255).opacity(0.1))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding()
        .background(
            ZStack {
                // Liquid glass background
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.2 : 0.3),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    NavigationStack {
        CompetitionsView()
    }
}
