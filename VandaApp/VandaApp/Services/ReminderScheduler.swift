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
    static let snooze10ActionID = "REMINDER_SNOOZE_10"
    static let snooze30ActionID = "REMINDER_SNOOZE_30"
    static let snooze60ActionID = "REMINDER_SNOOZE_60"
    static let skipTodayActionID = "REMINDER_SKIP_TODAY"
    private static let identifierPrefix = "reminder_"
    /// A szundizott egyszeri értesítések előtagja — szándékosan NEM a
    /// `reminder_` előtag, hogy a resync ne söpörje ki a függő szundikat.
    private static let snoozeIdentifierPrefix = "reminderSnooze_"

    /// Szundi-akcióhoz tartozó késleltetés; nem-szundi akcióra nil.
    static func snoozeInterval(for actionID: String) -> TimeInterval? {
        switch actionID {
        case snooze10ActionID: 10 * 60
        case snooze30ActionID: 30 * 60
        case snooze60ActionID: 60 * 60
        default: nil
        }
    }

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
        // Szundi + mai alkalom kihagyása (2026-07-09-i kérés). A „Ma kihagyom"
        // szándékosan nem töröl semmit — az emlékeztető holnap újra szól.
        let snooze10 = UNNotificationAction(identifier: Self.snooze10ActionID, title: "+10 perc", options: [])
        let snooze30 = UNNotificationAction(identifier: Self.snooze30ActionID, title: "+30 perc", options: [])
        let snooze60 = UNNotificationAction(identifier: Self.snooze60ActionID, title: "+1 óra", options: [])
        let skipToday = UNNotificationAction(identifier: Self.skipTodayActionID, title: "Ma kihagyom", options: [])
        let reminderCategory = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [done, snooze10, snooze30, snooze60, skipToday],
            intentIdentifiers: [],
            options: []
        )
        let moodCategory = UNNotificationCategory(
            identifier: MoodPromptScheduler.categoryID,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([reminderCategory, moodCategory])
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
        let categoryID = response.notification.request.content.categoryIdentifier

        Task { @MainActor in
            defer { completionHandler() }

            // Aksi-rákérdezésre koppintás: az app megnyílik, a Ma képernyő
            // kapuja pedig felteszi a csúszkát.
            if categoryID == MoodPromptScheduler.categoryID,
               actionID == UNNotificationDefaultActionIdentifier {
                UserDefaults.standard.set(true, forKey: MoodPromptScheduler.pendingFlagKey)
                return
            }

            // Szundi: ugyanaz a tartalom még egyszer, eltolva. Külön előtaggal,
            // hogy egy közbeeső resync ne törölje.
            if let interval = Self.snoozeInterval(for: actionID) {
                let content = response.notification.request.content.mutableCopy() as! UNMutableNotificationContent
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "\(Self.snoozeIdentifierPrefix)\(UUID().uuidString)",
                    content: content,
                    trigger: trigger
                )
                try? await center.add(request)
                return
            }

            guard let reminderIDString,
                  let reminderID = UUID(uuidString: reminderIDString),
                  let container = self.modelContainer else { return }

            // „Ma kihagyom": csak feljegyezzük — se pipa, se bűntudat,
            // az emlékeztető holnap ugyanúgy szól.
            if actionID == Self.skipTodayActionID {
                let log = ReminderLog()
                log.reminderID = reminderID
                log.status = .skipped
                container.mainContext.insert(log)
                try? container.mainContext.save()
                return
            }

            guard actionID == Self.doneActionID else { return }

            let log = ReminderLog()
            log.reminderID = reminderID
            log.status = .done
            container.mainContext.insert(log)
            try? container.mainContext.save()
        }
    }
}
