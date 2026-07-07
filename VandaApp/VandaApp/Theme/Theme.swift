//
//  Theme.swift
//  VandaApp
//
//  Design-tokenek — forrás: docs/design/design-tokens.md („Soft Dusk").
//  A UI ezekből építkezik; nyers hex/pt érték ne szóródjon szét a view-kban.
//

import SwiftUI

enum Theme {

    // MARK: - Forma & tér (design-tokens 4. fejezet)

    enum Radius {
        /// Kártya (22–26 pt)
        static let card: CGFloat = 24
        /// Kis kártya / chip (15–20 pt)
        static let cardSmall: CGFloat = 18
        /// Gomb (16–20 pt)
        static let button: CGFloat = 18
        /// Chip
        static let chip: CGFloat = 16
        /// Ikon-konténer (12–14 pt)
        static let iconContainer: CGFloat = 13
    }

    enum Spacing {
        /// Képernyő oldalmargó
        static let screenMargin: CGFloat = 20
        /// Kártyák közti gap (13–16 pt)
        static let cardGap: CGFloat = 14
        /// Kártya belső padding (15–18 pt)
        static let cardPadding: CGFloat = 16
        /// Chip padding (8–9 × 14–15 pt)
        static let chipVertical: CGFloat = 8
        static let chipHorizontal: CGFloat = 14
    }

    // MARK: - Fotó-háttér (design-tokens 2. fejezet)

    /// Fotó-háttérnél a kártyák nem tömör fehérek, hogy a kép átüssön,
    /// de a szöveg olvasható maradjon.
    static let cardOpacityOnPhoto: Double = 0.9

    // MARK: - Mozgás (design-tokens 6. fejezet)

    enum Motion {
        /// Lüktetés kizárólag a Panik gombon és a lélegző körön —
        /// visszafogott: scale 1↔1.06, ~2.6–3.5 s ciklus.
        static let pulseScale: CGFloat = 1.06
        static let pulsePeriod: TimeInterval = 3.0
    }
}

// MARK: - Árnyék (elevation)

extension View {
    /// Lágy, lila árnyalatú, alátett árnyék. Kemény fekete drop shadow kerülendő.
    /// CSS-referencia: `0 10px 26px -14px rgba(58,53,80,0.28)`
    func softShadow() -> some View {
        shadow(color: Color.ink.opacity(0.28), radius: 13, x: 0, y: 8)
    }
}
