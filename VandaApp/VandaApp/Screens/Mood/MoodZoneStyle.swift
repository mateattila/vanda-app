//
//  MoodZoneStyle.swift
//  VandaApp
//
//  A zónák megjelenése — a zóna-színek FIXEK, nem témázhatók (design-tokens 2.).
//

import SwiftUI

extension MoodZone {
    var name: String {
        switch self {
        case .green: "Zöld"
        case .orange: "Narancs"
        case .red: "Piros"
        }
    }

    var label: String {
        switch self {
        case .green: "bírom"
        case .orange: "fárad"
        case .red: "kimerül"
        }
    }

    /// Kitöltés (mérő, sávok)
    var fillColor: Color {
        switch self {
        case .green: .zoneGreen
        case .orange: .zoneOrange
        case .red: .zoneRed
        }
    }

    /// Jelző (chip, hangsúly)
    var strongColor: Color {
        switch self {
        case .green: .zoneGreen
        case .orange: .zoneOrangeStrong
        case .red: .zoneRedStrong
        }
    }
}
