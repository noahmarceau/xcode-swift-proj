import Foundation
import UserNotifications

enum RestNotifications {
    static func request() async throws -> Bool { try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    static func cancel() { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rest"]) }
    static func schedule(seconds: Int) {
        cancel()
        let content = UNMutableNotificationContent(); content.title = "Ready for your next set"; content.body = "Your rest timer has finished."; content.sound = .default
        let request = UNNotificationRequest(identifier: "rest", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: Double(max(1, seconds)), repeats: false))
        UNUserNotificationCenter.current().add(request)
    }
}
