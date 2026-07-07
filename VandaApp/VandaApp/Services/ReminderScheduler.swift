//
//  ReminderScheduler.swift
//  VandaApp
//
//  Lokális notificationök az emlékeztetőkhöz (spec 4.2). Szándékosan NEM
//  agresszív (sima UserNotifications, nem AlarmKit). A „✓ Kész" action
//  eredménye ReminderLog-ba folyik — abból épül majd a napi progress fal.
//

import Foundation
import SwiftData
import UserNotifications

final class ReminderScheduler: NSObject {
    static let shared = ReminderScheduler()

    static let categoryID = "VANDA_REMINDER"
    static let doneActionID = "REMINDER_DONE"
    private static let identifierPrefix = "reminder_"

    private var modelContainer: ModelContainer?

    /// App-induláskor hívandó: delegate + a „✓ Kész" action kategóriája.
    func configure(container: ModelContainer) {
        modelContainer = container
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let done = UNNotificationAction(
            identifier: Self.doneActionID,
            title: "✓ Kész",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [done],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    /// Engedélykérés, ha még nem dőlt el; a válasz: küldhetünk-e értesítést.
    func ensureAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            return false
        default:
            return true
        }
    }

    /// Teljes újraszinkron: a mi függő kéréseink törlése, majd az aktív
    /// emlékeztetők újraütemezése. Minden szerkesztés/kapcsolás után ezt hívjuk —
    /// egyszerűbb és robusztusabb, mint a különbség-követés.
    func resync(reminders: [Reminder]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        for reminder in reminders where reminder.isActive {
            for request in requests(for: reminder) {
                try? await center.add(request)
            }
        }
    }

    /// Kényelmi változat: maga kérdezi le az emlékeztetőket a containerből.
    func resyncFromStore() async {
        guard let modelContainer else { return }
        let reminders = (try? modelContainer.mainContext.fetch(FetchDescriptor<Reminder>())) ?? []
        await resync(reminders: reminders)
    }

    private func requests(for reminder: Reminder) -> [UNNotificationRequest] {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.text
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        content.userInfo = [
            "reminderID": reminder.id.uuidString,
            "wantsFeedback": reminder.wantsFeedback,
        ]

        let schedule = reminder.schedule
        let weekdays: [Int?] = schedule.isDaily ? [nil] : schedule.weekdays.map(Optional.init)

        var result: [UNNotificationRequest] = []
        var index = 0
        for time in schedule.times {
            for weekday in weekdays {
                var components = DateComponents()
                components.hour = time.hour
                components.minute = time.minute
                components.weekday = weekday
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                result.append(UNNotificationRequest(
                    identifier: "\(Self.identifierPrefix)\(reminder.id.uuidString)_\(index)",
                    content: content,
                    trigger: trigger
                ))
                index += 1
            }
        }
        return result
    }
}

// MARK: - Delegate: foreground megjelenítés + „✓ Kész" action

extension ReminderScheduler: UNUserNotificationCenterDelegate {

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionID = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        let reminderIDString = userInfo["reminderID"] as? String

        Task { @MainActor in
            defer { completionHandler() }
            guard actionID == Self.doneActionID,
                  let reminderIDString,
                  let reminderID = UUID(uuidString: reminderIDString),
                  let container = self.modelContainer else { return }

            let log = ReminderLog()
            log.reminderID = reminderID
            log.status = .done
            container.mainContext.insert(log)
            try? container.mainContext.save()
        }
    }
}
