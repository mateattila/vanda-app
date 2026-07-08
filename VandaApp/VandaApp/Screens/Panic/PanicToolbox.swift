//
//  PanicToolbox.swift
//  VandaApp
//
//  A panik-képernyő eszközkészlete (spec 4.4): érzés-chipek és a hozzájuk
//  illő eszköz-sorrend. A modulrendszer v1-e — új eszköz felvételéhez
//  a PanicToolID bővítendő, a képernyő a sorrendből dolgozik.
//

import Foundation

enum PanicFeeling: String, CaseIterable, Identifiable {
    case scared
    case angry
    case restless
    case sad

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scared: "Félek"
        case .angry: "Dühös vagyok"
        case .restless: "Nem tudok megnyugodni"
        case .sad: "Szomorú vagyok"
        }
    }

    var emoji: String {
        switch self {
        case .scared: "😨"
        case .angry: "😤"
        case .restless: "🌀"
        case .sad: "😢"
        }
    }
}

enum PanicToolID: String, CaseIterable, Identifiable {
    case breathing
    case grounding
    case calmFolder
    case calmActivities
    case callParents

    var id: String { rawValue }
}

enum PanicToolbox {
    static let defaultOrder: [PanicToolID] = [
        .breathing, .grounding, .calmFolder, .calmActivities, .callParents,
    ]

    /// Az érzéshez illő eszközök előre sorolva; a többi az alap sorrendben követ.
    static func recommendedOrder(for feeling: PanicFeeling?) -> [PanicToolID] {
        guard let feeling else { return defaultOrder }
        let lead: [PanicToolID] = switch feeling {
        case .scared: [.breathing, .callParents]
        case .angry: [.grounding, .calmActivities]
        case .restless: [.breathing, .grounding]
        case .sad: [.calmFolder, .callParents]
        }
        return lead + defaultOrder.filter { !lead.contains($0) }
    }
}
