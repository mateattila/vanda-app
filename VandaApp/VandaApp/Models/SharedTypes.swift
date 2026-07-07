//
//  SharedTypes.swift
//  VandaApp
//
//  Több modell által használt kis típusok.
//  CloudKit-szabály (minden @Model-re): minden mező opcionális vagy alapértékes,
//  nincs @Attribute(.unique) — az enumok String rawValue-ként tárolódnak.
//

import Foundation

/// Tartalom eredete (emlékeztető, kérdés, tevékenység…)
enum ContentSource: String, Codable {
    case factory      // gyári csomag
    case custom       // Vanda sajátja
    case aiApproved   // AI-generált, jóváhagyva (5. fázis)
}
