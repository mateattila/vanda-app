//
//  ReminderSeeder.swift
//  VandaApp
//
//  Gyári emlékeztető-csomag (spec 4.2) — ki-be kapcsolható, a szövegük átírható.
//

import Foundation
import SwiftData

enum ReminderSeeder {

    /// Akkor fut, ha a csomag még nincs bent. Gyári emlékeztető nem törölhető,
    /// így a csomagnál kevesebb gyári elem azt jelenti, hogy még nem seedeltünk —
    /// a napló fotó-promptja vagy egy saját emlékeztető ezt nem akadályozza.
    static func seedFactoryPackIfNeeded(in context: ModelContext) {
        let reminders = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []
        guard reminders.filter({ $0.source == .factory }).count < factoryPack.count else { return }

        for item in factoryPack {
            let reminder = Reminder()
            reminder.title = item.title
            reminder.text = item.text
            reminder.symbolOrEmoji = item.emoji
            reminder.colorHex = item.colorHex
            reminder.source = .factory
            var schedule = ReminderSchedule()
            schedule.times = item.times.map { ReminderSchedule.TimeOfDay(hour: $0.0, minute: $0.1) }
            reminder.schedule = schedule
            context.insert(reminder)
        }
    }

    private struct Seed {
        let title: String
        let text: String
        let emoji: String
        let colorHex: Int
        let times: [(Int, Int)]
    }

    private static let factoryPack: [Seed] = [
        Seed(title: "Vitamin", text: "Vitamin-idő! 💊", emoji: "💊", colorHex: 0xF2A65A, times: [(8, 0)]),
        Seed(title: "Pohár víz", text: "Egy pohár vizet reggelre 💙", emoji: "💧", colorHex: 0x6FA8E8, times: [(7, 30)]),
        Seed(title: "Fogmosás", text: "Fogmosás-parti 🪥✨", emoji: "🪥", colorHex: 0x8A7DE0, times: [(7, 45), (21, 30)]),
        Seed(title: "Fogszabályzó", text: "Fogszabályzó be! 🦷", emoji: "🦷", colorHex: 0xEC6F9E, times: [(21, 0)]),
        Seed(title: "Ettél?", text: "Ettél már valami jót? 🍎", emoji: "🍎", colorHex: 0xE06A5E, times: [(13, 0)]),
        Seed(title: "Ittál?", text: "Kortyolj egyet! 🥤", emoji: "🥤", colorHex: 0x5FB89C, times: [(16, 0)]),
        Seed(title: "Kimozdulás", text: "Kimentél már ma? Touch grass! 🌿", emoji: "🌿", colorHex: 0x5FB89C, times: [(15, 0)]),
        Seed(title: "Birkák", text: "Go feed the sheep! 🐑", emoji: "🐑", colorHex: 0x8A7DE0, times: [(17, 0)]),
    ]
}
