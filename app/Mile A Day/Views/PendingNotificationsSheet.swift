import SwiftUI

/// Standalone "share with friends?" stash sheet for ask-mode pending
/// notifications — partial walks, extra miles, and background-synced workouts
/// that didn't surface a celebration. Per-item Notify / dismiss, plus dismiss
/// all. Items expire at the user's local midnight (enforced server-side).
struct PendingNotificationsSheet: View {
	@ObservedObject private var service = PendingNotificationsService.shared
	@ObservedObject private var audience = AudienceSettingsService.shared
	@Environment(\.dismiss) private var dismiss

	@State private var busyIds: Set<String> = []

	var body: some View {
		ZStack {
			MADTheme.Colors.appBackgroundGradient
				.ignoresSafeArea()

			VStack(alignment: .leading, spacing: 0) {
				Capsule()
					.fill(Color.white.opacity(0.25))
					.frame(width: 36, height: 4)
					.frame(maxWidth: .infinity)
					.padding(.top, 10)
					.padding(.bottom, MADTheme.Spacing.md)

				Text("Share with friends?")
					.font(.system(size: 17, weight: .bold, design: .rounded))
					.foregroundColor(.white)
					.padding(.horizontal, MADTheme.Spacing.md)

				Text(subtitle)
					.font(.system(size: 11, weight: .regular, design: .rounded))
					.foregroundColor(.white.opacity(0.5))
					.padding(.horizontal, MADTheme.Spacing.md)
					.padding(.top, 2)

				ScrollView {
					VStack(spacing: MADTheme.Spacing.sm) {
						ForEach(service.pending) { item in
							pendingRow(item)
						}
					}
					.padding(MADTheme.Spacing.md)
				}

				if service.hasPending {
					Button {
						dismissAll()
					} label: {
						Text("Dismiss all")
							.font(.system(size: 13, weight: .medium, design: .rounded))
							.foregroundColor(.white.opacity(0.5))
							.frame(maxWidth: .infinity)
							.padding(.vertical, MADTheme.Spacing.sm)
					}
					.buttonStyle(.plain)
					.padding(.bottom, MADTheme.Spacing.lg)
				}
			}
		}
		.presentationDetents([.medium, .large])
		.presentationDragIndicator(.hidden)
		.onChange(of: service.hasPending) { _, hasPending in
			// Nothing left to act on — close the sheet.
			if !hasPending { dismiss() }
		}
		.task {
			// Ensure audience settings are present so we can label each item's
			// effective audience ("to Close Friends" etc.).
			await audience.loadIfNeeded()
		}
	}

	private var subtitle: String {
		let n = service.pending.count
		let noun = n == 1 ? "workout" : "workouts"
		return "\(n) pending \(noun) · sends to friends until midnight, then expires"
	}

	// MARK: - Row

	private func pendingRow(_ item: PendingFriendNotification) -> some View {
		let isBusy = busyIds.contains(item.id)
		return HStack(spacing: MADTheme.Spacing.sm) {
			ZStack {
				Circle().fill(Color.white.opacity(0.08)).frame(width: 38, height: 38)
				Image(systemName: icon(for: item))
					.font(.system(size: 16, weight: .semibold))
					.foregroundColor(.white.opacity(0.85))
			}

			VStack(alignment: .leading, spacing: 2) {
				Text(title(for: item))
					.font(.system(size: 13, weight: .semibold, design: .rounded))
					.foregroundColor(.white)
					.lineLimit(2)
				Text(subtitle(for: item))
					.font(.system(size: 10, weight: .regular, design: .rounded))
					.foregroundColor(.white.opacity(0.5))
					.lineLimit(1)
			}

			Spacer(minLength: 4)

			if isBusy {
				ProgressView().scaleEffect(0.7).tint(MADTheme.Colors.madRed)
					.frame(width: 64)
			} else {
				Button {
					notify(item)
				} label: {
					Text("Notify")
						.font(.system(size: 12, weight: .bold, design: .rounded))
						.foregroundColor(.white)
						.padding(.horizontal, 14)
						.padding(.vertical, 8)
						.background(Capsule().fill(MADTheme.Colors.madRed))
				}
				.buttonStyle(.plain)

				Button {
					decline(item)
				} label: {
					Image(systemName: "xmark")
						.font(.system(size: 11, weight: .bold))
						.foregroundColor(.white.opacity(0.55))
						.frame(width: 30, height: 30)
						.background(Circle().fill(Color.white.opacity(0.08)))
				}
				.buttonStyle(.plain)
			}
		}
		.padding(MADTheme.Spacing.md)
		.background(
			RoundedRectangle(cornerRadius: 14)
				.fill(Color.white.opacity(0.05))
				.overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
		)
	}

	// MARK: - Labels

	private func icon(for item: PendingFriendNotification) -> String {
		// Non-workout events get their own icon even when activity-tagged; only
		// workout-type events fall back to the run/walk glyph.
		switch item.eventType {
		case AudienceEventType.personalBest.rawValue: return "bolt.fill"
		case AudienceEventType.badgeEarned.rawValue: return "rosette"
		case AudienceEventType.challengeCompleted.rawValue: return "checkmark.seal.fill"
		case AudienceEventType.streakBroken.rawValue: return "flame"
		default:
			switch item.activityType {
			case "walk": return "figure.walk"
			case "run": return "figure.run"
			default: return "bell.fill"
			}
		}
	}

	private func title(for item: PendingFriendNotification) -> String {
		// Prefer the stored push title; fall back to the event display name.
		if let t = item.payload.title, !t.isEmpty { return t }
		return AudienceEventType(rawValue: item.eventType)?.displayName ?? "Activity"
	}

	private func subtitle(for item: PendingFriendNotification) -> String {
		let audienceLabel = resolvedAudienceLabel(for: item)
		if let body = item.payload.body, !body.isEmpty {
			return "\(body) · to \(audienceLabel)"
		}
		return "Pending · to \(audienceLabel)"
	}

	/// The effective outgoing audience for this item under current settings,
	/// as a friendly label. `ask`/`none` fall back to "friends" — the server
	/// caps the real send.
	private func resolvedAudienceLabel(for item: PendingFriendNotification) -> String {
		guard let event = AudienceEventType(rawValue: item.eventType) else { return "friends" }
		let activity = AudienceActivity(rawValue: item.activityType) ?? .none
		switch audience.resolve(direction: .outgoing, eventType: event, activity: activity) {
		case .close: return "Close Friends"
		case .all: return "All Friends"
		default: return "friends"
		}
	}

	// MARK: - Actions

	private func notify(_ item: PendingFriendNotification) {
		guard !busyIds.contains(item.id) else { return }
		busyIds.insert(item.id)
		UIImpactFeedbackGenerator(style: .medium).impactOccurred()
		Task {
			do {
				try await service.send(item)
				UINotificationFeedbackGenerator().notificationOccurred(.success)
			} catch {
				print("[PendingSheet] notify failed: \(error)")
				UINotificationFeedbackGenerator().notificationOccurred(.error)
			}
			await MainActor.run { _ = busyIds.remove(item.id) }
		}
	}

	private func decline(_ item: PendingFriendNotification) {
		guard !busyIds.contains(item.id) else { return }
		busyIds.insert(item.id)
		Task {
			do {
				try await service.dismiss(item)
			} catch {
				print("[PendingSheet] dismiss failed: \(error)")
			}
			await MainActor.run { _ = busyIds.remove(item.id) }
		}
	}

	private func dismissAll() {
		Task {
			do {
				_ = try await service.dismissAll()
			} catch {
				print("[PendingSheet] dismissAll failed: \(error)")
			}
		}
	}
}
