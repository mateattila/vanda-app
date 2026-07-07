//
//  Theme+Gradients.swift
//  VandaApp
//
//  Háttér-gradiensek és sötét környezetek — forrás: docs/design/design-tokens.md, 2. fejezet.
//  A CSS-fokok fordítása: 180deg → fentről le; 160deg → enyhén átlós (topLeading → bottomTrailing).
//

import SwiftUI

extension Theme {

    /// A Kinézetben választható háttér-gradiensek. A fotó-háttér külön út
    /// (user kép + `Gradients.photoOverlay` + `Theme.cardOpacityOnPhoto`).
    enum BackgroundGradient: String, CaseIterable, Identifiable {
        case lavender, mint, rose, iris

        var id: String { rawValue }

        static let `default`: BackgroundGradient = .lavender

        /// Magyar név a Kinézet-képernyőhöz
        var displayName: String {
            switch self {
            case .lavender: "Levendula"
            case .mint: "Menta"
            case .rose: "Rózsa"
            case .iris: "Írisz"
            }
        }

        var gradient: LinearGradient {
            switch self {
            case .lavender:
                LinearGradient(
                    colors: [Color(hex: 0xF4F1FC), Color(hex: 0xECE7F8)],
                    startPoint: .top, endPoint: .bottom)
            case .mint:
                LinearGradient(
                    colors: [Color(hex: 0xDCF0E8), Color(hex: 0xBFE3D4)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            case .rose:
                LinearGradient(
                    colors: [Color(hex: 0xFFE7EF), Color(hex: 0xFBC9DC)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            case .iris:
                LinearGradient(
                    colors: [Color(hex: 0xE9E4FF), Color(hex: 0xC7BBF5)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }

    enum Gradients {
        /// Olvashatósági overlay a fotó-háttér fölé
        static let photoOverlay = LinearGradient(
            colors: [Color(hex: 0x3A3550, opacity: 0.05), Color(hex: 0x3A3550, opacity: 0.35)],
            startPoint: .top, endPoint: .bottom)

        /// Panik-képernyő saját, sötétebb környezete (fehér szöveggel)
        static let panic = LinearGradient(
            colors: [Color(hex: 0x5E4F86), Color(hex: 0x3E355C)],
            startPoint: .top, endPoint: .bottom)

        /// Napló-belépés sötét környezete (PIN-képernyő)
        static let journalEntry = LinearGradient(
            colors: [Color(hex: 0x48416A), Color(hex: 0x322C4C)],
            startPoint: .top, endPoint: .bottom)
    }
}
