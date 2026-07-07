//
//  Reminder.swift
//  VandaApp
//
//  Spec 3. + 4.2: emlékeztetők (gyári + saját) és a visszajelzés-naplójuk.
//

import Foundation
import SwiftData

/// Emlékeztető ütemezése (napi / heti / egyedi időpontok)
nonisolated struct ReminderSchedule: Codable {
    enum Frequency: String, Codable {
        case daily, weekly, custom
    }

    struct TimeOfDay: Codable {
        var hour: Int = 8
        var minute: Int = 0
    }

    var frequency: Frequency = .daily
    /// Heti ismétlésnél a napok (`Calendar` konvenció: 1 = vasárnap … 7 = szombat)
    var weekdays: [Int] = []
    var times: [TimeOfDay] = [TimeOfDay()]
}

@Model
final class Reminder {
    var id: UUID = UUID()
    var sourceRaw: String = ContentSource.custom.rawValue
    var title: String = ""
    /// A notification szövege — a gyáriaké is átírható
    var text: String = ""
    /// Emoji vagy SF Symbol név
    var symbolOrEmoji: String = "🔔"
    /// Kártya-/ikonszín 0xRRGGBB-ként
    var colorHex: Int = 0x8A7DE0
    var schedule: ReminderSchedule = ReminderSchedule()
    /// Kér-e ✓ visszajelzést (az eredmény a Napi progress falba folyik)
    var wantsFeedback: Bool = true
    var isActive: Bool = true
    var createdAt: Date = Date()

    init() {}

    var source: ContentSource {
        get { ContentSource(rawValue: sourceRaw) ?? .custom }
        set { sourceRaw = newValue.rawValue }
    }
}

enum ReminderLogStatus: String, Codable {
    case done     // kész
    case skipped  // kihagyva
}

@Model
final class ReminderLog {
    var id: UUID = UUID()
    /// Szándékosan UUID-referencia, nem relationship: a napló akkor is maradjon meg,
    /// ha az emlékeztetőt törlik.
    var reminderID: UUID? = nil
    var date: Date = Date()
    var statusRaw: String = ReminderLogStatus.done.rawValue

    init() {}

    var status: ReminderLogStatus {
        get { ReminderLogStatus(rawValue: statusRaw) ?? .done }
        set { statusRaw = newValue.rawValue }
    }
}
