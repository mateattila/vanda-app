//
//  PanicContact.swift
//  VandaApp
//
//  „Hívd anyát / apát" — a panik-képernyő hívás-gombjainak címzettjei
//  (spec 4.4). CloudKit-szinkronizált, a Beállításokban szerkeszthető.
//

import Foundation
import SwiftData

@Model
final class PanicContact {
    var id: UUID = UUID()
    var label: String = ""
    var emoji: String = "💛"
    /// Telefonszám — a tel: és a FaceTime linkek is ebből készülnek.
    var phoneNumber: String = ""
    var orderIndex: Int = 0
    var createdAt: Date = Date()

    init() {}
}

extension PanicContact {
    /// Csak számjegyek + esetleges vezető „+" („06 30 123-4567" → „06301234567").
    var dialableNumber: String { Self.dialableNumber(from: phoneNumber) }

    /// Csak számjegyek + esetleges vezető „+" („06 30 123-4567" → „06301234567").
    static func dialableNumber(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = ""
        for character in trimmed {
            if character.isWholeNumber {
                result.append(character)
            } else if character == "+" && result.isEmpty {
                result.append(character)
            }
        }
        return result
    }

    /// RFC 3966 / Apple dokumentált forma: „tel:” — kettőspont, nincs „//”.
    var telURL: URL? { deepLink(prefix: "tel:") }
    var faceTimeVideoURL: URL? { deepLink(prefix: "facetime://") }
    var faceTimeAudioURL: URL? { deepLink(prefix: "facetime-audio://") }

    private func deepLink(prefix: String) -> URL? {
        let number = dialableNumber
        // Egy magányos „+” (számjegy nélkül) nem hívható szám.
        guard number.contains(where: \.isWholeNumber) else { return nil }
        return URL(string: "\(prefix)\(number)")
    }
}
