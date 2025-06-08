import Foundation
import UserNotifications

class NotificationManager: ObservableObject {
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    func scheduleStreakReminderNotification(at hour: Int = 18) {
        let content = UNMutableNotificationContent()
        content.title = "Mile A Day"
        content.body = "Don't forget to complete your mile today to keep your streak going!"
        content.sound = .default
        
        var dateComponents = DateComponents()
        dateComponents.hour = hour // 6 PM reminder
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "streak.reminder", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error.localizedDescription)")
            }
        }
    }
    
    func scheduleCompletionCongratulationsNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Mile Complete! 🎉"
        content.body = "You've kept your streak alive today. Great job!"
        content.sound = .default
        
        // Schedule for immediate delivery
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "completion.congrats", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error.localizedDescription)")
            }
        }
    }
} 