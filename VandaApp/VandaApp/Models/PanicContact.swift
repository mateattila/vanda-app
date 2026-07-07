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
    var dialableNumber: String {
        let trimmed = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
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

    var telURL: URL? { deepLink(scheme: "tel") }
    var faceTimeVideoURL: URL? { deepLink(scheme: "facetime") }
    var faceTimeAudioURL: URL? { deepLink(scheme: "facetime-audio") }

    private func deepLink(scheme: String) -> URL? {
        let number = dialableNumber
        guard !number.isEmpty else { return nil }
        return URL(string: "\(scheme)://\(number)")
    }
}
