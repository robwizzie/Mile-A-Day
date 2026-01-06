import SwiftUI

struct LeaderboardView: View {
    @ObservedObject var userManager: UserManager
    @ObservedObject var healthManager: HealthKitManager
    @State private var selectedTab = 0
    @State private var showWorkoutDetail = false
    @State private var selectedUser: User?

    private let tabs = ["Streak", "Total Miles", "Fastest Pace", "Most in Day"]

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Tab selector
                Picker("Leaderboard Type", selection: $selectedTab) {
                    ForEach(0..<tabs.count, id: \.self) { index in
                        Text(tabs[index]).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .colorMultiply(MADTheme.Colors.primary)

                // Leaderboard content
                TabView(selection: $selectedTab) {
                    LeaderboardList(users: userManager.getLeaderboardByStreak(), valueType: .streak, healthManager: healthManager)
                        .tag(0)

                    LeaderboardList(users: userManager.getLeaderboardByTotalMiles(), valueType: .totalMiles, healthManager: healthManager)
                        .tag(1)

                    LeaderboardList(users: userManager.getLeaderboardByPersonalRecord(), valueType: .fastestPace, healthManager: healthManager)
                        .tag(2)

                    LeaderboardList(users: userManager.getLeaderboardByMostMilesInDay(), valueType: .mostMilesInDay, healthManager: healthManager)
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: selectedTab)
            }
        }
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

enum LeaderboardValueType {
    case streak, totalMiles, fastestPace, mostMilesInDay
    
    func getValue(from user: User) -> String {
        switch self {
        case .streak:
            return "\(user.streak) \(user.streak == 1 ? "day" : "days")"
        case .totalMiles:
            return user.totalMiles.milesFormatted
        case .fastestPace:
            if user.fastestMilePace > 0 {
                let totalMinutes = user.fastestMilePace
                let minutes = Int(totalMinutes)
                let seconds = Int((totalMinutes - Double(minutes)) * 60)
                return String(format: "%d:%02d /mi", minutes, seconds)
            } else {
                return "N/A"
            }
        case .mostMilesInDay:
            return user.mostMilesInOneDay.milesFormatted
        }
    }
    
    var icon: String {
        switch self {
        case .streak:
            return "flame.fill"
        case .totalMiles:
            return "map.fill"
        case .fastestPace:
            return "hare.fill"
        case .mostMilesInDay:
            return "calendar.badge.clock"
        }
    }
    
    var color: Color {
        switch self {
        case .streak:
            return .orange
        case .totalMiles:
            return .blue
        case .fastestPace:
            return .green
        case .mostMilesInDay:
            return .purple
        }
    }
}

struct LeaderboardList: View {
    let users: [User]
    let valueType: LeaderboardValueType
    @ObservedObject var healthManager: HealthKitManager
    @State private var selectedUser: User?
    @State private var showDetail = false

    var topThree: [User] {
        Array(users.prefix(3))
    }

    var remainingUsers: [(index: Int, user: User)] {
        Array(users.enumerated()).dropFirst(3).map { (index: $0.offset, user: $0.element) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: MADTheme.Spacing.xl) {
                // Podium for top 3
                if topThree.count >= 3 {
                    PodiumView(
                        first: topThree[0],
                        second: topThree[1],
                        third: topThree[2],
                        valueType: valueType
                    )
                    .padding(.top, MADTheme.Spacing.lg)
                }

                // Top 3 card section
                VStack(spacing: MADTheme.Spacing.sm) {
                    ForEach(Array(topThree.enumerated()), id: \.element.id) { index, user in
                        Button {
                            if valueType == .mostMilesInDay || valueType == .fastestPace {
                                selectedUser = user
                                showDetail = true
                            }
                        } label: {
                            TopThreeRow(
                                rank: index + 1,
                                user: user,
                                value: valueType.getValue(from: user),
                                isCurrentUser: user.name == "You"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, MADTheme.Spacing.lg)
                .padding(.vertical, MADTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            MADTheme.Colors.primary.opacity(0.3),
                                            Color.clear
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
                .padding(.horizontal, MADTheme.Spacing.lg)

                // Remaining positions
                VStack(spacing: MADTheme.Spacing.sm) {
                    ForEach(remainingUsers, id: \.user.id) { item in
                        Button {
                            if valueType == .mostMilesInDay || valueType == .fastestPace {
                                selectedUser = item.user
                                showDetail = true
                            }
                        } label: {
                            RegularLeaderboardRow(
                                rank: item.index + 1,
                                user: item.user,
                                value: valueType.getValue(from: item.user),
                                isCurrentUser: item.user.name == "You"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, MADTheme.Spacing.lg)
                .padding(.bottom, MADTheme.Spacing.xl)
            }
        }
        .sheet(isPresented: $showDetail, content: {
            if let user = selectedUser {
                switch valueType {
                case .fastestPace:
                    FastestPaceDetailView(healthManager: healthManager)
                case .mostMilesInDay:
                    MostMilesDetailView(miles: user.mostMilesInOneDay, healthManager: healthManager)
                default:
                    EmptyView()
                }
            }
        })
    }
}

// MARK: - Podium View

struct PodiumView: View {
    let first: User
    let second: User
    let third: User
    let valueType: LeaderboardValueType

    var body: some View {
        HStack(alignment: .bottom, spacing: MADTheme.Spacing.md) {
            // Second place (left)
            VStack(spacing: MADTheme.Spacing.sm) {
                // Avatar with position badge
                ZStack(alignment: .top) {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Text(second.name.prefix(1).uppercased())
                                .font(MADTheme.Typography.title3)
                                .foregroundColor(.white)
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.gray.opacity(0.8), Color.gray.opacity(0.4)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 3
                                )
                        )

                    // Position badge
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.gray.opacity(0.8), Color.gray.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 24, height: 24)
                        .overlay(
                            Text("2")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .offset(y: -8)
                }

                Text(second.name)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.white)
                    .lineLimit(1)

                // Podium block
                VStack {
                    Spacer()
                    Text("2")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 80, height: 80)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [
                                    MADTheme.Colors.madRed.opacity(0.7),
                                    MADTheme.Colors.madRed.opacity(0.5)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
            }
            .offset(y: 20)

            // First place (center)
            VStack(spacing: MADTheme.Spacing.sm) {
                // Crown
                Image(systemName: "crown.fill")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.yellow, Color.orange],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Avatar with position badge
                ZStack(alignment: .top) {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 70, height: 70)
                        .overlay(
                            Text(first.name.prefix(1).uppercased())
                                .font(MADTheme.Typography.title2)
                                .foregroundColor(.white)
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.yellow, Color.orange],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 3
                                )
                        )

                    // Position badge
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.yellow, Color.orange],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text("1")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .offset(y: -8)
                }

                Text(first.name)
                    .font(MADTheme.Typography.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)

                // Podium block
                VStack {
                    Spacer()
                    Text("1")
                        .font(.system(size: 50, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 90, height: 110)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [
                                    MADTheme.Colors.madRed.opacity(0.9),
                                    MADTheme.Colors.madRed.opacity(0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
            }

            // Third place (right)
            VStack(spacing: MADTheme.Spacing.sm) {
                // Avatar with position badge
                ZStack(alignment: .top) {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Text(third.name.prefix(1).uppercased())
                                .font(MADTheme.Typography.title3)
                                .foregroundColor(.white)
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.brown.opacity(0.8), Color.brown.opacity(0.4)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 3
                                )
                        )

                    // Position badge
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.brown.opacity(0.8), Color.brown.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 24, height: 24)
                        .overlay(
                            Text("3")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .offset(y: -8)
                }

                Text(third.name)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.white)
                    .lineLimit(1)

                // Podium block
                VStack {
                    Spacer()
                    Text("3")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 80, height: 70)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [
                                    MADTheme.Colors.madRed.opacity(0.6),
                                    MADTheme.Colors.madRed.opacity(0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
            }
            .offset(y: 30)
        }
        .padding(.horizontal, MADTheme.Spacing.lg)
    }
}

// MARK: - Top Three Row

struct TopThreeRow: View {
    let rank: Int
    let user: User
    let value: String
    let isCurrentUser: Bool

    var medalColor: Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .brown
        default: return .clear
        }
    }

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            // Medal icon
            Image(systemName: "medal.fill")
                .font(.title3)
                .foregroundColor(medalColor)
                .frame(width: 30)

            // Avatar
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(user.name.prefix(1).uppercased())
                        .font(MADTheme.Typography.callout)
                        .foregroundColor(.white)
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )

            // Name
            Text(user.name)
                .font(MADTheme.Typography.headline)
                .foregroundColor(.white)

            Spacer()

            // Value
            Text(value)
                .font(MADTheme.Typography.callout)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(isCurrentUser ? 0.1 : 0.0))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .stroke(
                            isCurrentUser ? MADTheme.Colors.primary : Color.clear,
                            lineWidth: 2
                        )
                )
        )
    }
}

// MARK: - Regular Leaderboard Row

struct RegularLeaderboardRow: View {
    let rank: Int
    let user: User
    let value: String
    let isCurrentUser: Bool

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            // Rank number
            Text("\(rank)")
                .font(MADTheme.Typography.headline)
                .fontWeight(.bold)
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 30)

            // Avatar
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(user.name.prefix(1).uppercased())
                        .font(MADTheme.Typography.callout)
                        .foregroundColor(.white)
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )

            // Name
            Text(user.name)
                .font(MADTheme.Typography.headline)
                .foregroundColor(.white)

            Spacer()

            // Value
            Text(value)
                .font(MADTheme.Typography.callout)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(isCurrentUser ? 0.05 : 0.0))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .stroke(
                            isCurrentUser ? MADTheme.Colors.primary : Color.clear,
                            lineWidth: 2
                        )
                )
        )
    }
}

#Preview {
    NavigationStack {
        LeaderboardView(userManager: UserManager(), healthManager: HealthKitManager())
    }
} 