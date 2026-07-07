//
//  VandaModelContainer.swift
//  VandaApp
//
//  SwiftData + CloudKit (privát adatbázis): iPhone ↔ iPad automatikus szinkron
//  Vanda saját iCloudjában. A modellek CloudKit-kompatibilisek: minden mező
//  opcionális vagy alapértékes, nincs @Attribute(.unique).
//

import SwiftData

enum VandaStore {
    static let schema = Schema([
        AlarmProfile.self,
        Reminder.self,
        ReminderLog.self,
        MoodEntry.self,
        MoodSettings.self,
        Question.self,
        Activity.self,
        JournalEntry.self,
        JournalAuditEvent.self,
        DailyTask.self,
        JournalTemplate.self,
        ThemeSettings.self,
    ])

    static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .private("iCloud.hu.attis.VandaApp")
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Nem sikerült létrehozni a ModelContainert: \(error)")
        }
    }
}
