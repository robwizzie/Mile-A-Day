import SwiftUI

/// Preferences for the daily challenge system — currently the Head-to-Head
/// rival pool. The close-friends-only toggle is server-authoritative
/// (`h2h_close_friends_only` on /notifications/preferences): matchmaking
/// happens backend-side, so the value is loaded fresh here rather than from
/// the UserDefaults-backed NotificationPreferences.
struct DailyChallengeSettingsView: View {
    @ObservedObject var friendService: FriendService
    @ObservedObject private var closeFriendsService = CloseFriendsService.shared

    @State private var closeFriendsOnly = false
    @State private var hasLoaded = false
    @State private var saveError: String?

    /// The toggle is only enableable with at least one close friend — with an
    /// empty close list the rival pool would be empty and the server rejects
    /// the update (400 no_close_friends).
    private var hasCloseFriends: Bool {
        !closeFriendsService.closeFriendIds.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                headToHeadSection
            }
            .padding(MADTheme.Spacing.md)
        }
        .background(MADTheme.Colors.appBackgroundGradient)
        .navigationTitle("Daily Challenges")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await closeFriendsService.loadIfNeeded()
            await loadCurrentPreference()
        }
    }

    private var headToHeadSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "flag.2.crossed.fill")
                    .madFont(size: 11, weight: .semibold, maxScale: 1.5)
                    .foregroundColor(MADTheme.Colors.madRed)

                Text("HEAD-TO-HEAD")
                    .madFont(size: 12, design: .rounded)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .tracking(0.5)
            }

            VStack(alignment: .leading, spacing: 2) {
                Toggle("Rivals from close friends only", isOn: $closeFriendsOnly)
                    .madFont(size: 17, design: .rounded)
                    .tint(MADTheme.Colors.madRed)
                    .disabled(!hasLoaded || (!hasCloseFriends && !closeFriendsOnly))
                    .onChange(of: closeFriendsOnly) { oldValue, newValue in
                        guard hasLoaded else { return }
                        savePreference(newValue, revertTo: oldValue)
                    }

                Text(
                    hasCloseFriends || closeFriendsOnly
                        ? "Head-to-Head matchups will only pull rivals from your close friends. Applies starting with your next matchup."
                        : "Add at least one close friend to unlock this."
                )
                .madFont(size: 11, design: .rounded)
                .foregroundColor(.white.opacity(0.6))
                .padding(.leading, 2)

                if let saveError {
                    Text(saveError)
                        .madFont(size: 11, design: .rounded)
                        .foregroundColor(.orange)
                        .padding(.leading, 2)
                        .padding(.top, 2)
                }
            }

            Divider().overlay(Color.white.opacity(0.06))

            NavigationLink(destination: CloseFriendsListView(friendService: friendService)) {
                HStack {
                    Image(systemName: "star.fill")
                        .madFont(size: 13, weight: .semibold, maxScale: 1.5)
                        .foregroundColor(.yellow)
                    Text("Manage Close Friends")
                        .madFont(size: 17, design: .rounded)
                        .foregroundColor(.primary)
                    Spacer()
                    if closeFriendsService.hasLoadedOnce {
                        Text("\(closeFriendsService.closeFriendIds.count)")
                            .madFont(size: 13, weight: .semibold, design: .rounded)
                            .foregroundColor(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .madFont(size: 12, weight: .semibold, maxScale: 1.5)
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    // MARK: - Backend sync

    private func loadCurrentPreference() async {
        do {
            let settings = try await friendService.getNotificationSettings()
            closeFriendsOnly = settings.h2h_close_friends_only ?? false
            // Free hydration point for the Stealth window log (server wins).
            StealthModeStore.shared.apply(settings)
        } catch {
            print("[ChallengeSettings] Failed to load preference: \(error)")
        }
        hasLoaded = true
    }

    private func savePreference(_ newValue: Bool, revertTo oldValue: Bool) {
        saveError = nil
        MADHaptics.tap()
        Task {
            do {
                _ = try await friendService.updateNotificationSettings([
                    "h2h_close_friends_only": newValue
                ])
            } catch {
                // Server refused (e.g. close list emptied on another device) —
                // put the switch back where it was.
                closeFriendsOnly = oldValue
                saveError = "Couldn't save — add a close friend first."
                print("[ChallengeSettings] Failed to save preference: \(error)")
            }
        }
    }
}
