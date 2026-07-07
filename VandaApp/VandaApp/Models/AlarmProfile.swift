//
//  AlarmProfile.swift
//  VandaApp
//
//  Spec 3. fejezet: id, név, ütemezés, hangfájl, láncbeállítás, feladvány-típus/nehézség.
//  Az AlarmKit-integráció az 1. fázis dolga; itt csak a perzisztens modell van.
//

import Foundation
import SwiftData

enum AlarmPuzzleKind: String, Codable {
    case none   // Nincs
    case math   // matekpélda (v1); a feladvány-modul cserélhető protokoll mögött lesz
}

@Model
final class AlarmProfile {
    var id: UUID = UUID()
    var name: String = ""
    var hour: Int = 6
    var minute: Int = 45
    /// Ismétlés napjai, `Calendar` konvencióval (1 = vasárnap … 7 = szombat); üres = egyszeri
    var repeatWeekdays: [Int] = []
    /// A zenetárból választott hangfájl neve (Library/Sounds alatt)
    var soundFileName: String? = nil

    // Lánc-ébresztő (spec 4.1): egy „ébresztés" = N alarm, M percenként
    var isChainEnabled: Bool = true
    var chainCount: Int = 5
    var chainIntervalMinutes: Int = 2

    // Kikapcsoló feladvány
    var puzzleKindRaw: String = AlarmPuzzleKind.math.rawValue
    /// Nehézség: 1 = könnyű … (skála a 9.1 nyitott kérdés szerint Vandával iterálva)
    var puzzleDifficulty: Int = 1
    /// Hány jó válasz kell a kikapcsoláshoz
    var puzzleRequiredCorrect: Int = 3

    var isEnabled: Bool = true
    var createdAt: Date = Date()

    init() {}

    var puzzleKind: AlarmPuzzleKind {
        get { AlarmPuzzleKind(rawValue: puzzleKindRaw) ?? .math }
        set { puzzleKindRaw = newValue.rawValue }
    }
}
