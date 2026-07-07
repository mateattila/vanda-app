//
//  Mood.swift
//  VandaApp
//
//  Spec 3. + 4.3: hangulatbarométer (aksi%) és a kérdésbank.
//  Adatkezelés: CloudKit-szinkron Vanda eszközei közt; a szülők felé csak a
//  kapcsolható megosztás számai mennek (4. fázis, backend) — a válaszok soha.
//

import Foundation
import SwiftData

/// Zóna-határok beállításban módosíthatók, ezért a bejegyzés a kitöltéskori zónát tárolja.
enum MoodZone: String, Codable {
    case green   // „bírom"
    case orange  // „fárad"
    case red     // „kimerül"
}

/// Opcionális kérdés-válasz pár egy kitöltéshez
nonisolated struct MoodAnswer: Codable {
    var question: String = ""
    var answer: String = ""
}

@Model
final class MoodEntry {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    /// „Hány százalékos az aksid?" — 0–100
    var batteryPercent: Int = 50
    var zoneRaw: String = MoodZone.green.rawValue
    var answers: [MoodAnswer] = []

    init() {}

    var zone: MoodZone {
        get { MoodZone(rawValue: zoneRaw) ?? .green }
        set { zoneRaw = newValue.rawValue }
    }
}

@Model
final class Question {
    var id: UUID = UUID()
    var text: String = ""
    /// 1 = könnyű … 3 = mély
    var level: Int = 1
    var isActive: Bool = true
    var sourceRaw: String = ContentSource.factory.rawValue

    init() {}

    var source: ContentSource {
        get { ContentSource(rawValue: sourceRaw) ?? .factory }
        set { sourceRaw = newValue.rawValue }
    }
}
