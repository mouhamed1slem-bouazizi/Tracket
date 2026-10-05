import Foundation
import UserNotifications

enum NotificationServiceError: LocalizedError {
    case appBundleRequired

    var errorDescription: String? {
        "Notifications are available in the packaged Tracket.app build."
    }
}

struct NotificationService {
    func requestPermission() async throws -> Bool {
        guard let center else { throw NotificationServiceError.appBundleRequired }
        return try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func scheduleNudge(for project: TracketProject) async throws {
        guard let center else { throw NotificationServiceError.appBundleRequired }
        center.removePendingNotificationRequests(withIdentifiers: [identifier(for: project)])
        guard project.stage != .live else { return }

        let content = UNMutableNotificationContent()
        content.title = "Keep \(project.name) moving"
        content.body = project.activeTask.map { "Next: \($0.title)" }
            ?? project.nextSuggestion
            ?? "Open Tracket and choose the next small step toward launch."
        content.sound = .default

        var date = Calendar.current.dateComponents([.year, .month, .day], from: Date().addingTimeInterval(24 * 60 * 60))
        date.hour = 10
        date.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier(for: project),
            content: content,
            trigger: trigger
        )
        try await center.add(request)
    }

    func removeNudge(for project: TracketProject) {
        guard let center else { return }
        center.removePendingNotificationRequests(withIdentifiers: [identifier(for: project)])
    }

    func removeAllNudges() {
        guard let center else { return }
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    private func identifier(for project: TracketProject) -> String {
        "tracket.nudge.\(project.id.uuidString)"
    }
}
