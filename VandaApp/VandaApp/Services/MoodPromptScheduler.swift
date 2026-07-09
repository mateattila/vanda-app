//
//  MoodPromptScheduler.swift
//  VandaApp
//
//  Napi 1-2 véletlenszerű aksi-rákérdezés a beállított idősávban (spec 4.3).
//  A következő 7 nap kérdezéseit ütemezzük fix időpontokra; minden
//  app-indulás újrasorsolja őket.
//

import Foundation
import SwiftData
import UserNotifications

final class MoodPromptScheduler {
    static let shared = MoodPromptScheduler()

    static let categoryID = "VANDA_MOOD"
    static let pendingFlagKey = "moodPromptPending"
    static let todayFireDatesKey = "moodTodayFireDates"
    private static let identifierPrefix = "mood_"

    /// Igaz, ha ma már szólt (vagy Vanda már válaszolt) egy rákérdezés —
    /// ilyenkor az újrasorsolás a mai napot kihagyja, különben az app minden
    /// megnyitása (tipikusan épp a prompt-ra!) második aznapi kérdezést sorsolna.
    static func shouldSkipToday(
        storedFireDates: [Date],
        hasEntryToday: Bool,
        pendingFlag: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        if hasEntryToday || pendingFlag { return true }
        return storedFireDates.contains { calendar.isDate($0, inSameDayAs: now) && $0 <= now }
    }

    func resync(settings: MoodSettings, hasEntryToday: Bool = false) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard settings.promptsPerDay > 0 else { return }

        let defaults = UserDefaults.standard
        let storedDates = (defaults.array(forKey: Self.todayFireDatesKey) as? [Date]) ?? []
        let skipToday = Self.shouldSkipToday(
            storedFireDates: storedDates,
            hasEntryToday: hasEntryToday,
            pendingFlag: defaults.bool(forKey: Self.pendingFlagKey)
        )

        let calendar = Calendar.current
        let startHour = min(settings.promptWindowStartHour, settings.promptWindowEndHour)
        let endHour = max(settings.promptWindowStartHour, settings.promptWindowEndHour, startHour + 1)
        let windowMinutes = (endHour - startHour) * 60

        var todayFireDates: [Date] = skipToday ? storedDates : []
        for dayOffset in (skipToday ? 1 : 0)..<7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: Date()) else { continue }
            for promptIndex in 0..<min(settings.promptsPerDay, 2) {
                // A sáv promptonkénti szeletén belül sorsolunk, hogy két kérdezés ne essen egymásra.
                let sliceLength = windowMinutes / min(settings.promptsPerDay, 2)
                let minuteOffset = sliceLength * promptIndex + Int.random(in: 0..<max(1, sliceLength))
                guard let fireDate = calendar.date(
                    bySettingHour: startHour + minuteOffset / 60,
                    minute: minuteOffset % 60,
                    second: 0,
                    of: day
                ), fireDate > Date() else { continue }

                let content = UNMutableNotificationContent()
                content.title = "Aksi-check 🔋"
                content.body = "Hány százalékon vagy most? 5 másodperc az egész."
                content.sound = .default
                content.categoryIdentifier = Self.categoryID

                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "\(Self.identifierPrefix)\(dayOffset)_\(promptIndex)",
                    content: content,
                    trigger: trigger
                )
                try? await center.add(request)
                if dayOffset == 0 {
                    todayFireDates.append(fireDate)
                }
            }
        }
        defaults.set(todayFireDates, forKey: Self.todayFireDatesKey)
    }

    @MainActor
    func resyncFromStore(container: ModelContainer) async {
        let settings = MoodSettings.ensureCurrent(in: container.mainContext)
        let entries = (try? container.mainContext.fetch(FetchDescriptor<MoodEntry>())) ?? []
        let hasEntryToday = entries.contains { Calendar.current.isDateInToday($0.timestamp) }
        await resync(settings: settings, hasEntryToday: hasEntryToday)
    }
}
