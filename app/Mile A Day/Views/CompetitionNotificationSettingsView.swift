import SwiftUI

/// Drill-in screen for the eight individual competition notification toggles.
/// Lives behind the collapsed "Competitions" master toggle in
/// `NotificationSettingsView` so the main settings page stays uncluttered.
/// Shares the parent's `prefs` binding; `onSave` persists + syncs to backend.
struct CompetitionNotificationSettingsView: View {
	@Binding var prefs: NotificationPreferences
	var onSave: () -> Void

	var body: some View {
		ZStack {
			MADTheme.Colors.appBackgroundGradient
				.ignoresSafeArea()

			ScrollView {
				VStack(spacing: MADTheme.Spacing.lg) {
					settingsSection(title: "INVITES & STATUS", icon: "envelope.fill", iconColor: .yellow) {
						settingsToggle("Competition invites", isOn: $prefs.competitionInviteEnabled)
						settingsDivider
						settingsToggle("Invite accepted", isOn: $prefs.competitionAcceptedEnabled)
						settingsDivider
						settingsToggle("Competition started", isOn: $prefs.competitionStartEnabled)
						settingsDivider
						settingsToggle("Competition finished", isOn: $prefs.competitionFinishEnabled)
					}

					settingsSection(title: "CHEERS", icon: "hands.clap.fill", iconColor: .pink) {
						settingsToggle("Competition nudges", isOn: $prefs.competitionNudgeEnabled)
						settingsDivider
						settingsToggle("Flex notifications", isOn: $prefs.competitionFlexEnabled)
						settingsDivider
						settingsToggle("Hype reactions", isOn: $prefs.hypeEnabled,
							description: "When a friend or competitor cheers on your completed mile")
					}

					settingsSection(title: "UPDATES", icon: "flag.checkered", iconColor: .green) {
						settingsToggle("Milestones & updates", isOn: $prefs.competitionMilestonesEnabled,
							description: "Halfway marks, one point from winning, and more")
					}

					Spacer(minLength: MADTheme.Spacing.xxl)
				}
				.padding(MADTheme.Spacing.md)
			}
		}
		.navigationTitle("Competitions")
		.navigationBarTitleDisplayMode(.inline)
		.toolbarColorScheme(.dark, for: .navigationBar)
		.toolbar {
			ToolbarItem(placement: .confirmationAction) {
				Button("Save") { onSave() }
					.foregroundColor(MADTheme.Colors.madRed)
					.fontWeight(.semibold)
			}
		}
	}

	// MARK: - Reused styling helpers (mirror NotificationSettingsView)

	private func settingsSection<Content: View>(
		title: String,
		icon: String,
		iconColor: Color,
		@ViewBuilder content: () -> Content
	) -> some View {
		VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
			HStack(spacing: MADTheme.Spacing.sm) {
				Image(systemName: icon)
					.font(.system(size: 11, weight: .semibold))
					.foregroundColor(iconColor)
				Text(title)
					.font(MADTheme.Typography.caption)
					.fontWeight(.semibold)
					.foregroundColor(.secondary)
					.tracking(0.5)
			}
			content()
		}
		.padding(MADTheme.Spacing.md)
		.madLiquidGlass()
	}

	private func settingsToggle(_ label: String, isOn: Binding<Bool>, description: String? = nil) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Toggle(label, isOn: isOn)
				.font(MADTheme.Typography.body)
				.tint(MADTheme.Colors.madRed)
			if let description = description {
				Text(description)
					.font(.system(size: 11, design: .rounded))
					.foregroundColor(.white.opacity(0.35))
					.padding(.leading, 2)
			}
		}
	}

	private var settingsDivider: some View {
		Divider().overlay(Color.white.opacity(0.06))
	}
}
