import SwiftUI

struct LeaderboardView: View {
    @ObservedObject var userManager: UserManager
    @ObservedObject var healthManager: HealthKitManager
    @State private var selectedTab = 0
    @State private var showWorkoutDetail = false
    @State private var selectedUser: User?

    private let tabs: [(String, String)] = [
        ("Streak", "flame.fill"),
        ("Total Miles", "map.fill"),
        ("Fastest Pace", "hare.fill"),
        ("Most in Day", "calendar.badge.clock")
    ]

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom scrolling tab selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(0..<tabs.count, id: \.self) { index in
                            LeaderboardTabButton(
                                title: tabs[index].0,
                                icon: tabs[index].1,
                                isSelected: selectedTab == index
                            ) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    selectedTab = index
                                }
                            }
                        }
                    }
                    .padding(.horizontal, MADTheme.Spacing.md)
                    .padding(.vertical, MADTheme.Spacing.sm)
                }

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
    }
}

// MARK: - Leaderboard Tab Button

struct LeaderboardTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(isSelected ? MADTheme.Colors.madRed : Color.white.opacity(0.06))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? MADTheme.Colors.madRed.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
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
    @State private var animateRows = false

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
                                valueIcon: valueType.icon,
                                valueColor: valueType.color,
                                isCurrentUser: user.name == "You"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .opacity(animateRows ? 1 : 0)
                        .offset(y: animateRows ? 0 : 20)
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.08),
                            value: animateRows
                        )
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
                if !remainingUsers.isEmpty {
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
                                    valueIcon: valueType.icon,
                                    valueColor: valueType.color,
                                    isCurrentUser: item.user.name == "You"
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .opacity(animateRows ? 1 : 0)
                            .offset(y: animateRows ? 0 : 15)
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.8).delay(0.24 + Double(item.index - 3) * 0.05),
                                value: animateRows
                            )
                        }
                    }
                    .padding(.horizontal, MADTheme.Spacing.lg)
                    .padding(.bottom, MADTheme.Spacing.xl)
                }
            }
        }
        .onAppear {
            animateRows = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                animateRows = true
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
    @State private var podiumAnimated = false

    var body: some View {
        HStack(alignment: .bottom, spacing: MADTheme.Spacing.md) {
            // Second place (left)
            podiumSlot(
                user: second,
                rank: 2,
                avatarSize: 56,
                colors: [Color(white: 0.85), Color(white: 0.6)],
                pedestalHeight: 70
            )
            .offset(y: 20)

            // First place (center)
            VStack(spacing: MADTheme.Spacing.xs) {
                // Crown with glow
                ZStack {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.yellow, Color.orange],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .yellow.opacity(0.4), radius: 6)
                }

                podiumSlot(
                    user: first,
                    rank: 1,
                    avatarSize: 66,
                    colors: [Color.yellow, Color.orange],
                    pedestalHeight: 100
                )
            }

            // Third place (right)
            podiumSlot(
                user: third,
                rank: 3,
                avatarSize: 56,
                colors: [Color(red: 0.8, green: 0.5, blue: 0.2), Color(red: 0.6, green: 0.35, blue: 0.15)],
                pedestalHeight: 55
            )
            .offset(y: 30)
        }
        .padding(.horizontal, MADTheme.Spacing.lg)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.65)) {
                    podiumAnimated = true
                }
            }
        }
    }

    private func podiumSlot(user: User, rank: Int, avatarSize: CGFloat, colors: [Color], pedestalHeight: CGFloat) -> some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            // Avatar
            ZStack {
                // Glow behind avatar
                if rank == 1 {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [colors[0].opacity(0.3), Color.clear],
                                center: .center,
                                startRadius: avatarSize * 0.3,
                                endRadius: avatarSize * 0.8
                            )
                        )
                        .frame(width: avatarSize + 20, height: avatarSize + 20)
                }

                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: avatarSize, height: avatarSize)
                    .overlay(
                        Text(user.name.prefix(1).uppercased())
                            .font(.system(size: avatarSize * 0.35, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: colors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: rank == 1 ? 3 : 2.5
                            )
                    )
                    .shadow(color: colors[0].opacity(0.3), radius: 8, y: 4)
            }

            // Name
            Text(user.name)
                .font(.system(size: rank == 1 ? 14 : 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)

            // Value
            Text(valueType.getValue(from: user))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))

            // Pedestal
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [colors[0].opacity(0.25), colors[1].opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: podiumAnimated ? pedestalHeight : 0)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            LinearGradient(colors: colors.map { $0.opacity(0.3) }, startPoint: .top, endPoint: .bottom),
                            lineWidth: 1
                        )
                )
                .overlay(
                    Text("\(rank)")
                        .font(.system(size: pedestalHeight * 0.4, weight: .bold, design: .rounded))
                        .foregroundColor(colors[0].opacity(0.2))
                )
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Top Three Row

struct TopThreeRow: View {
    let rank: Int
    let user: User
    let value: String
    let valueIcon: String
    let valueColor: Color
    let isCurrentUser: Bool

    var rankGradient: [Color] {
        switch rank {
        case 1: return [.yellow, .orange]
        case 2: return [Color(white: 0.85), Color(white: 0.6)]
        case 3: return [Color(red: 0.8, green: 0.5, blue: 0.2), Color(red: 0.6, green: 0.35, blue: 0.15)]
        default: return [.clear]
        }
    }

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            // Rank badge
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: rankGradient.map { $0.opacity(0.2) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)
                Text("\(rank)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: rankGradient, startPoint: .top, endPoint: .bottom)
                    )
            }

            // Avatar
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(user.name.prefix(1).uppercased())
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(colors: rankGradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 2
                        )
                )

            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                if isCurrentUser {
                    Text("You")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(MADTheme.Colors.madRed)
                }
            }

            Spacer()

            // Value with icon
            HStack(spacing: 5) {
                Image(systemName: valueIcon)
                    .font(.system(size: 11))
                    .foregroundColor(valueColor.opacity(0.7))
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(isCurrentUser ? 0.08 : 0.0))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .stroke(
                            isCurrentUser
                                ? MADTheme.Colors.primary.opacity(0.5)
                                : (rank == 1 ? rankGradient.first?.opacity(0.15) ?? Color.clear : Color.clear),
                            lineWidth: isCurrentUser ? 1.5 : 1
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
    let valueIcon: String
    let valueColor: Color
    let isCurrentUser: Bool

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            // Rank number
            Text("\(rank)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 30)

            // Avatar
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(user.name.prefix(1).uppercased())
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )

            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                if isCurrentUser {
                    Text("You")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(MADTheme.Colors.madRed)
                }
            }

            Spacer()

            // Value with icon
            HStack(spacing: 5) {
                Image(systemName: valueIcon)
                    .font(.system(size: 11))
                    .foregroundColor(valueColor.opacity(0.5))
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(isCurrentUser ? 0.06 : 0.0))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .stroke(
                            isCurrentUser ? MADTheme.Colors.primary.opacity(0.4) : Color.clear,
                            lineWidth: 1.5
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
