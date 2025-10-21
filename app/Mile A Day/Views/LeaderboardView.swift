import SwiftUI

struct LeaderboardView: View {
    @ObservedObject var userManager: UserManager
    @ObservedObject var healthManager: HealthKitManager
    @State private var selectedTab = 0
    @State private var showWorkoutDetail = false
    @State private var selectedUser: User?
    
    private let tabs = ["Streak", "Total Miles", "Fastest Pace", "Most in Day"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("Leaderboard Type", selection: $selectedTab) {
                ForEach(0..<tabs.count, id: \.self) { index in
                    Text(tabs[index]).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
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
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
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
    
    var body: some View {
        List {
            ForEach(Array(users.enumerated()), id: \.element.id) { index, user in
                Button {
                    if valueType == .mostMilesInDay || valueType == .fastestPace {
                        selectedUser = user
                        showDetail = true
                    }
                } label: {
                    LeaderboardRow(
                        rank: index + 1,
                        user: user,
                        value: valueType.getValue(from: user),
                        icon: valueType.icon,
                        iconColor: valueType.color,
                        isCurrentUser: user.name == "You"
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .listStyle(.plain)
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

struct LeaderboardRow: View {
    let rank: Int
    let user: User
    let value: String
    let icon: String
    let iconColor: Color
    let isCurrentUser: Bool
    
    var body: some View {
        HStack {
            // Rank
            Text("\(rank)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(width: 30)
            
            // Medal for top 3
            if rank <= 3 {
                Image(systemName: medalIcon(for: rank))
                    .foregroundColor(medalColor(for: rank))
            }
            
            // User name
            Text(user.name)
                .font(.headline)
                .fontWeight(isCurrentUser ? .bold : .regular)
                .foregroundColor(isCurrentUser ? .primary : .secondary)
            
            Spacer()
            
            // Value with icon
            HStack {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isCurrentUser ? Color("appPrimary").opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(isCurrentUser ? Color.secondary.opacity(0.05) : Color.clear)
    }
    
    private func medalIcon(for rank: Int) -> String {
        switch rank {
        case 1: return "medal.fill"
        case 2: return "medal.fill"
        case 3: return "medal.fill"
        default: return ""
        }
    }
    
    private func medalColor(for rank: Int) -> Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .brown
        default: return .clear
        }
    }
}

#Preview {
    NavigationStack {
        LeaderboardView(userManager: UserManager(), healthManager: HealthKitManager())
    }
} 