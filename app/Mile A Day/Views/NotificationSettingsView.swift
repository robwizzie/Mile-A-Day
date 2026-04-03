import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @State private var prefs = NotificationPreferences.load()
    @ObservedObject private var notificationService = MADNotificationService.shared

    // Convert stored hour into Date for DatePicker and vice-versa
    private var reminderTimeBinding: Binding<Date> {
        Binding {
            var comps = DateComponents()
            comps.hour = prefs.dailyReminderHour
            comps.minute = 0
            return Calendar.current.date(from: comps) ?? Date()
        } set: { date in
            let hour = Calendar.current.component(.hour, from: date)
            prefs.dailyReminderHour = hour
        }
    }

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: MADTheme.Spacing.lg) {
                    // Daily Reminder Section
                    VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                        Text("DAILY REMINDER")
                            .font(MADTheme.Typography.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .tracking(0.5)

                        Toggle("Enable Daily Reminder", isOn: $prefs.dailyReminderEnabled)
                            .font(MADTheme.Typography.body)
                            .tint(MADTheme.Colors.madRed)

                        if prefs.dailyReminderEnabled {
                            Divider().overlay(Color.white.opacity(0.06))

                            DatePicker("Reminder Time", selection: reminderTimeBinding, displayedComponents: .hourAndMinute)
                                .font(MADTheme.Typography.body)
                                .datePickerStyle(.compact)
                                .tint(MADTheme.Colors.madRed)
                        }
                    }
                    .padding(MADTheme.Spacing.md)
                    .madLiquidGlass()

                    // Instant Notifications Section
                    VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                        Text("INSTANT NOTIFICATIONS")
                            .font(MADTheme.Typography.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .tracking(0.5)

                        Toggle("When I complete a mile", isOn: $prefs.mileCompletedEnabled)
                            .font(MADTheme.Typography.body)
                            .tint(MADTheme.Colors.madRed)

                        Divider().overlay(Color.white.opacity(0.06))

                        Toggle("When a friend completes a mile", isOn: $prefs.friendCompletedEnabled)
                            .font(MADTheme.Typography.body)
                            .tint(MADTheme.Colors.madRed)

                        Divider().overlay(Color.white.opacity(0.06))

                        Toggle("When I receive a friend request", isOn: $prefs.friendRequestReceivedEnabled)
                            .font(MADTheme.Typography.body)
                            .tint(MADTheme.Colors.madRed)

                        Divider().overlay(Color.white.opacity(0.06))

                        Toggle("When a friend request is accepted", isOn: $prefs.friendRequestAcceptedEnabled)
                            .font(MADTheme.Typography.body)
                            .tint(MADTheme.Colors.madRed)
                    }
                    .padding(MADTheme.Spacing.md)
                    .madLiquidGlass()
                }
                .padding(MADTheme.Spacing.md)
            }

            Section(header: Text("Competitions")) {
                Toggle("Competition invites", isOn: $prefs.competitionInviteEnabled)
                Toggle("Invite accepted", isOn: $prefs.competitionAcceptedEnabled)
                Toggle("Competition started", isOn: $prefs.competitionStartEnabled)
                Toggle("Competition finished", isOn: $prefs.competitionFinishEnabled)
                Toggle("Nudges", isOn: $prefs.competitionNudgeEnabled)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveAndApply()
                }
                .foregroundColor(MADTheme.Colors.madRed)
                .fontWeight(.semibold)
            }
        }
    }

    private func saveAndApply() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        prefs.save()
        if prefs.dailyReminderEnabled {
            let widgetData = WidgetDataStore.load()
            notificationService.updateDailyReminder(
                isCompleted: widgetData.miles >= widgetData.goal,
                currentMiles: widgetData.miles,
                goalMiles: widgetData.goal,
                at: prefs.dailyReminderHour
            )
        } else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [MADNotificationService.Identifier.dailyReminder])
        }
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
}
