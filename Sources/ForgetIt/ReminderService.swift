import Foundation
import UserNotifications

@MainActor
final class ReminderService: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: ((UUID) -> Void)?
    private var revision = 0
    private var syncTask: Task<Void, Never>?
    // Notification APIs require an app bundle. CLI tests never initialize the store.
    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    func requestPermission(completion: @escaping () -> Void) {
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            completion()
        }
    }

    func synchronize(data: PlannerData, completion: @escaping (String, Int, String?) -> Void) {
        revision += 1
        let token = revision
        let previous = syncTask
        syncTask = Task {
            // Serialize replacements so a rapid edit cannot leave stale requests behind.
            await previous?.value
            guard token == revision else { return }
            center.delegate = self
            let settings = await center.notificationSettings()
            guard token == revision else { return }
            center.removeAllPendingNotificationRequests()
            let delivered = await center.deliveredNotifications()
            let activeIDs = Set(data.tasks.filter { !$0.isComplete }.map { $0.id.uuidString })
            center.removeDeliveredNotifications(withIdentifiers: delivered.filter {
                !activeIDs.contains($0.request.content.userInfo["taskID"] as? String ?? "") || $0.date < Date().addingTimeInterval(-86400)
            }.map { $0.request.identifier })
            let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            guard allowed else {
                completion(settings.authorizationStatus == .denied ? "Notifications are off in System Settings" : "Not requested", 0, nil)
                return
            }
            let now = Date()
            let planned = data.tasks.filter { !$0.isComplete }.flatMap { task in
                task.reminderDates(rule: task.reminder ?? data.defaultReminder ?? ReminderRule(), now: now).map { (task, $0) }
            }.sorted { $0.1 < $1.1 }
            var count = 0
            var failure: String?
            for (task, date) in planned.prefix(60) {
                guard token == revision else { return }
                let content = UNMutableNotificationContent()
                content.title = "\(data.classes.first { $0.id == task.classID }?.name ?? "Homework") · \(task.title)"
                content.body = "\(task.isEvent ? "Event" : "Due") \(task.deadlineText)"
                content.sound = .default
                content.userInfo = ["taskID": task.id.uuidString]
                let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date), repeats: false)
                let request = UNNotificationRequest(identifier: "\(task.id.uuidString)-\(Int(date.timeIntervalSince1970))", content: content, trigger: trigger)
                do { try await center.add(request); count += 1 }
                catch { failure = "Some reminders could not be scheduled: \(error.localizedDescription)" }
            }
            guard token == revision else { return }
            completion(planned.count > 60 ? "Enabled · next 60 alerts scheduled; reopen to refresh" : "Enabled", count, failure)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let text = response.notification.request.content.userInfo["taskID"] as? String, let id = UUID(uuidString: text) else { return }
        await MainActor.run { self.onOpen?(id) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
