import SwiftUI

/// Instagram-style triple stat row for profile headers: Streak · Miles ·
/// Friends. The Friends cell is tappable and pushes the supplied destination
/// (the friends list); the other two are read-only.
struct ProfileStatsRow<FriendsDestination: View>: View {
    let streak: Int
    let totalMiles: Double
    /// nil renders a placeholder dash until the count loads.
    let friendCount: Int?
    @ViewBuilder var friendsDestination: () -> FriendsDestination

    var body: some View {
        HStack(spacing: 0) {
            cell(value: "\(streak)", label: "Streak")
            divider
            cell(value: milesText, label: "Miles")
            divider
            NavigationLink(destination: friendsDestination()) {
                cell(
                    value: friendCount.map(String.init) ?? "—",
                    label: friendCount == 1 ? "Friend" : "Friends"
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.2), value: friendCount)
    }

    private func cell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.4)
                .foregroundColor(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 28)
    }

    private var milesText: String {
        if totalMiles >= 1000 {
            return String(format: "%.0f", totalMiles)
        } else if totalMiles >= 100 {
            return String(format: "%.0f", totalMiles)
        } else {
            return String(format: "%.1f", totalMiles)
        }
    }
}
