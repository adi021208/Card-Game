import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// The daily reminder.
///
/// One notification, once a day, only if the player asked for it, and worded
/// like the rest of the app. There is nothing else — no re-engagement campaign,
/// no "we miss you", no streak-loss threats.
public final class NotificationService: @unchecked Sendable {
    public static let shared = NotificationService()

    private static let dailyIdentifier = "deck.daily.reminder"

    private init() {}

    public enum Permission: Sendable {
        case notDetermined
        case granted
        case denied
    }

    public func permission() async -> Permission {
        #if canImport(UserNotifications)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .granted
        }
        #else
        return .denied
        #endif
    }

    @discardableResult
    public func requestPermission() async -> Bool {
        #if canImport(UserNotifications)
        let granted = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        return granted ?? false
        #else
        return false
        #endif
    }

    /// Schedules the reminder at a local time each day.
    ///
    /// A calendar trigger with no date component for the day repeats daily in
    /// the device's own time zone, which is the same policy the challenge date
    /// uses — so the reminder and the rollover never disagree.
    public func scheduleDailyReminder(atMinutesPastMidnight minutes: Int, streak: Int) async {
        #if canImport(UserNotifications)
        let centre = UNUserNotificationCenter.current()
        centre.removePendingNotificationRequests(withIdentifiers: [Self.dailyIdentifier])

        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.daily.title",
                               defaultValue: "Today's deck is ready.")
        content.body = streak > 0
            ? String(format: String(localized: "notification.daily.streak",
                                    defaultValue: "%d days. Keep it going."), streak)
            : String(localized: "notification.daily.body",
                     defaultValue: "One challenge, three attempts.")
        content.sound = .default

        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: Self.dailyIdentifier,
                                            content: content,
                                            trigger: trigger)
        try? await centre.add(request)
        #endif
    }

    public func cancelDailyReminder() {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.dailyIdentifier])
        #endif
    }
}
