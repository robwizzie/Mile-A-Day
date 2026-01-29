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
        Form {
            Section(header: Text("Daily Reminder")) {
                Toggle("Enable Daily Reminder", isOn: $prefs.dailyReminderEnabled)
                if prefs.dailyReminderEnabled {
                    DatePicker("", selection: reminderTimeBinding, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                }
            }

            Section(header: Text("Instant Notifications")) {
                Toggle("When I complete a mile", isOn: $prefs.mileCompletedEnabled)
                Toggle("When a friend completes a mile", isOn: $prefs.friendCompletedEnabled)
                Toggle("When I receive a friend request", isOn: $prefs.friendRequestReceivedEnabled)
                Toggle("When a friend request is accepted", isOn: $prefs.friendRequestAcceptedEnabled)
            }
        }
        .navigationTitle("Notifications")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveAndApply()
                }
            }
        }
    }

    private func saveAndApply() {
        prefs.save()
        // Update daily reminder schedule based on new prefs
        if prefs.dailyReminderEnabled {
            // Get current health data for smart notification
            let widgetData = WidgetDataStore.load()
            
            // Use smart daily reminder logic
            notificationService.updateDailyReminder(
                isCompleted: widgetData.miles >= widgetData.goal,
                currentMiles: widgetData.miles,
                goalMiles: widgetData.goal,
                at: prefs.dailyReminderHour
            )
        } else {
            // Remove existing reminder
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [MADNotificationService.Identifier.dailyReminder])
        }
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
} 