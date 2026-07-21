import SwiftUI

/// Per-event-type notification audience controls (the approved "Variant B"
/// mockup). A hero default selector drives every activity below it via the
/// cascade; per-activity cards let the user override individual events, with
/// run/walk splits for workout-type events. Sharing|Incoming tabs mirror the
/// same matrix (Incoming has no "Ask").
struct FriendActivitySettingsView: View {
	@ObservedObject private var audience = AudienceSettingsService.shared

	@State private var direction: AudienceDirection = .outgoing
	@State private var errorText: String?

	// Workout-type events get run/walk cards; the rest are single rows.
	private let workoutEvents: [AudienceEventType] = [.mileCompleted, .extraWorkout, .workout]
	private let simpleEvents: [AudienceEventType] = [.personalBest, .badgeEarned, .challengeCompleted, .streakBroken]

	/// Audience options offered in a menu/hero for the current direction.
	private var pickableAudiences: [Audience] {
		direction == .outgoing ? [.none, .close, .all, .ask] : [.none, .close, .all]
	}

	var body: some View {
		ZStack {
			MADTheme.Colors.appBackgroundGradient
				.ignoresSafeArea()

			ScrollView {
				VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
					directionTabs

					if !audience.hasLoaded {
						loadingState
					} else {
						heroDefaultCard
						perActivitySection
						simpleEventsSection
						footerNote
					}
				}
				.padding(MADTheme.Spacing.md)
			}
		}
		.navigationTitle("Friend Activity")
		.navigationBarTitleDisplayMode(.inline)
		.toolbarColorScheme(.dark, for: .navigationBar)
		.task {
			await audience.loadIfNeeded()
		}
		.overlay(alignment: .bottom) { errorToast }
	}

	// MARK: - Tabs

	private var directionTabs: some View {
		HStack(spacing: 2) {
			tabButton("Sharing", .outgoing)
			tabButton("Incoming", .incoming)
		}
		.padding(2)
		.background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
	}

	private func tabButton(_ title: String, _ value: AudienceDirection) -> some View {
		Button {
			withAnimation(.easeInOut(duration: 0.15)) { direction = value }
		} label: {
			Text(title)
				.font(.system(size: 13, weight: .semibold, design: .rounded))
				.foregroundColor(direction == value ? .white : .white.opacity(0.5))
				.frame(maxWidth: .infinity)
				.padding(.vertical, 7)
				.background(
					RoundedRectangle(cornerRadius: 8)
						.fill(direction == value ? Color.white.opacity(0.14) : .clear)
				)
		}
		.buttonStyle(.plain)
	}

	// MARK: - Hero default selector

	private var heroDefaultCard: some View {
		let explicitGlobal = audience.explicitAudience(direction: direction, eventType: .global)
		return VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
			Text(direction == .outgoing ? "Share your activity with" : "Hear about activity from")
				.font(.system(size: 16, weight: .bold, design: .rounded))
				.foregroundColor(.white)
			Text("Your main setting — every activity below uses this unless you change it individually.")
				.font(.system(size: 11, weight: .regular, design: .rounded))
				.foregroundColor(.white.opacity(0.5))
				.fixedSize(horizontal: false, vertical: true)

			LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
				ForEach(pickableAudiences, id: \.self) { aud in
					heroButton(aud, selected: explicitGlobal == aud)
				}
			}
			.padding(.top, 2)

			if explicitGlobal != nil {
				Button {
					set(eventType: .global, activity: .none, audience: nil)
				} label: {
					Text("Reset to smart defaults")
						.font(.system(size: 11, weight: .medium, design: .rounded))
						.foregroundColor(.white.opacity(0.45))
						.underline()
				}
				.buttonStyle(.plain)
				.padding(.top, 2)
			} else {
				Text("Using smart defaults — pick one to set a global default.")
					.font(.system(size: 11, weight: .regular, design: .rounded))
					.foregroundColor(.white.opacity(0.35))
			}
		}
		.padding(MADTheme.Spacing.md)
		.background(
			RoundedRectangle(cornerRadius: 18)
				.fill(MADTheme.Colors.madRed.opacity(0.12))
				.overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(MADTheme.Colors.madRed.opacity(0.4), lineWidth: 1.5))
		)
	}

	private func heroButton(_ aud: Audience, selected: Bool) -> some View {
		Button {
			set(eventType: .global, activity: .none, audience: aud)
		} label: {
			Text(aud.displayName)
				.font(.system(size: 13, weight: .semibold, design: .rounded))
				.foregroundColor(selected ? .white : .white.opacity(0.55))
				.frame(maxWidth: .infinity)
				.padding(.vertical, 11)
				.background(
					RoundedRectangle(cornerRadius: 12)
						.fill(selected ? MADTheme.Colors.madRed : Color.white.opacity(0.06))
				)
		}
		.buttonStyle(.plain)
	}

	// MARK: - Per-activity (workout) cards

	private var perActivitySection: some View {
		VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
			sectionLabel("CUSTOMIZE PER ACTIVITY")
			ForEach(workoutEvents, id: \.self) { event in
				workoutCard(event)
			}
		}
	}

	private func workoutCard(_ event: AudienceEventType) -> some View {
		VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
			Text(event.displayName)
				.font(.system(size: 13, weight: .semibold, design: .rounded))
				.foregroundColor(.white)
			if event == .workout {
				Text("Workouts that don't complete your mile.")
					.font(.system(size: 10, weight: .regular, design: .rounded))
					.foregroundColor(.white.opacity(0.45))
			}
			activityRow(event, .run, label: "Running")
			activityRow(event, .walk, label: "Walking")
		}
		.padding(MADTheme.Spacing.md)
		.background(cardBackground)
	}

	private func activityRow(_ event: AudienceEventType, _ activity: AudienceActivity, label: String) -> some View {
		HStack {
			Text(label)
				.font(.system(size: 12, weight: .regular, design: .rounded))
				.foregroundColor(.white.opacity(0.6))
			Spacer()
			audienceMenu(event: event, activity: activity)
		}
	}

	// MARK: - Simple (non-activity) events

	private var simpleEventsSection: some View {
		VStack(spacing: MADTheme.Spacing.sm) {
			ForEach(simpleEvents, id: \.self) { event in
				HStack {
					Text(event.displayName)
						.font(.system(size: 13, weight: .semibold, design: .rounded))
						.foregroundColor(.white)
					Spacer()
					audienceMenu(event: event, activity: .none)
				}
				.padding(MADTheme.Spacing.md)
				.background(cardBackground)
			}
		}
	}

	// MARK: - Audience dropdown menu

	@ViewBuilder
	private func audienceMenu(event: AudienceEventType, activity: AudienceActivity) -> some View {
		let explicit = audience.explicitAudience(direction: direction, eventType: event, activity: activity)
		let inheritedDefault = audience.resolvedDefault(direction: direction, eventType: event, activity: activity)
		// Walking rows can track the run setting.
		let runResolved = audience.resolve(direction: direction, eventType: event, activity: .run)
		let isWalk = activity == .walk

		Menu {
			// Default (reset) — always first.
			menuItem(title: "Default · \(inheritedDefault.displayName)", isSelected: explicit == nil) {
				set(eventType: event, activity: activity, audience: nil)
			}
			// Walking: "Same as Running".
			if isWalk {
				menuItem(title: "Same as Running · \(runResolved.displayName)", isSelected: explicit == .matchRun) {
					set(eventType: event, activity: activity, audience: .matchRun)
				}
			}
			ForEach(pickableAudiences, id: \.self) { aud in
				menuItem(title: aud.displayName, isSelected: explicit == aud) {
					set(eventType: event, activity: activity, audience: aud)
				}
			}
		} label: {
			menuLabel(explicit: explicit, inheritedDefault: inheritedDefault, runResolved: runResolved)
		}
	}

	private func menuItem(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			if isSelected {
				Label(title, systemImage: "checkmark")
			} else {
				Text(title)
			}
		}
	}

	private func menuLabel(explicit: Audience?, inheritedDefault: Audience, runResolved: Audience) -> some View {
		let isSet = explicit != nil
		let text: String
		if let explicit {
			text = explicit == .matchRun ? "Same as Running · \(runResolved.displayName)" : explicit.displayName
		} else {
			text = "Default · \(inheritedDefault.displayName)"
		}
		return HStack(spacing: 4) {
			Text(text)
				.font(.system(size: 12, weight: isSet ? .medium : .regular, design: .rounded))
				.lineLimit(1)
			Image(systemName: "chevron.down")
				.font(.system(size: 9, weight: .semibold))
		}
		.foregroundColor(isSet ? Color(red: 0.91, green: 0.35, blue: 0.51) : .white.opacity(0.5))
		.padding(.horizontal, 10)
		.padding(.vertical, 7)
		.background(
			RoundedRectangle(cornerRadius: 10)
				.fill(isSet ? MADTheme.Colors.madRed.opacity(0.13) : Color.clear)
				.overlay(
					RoundedRectangle(cornerRadius: 10)
						.strokeBorder(isSet ? Color.clear : Color.white.opacity(0.15), lineWidth: 1)
				)
		)
	}

	// MARK: - Bits

	private func sectionLabel(_ text: String) -> some View {
		Text(text)
			.font(.system(size: 11, weight: .heavy, design: .rounded))
			.tracking(0.8)
			.foregroundColor(.white.opacity(0.5))
			.padding(.horizontal, 4)
	}

	private var cardBackground: some View {
		RoundedRectangle(cornerRadius: 14)
			.fill(Color.white.opacity(0.04))
			.overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
	}

	private var footerNote: some View {
		Text("Gray “Default” follows your main setting above. Pink means set individually. Walking can track its Running setting with “Same as Running.”")
			.font(.system(size: 11, weight: .regular, design: .rounded))
			.foregroundColor(.white.opacity(0.4))
			.fixedSize(horizontal: false, vertical: true)
			.padding(.horizontal, 4)
	}

	private var loadingState: some View {
		VStack(spacing: MADTheme.Spacing.md) {
			ProgressView().tint(MADTheme.Colors.madRed)
			Text("Loading…")
				.font(.system(size: 13, weight: .medium, design: .rounded))
				.foregroundColor(.white.opacity(0.5))
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, MADTheme.Spacing.xxl)
	}

	@ViewBuilder
	private var errorToast: some View {
		if let errorText {
			Text(errorText)
				.font(.system(size: 12, weight: .medium, design: .rounded))
				.foregroundColor(.white)
				.padding(.horizontal, 14)
				.padding(.vertical, 10)
				.background(Capsule().fill(Color.red.opacity(0.85)))
				.padding(.bottom, MADTheme.Spacing.xl)
				.transition(.move(edge: .bottom).combined(with: .opacity))
		}
	}

	// MARK: - Mutation

	private func set(eventType: AudienceEventType, activity: AudienceActivity, audience aud: Audience?) {
		MADHaptics.tap()
		Task {
			do {
				try await audience.set(direction: direction, eventType: eventType, activity: activity, audience: aud)
			} catch {
				await MainActor.run {
					withAnimation { errorText = (error as? LocalizedError)?.errorDescription ?? "Couldn't save setting" }
				}
				try? await Task.sleep(nanoseconds: 2_500_000_000)
				await MainActor.run { withAnimation { errorText = nil } }
			}
		}
	}
}

#Preview {
	NavigationStack {
		FriendActivitySettingsView()
	}
}
