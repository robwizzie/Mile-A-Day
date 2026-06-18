import SwiftUI

/// Manage the user's private close-friends list: see who's on it, remove people,
/// and add accepted friends who aren't on it yet. The list is one-directional
/// and private — the other person is never told they were added.
struct CloseFriendsListView: View {
	@ObservedObject var friendService: FriendService
	@ObservedObject private var closeFriends = CloseFriendsService.shared
	@Environment(\.dismiss) private var dismiss

	@State private var busyIds: Set<String> = []

	/// Accepted friends not yet on the close list, sorted by display name.
	private var addableFriends: [BackendUser] {
		friendService.friends
			.filter { !closeFriends.closeFriendIds.contains($0.user_id) }
			.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
	}

	private var closeFriendsList: [BackendUser] {
		closeFriends.closeFriends
			.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
	}

	var body: some View {
		ZStack {
			MADTheme.Colors.appBackgroundGradient
				.ignoresSafeArea()

			ScrollView {
				VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
					privacyNote

					if closeFriends.isLoading && !closeFriends.hasLoadedOnce {
						loadingState
					} else {
						currentSection
						addSection
					}
				}
				.padding(MADTheme.Spacing.md)
			}
			.refreshable {
				try? await closeFriends.load()
			}
		}
		.navigationTitle("Close Friends")
		.navigationBarTitleDisplayMode(.inline)
		.toolbarColorScheme(.dark, for: .navigationBar)
		.toolbar {
			ToolbarItem(placement: .confirmationAction) {
				Button("Done") { dismiss() }
					.foregroundColor(MADTheme.Colors.madRed)
					.fontWeight(.semibold)
			}
		}
		.task {
			await closeFriends.loadIfNeeded()
		}
	}

	// MARK: - Sections

	private var privacyNote: some View {
		HStack(alignment: .top, spacing: MADTheme.Spacing.sm) {
			Image(systemName: "lock.fill")
				.font(.system(size: 13, weight: .bold))
				.foregroundColor(.yellow)
			Text("Your close friends list is private. People are never told when you add or remove them. Use it to share activity with a smaller circle.")
				.font(.system(size: 12, weight: .medium, design: .rounded))
				.foregroundColor(.white.opacity(0.6))
				.fixedSize(horizontal: false, vertical: true)
		}
		.padding(MADTheme.Spacing.md)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(
			RoundedRectangle(cornerRadius: 14)
				.fill(Color.yellow.opacity(0.06))
				.overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.yellow.opacity(0.18), lineWidth: 1))
		)
	}

	@ViewBuilder
	private var currentSection: some View {
		sectionHeader("CLOSE FRIENDS", count: closeFriendsList.count)
		if closeFriendsList.isEmpty {
			emptyRow("No close friends yet. Add some below.")
		} else {
			VStack(spacing: MADTheme.Spacing.sm) {
				ForEach(closeFriendsList) { friend in
					friendRow(friend, isClose: true)
				}
			}
		}
	}

	@ViewBuilder
	private var addSection: some View {
		if !addableFriends.isEmpty {
			sectionHeader("ADD FRIENDS", count: addableFriends.count)
			VStack(spacing: MADTheme.Spacing.sm) {
				ForEach(addableFriends) { friend in
					friendRow(friend, isClose: false)
				}
			}
		} else if !closeFriendsList.isEmpty {
			// Everyone is already a close friend.
			emptyRow("All your friends are close friends.")
		}
	}

	// MARK: - Rows

	private func friendRow(_ friend: BackendUser, isClose: Bool) -> some View {
		let isBusy = busyIds.contains(friend.user_id)
		return HStack(spacing: MADTheme.Spacing.md) {
			ProfileImageView(user: friend, size: 44)

			VStack(alignment: .leading, spacing: 2) {
				Text(friend.username ?? friend.displayName)
					.font(.system(size: 14, weight: .semibold))
					.foregroundColor(.white)
					.lineLimit(1)
				if friend.displayName != (friend.username ?? "") {
					Text(friend.displayName)
						.font(.system(size: 12, weight: .regular))
						.foregroundColor(.white.opacity(0.5))
						.lineLimit(1)
				}
			}

			Spacer(minLength: 4)

			Button {
				toggle(friend)
			} label: {
				Group {
					if isBusy {
						ProgressView().scaleEffect(0.6).tint(.yellow)
					} else {
						Image(systemName: isClose ? "star.fill" : "star")
							.font(.system(size: 16, weight: .bold))
							.foregroundColor(isClose ? .yellow : .white.opacity(0.4))
					}
				}
				.frame(width: 36, height: 36)
				.background(Circle().fill(Color.white.opacity(0.06)))
				.contentShape(Circle())
			}
			.buttonStyle(.plain)
			.disabled(isBusy)
		}
		.padding(MADTheme.Spacing.md)
		.background(
			RoundedRectangle(cornerRadius: 14)
				.fill(Color.white.opacity(0.04))
				.overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
		)
	}

	private func sectionHeader(_ title: String, count: Int) -> some View {
		HStack {
			Text(title)
				.font(.system(size: 11, weight: .heavy, design: .rounded))
				.tracking(1.0)
				.foregroundColor(.white.opacity(0.5))
			Spacer()
			Text("\(count)")
				.font(.system(size: 11, weight: .bold, design: .rounded))
				.foregroundColor(.white.opacity(0.4))
		}
		.padding(.horizontal, 4)
	}

	private func emptyRow(_ message: String) -> some View {
		Text(message)
			.font(.system(size: 13, weight: .medium, design: .rounded))
			.foregroundColor(.white.opacity(0.4))
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(MADTheme.Spacing.md)
	}

	private var loadingState: some View {
		VStack(spacing: MADTheme.Spacing.md) {
			ProgressView().tint(MADTheme.Colors.madRed)
			Text("Loading…")
				.font(.system(size: 13, weight: .medium, design: .rounded))
				.foregroundColor(.white.opacity(0.5))
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, MADTheme.Spacing.xl)
	}

	// MARK: - Actions

	private func toggle(_ friend: BackendUser) {
		guard !busyIds.contains(friend.user_id) else { return }
		busyIds.insert(friend.user_id)
		UIImpactFeedbackGenerator(style: .light).impactOccurred()
		Task {
			do {
				try await closeFriends.toggle(friend)
			} catch {
				print("[CloseFriendsList] toggle failed: \(error)")
				UINotificationFeedbackGenerator().notificationOccurred(.error)
			}
			await MainActor.run { _ = busyIds.remove(friend.user_id) }
		}
	}
}
