//
//  Theme+Colors.swift
//  VandaApp
//
//  Szín-tokenek — forrás: docs/design/design-tokens.md, 2. fejezet.
//

import SwiftUI
import UIKit

extension Color {
    /// Szín 0xRRGGBB hex értékből.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    // MARK: Alap (fix, téma-szintű)

    /// Elsődleges szöveg, ikonok, sötét gombok
    static let ink = Color(hex: 0x3A3550)
    /// Másodlagos szöveg, feliratok
    static let inkMuted = Color(hex: 0x8A82A8)
    /// Címkék, placeholder, uppercase kis feliratok
    static let inkFaint = Color(hex: 0xA69FC0)
    /// Kártyák háttere
    static let surface = Color(hex: 0xFFFFFF)
    /// Inaktív chip / segment háttér
    static let surfaceTint = Color(hex: 0xEEE9F6)
    /// Elválasztó vonalak
    static let hairline = Color(hex: 0x3A3550, opacity: 0.10)

    // MARK: Zóna-színek (hangulatbarométer) — FIXEK, nem témázhatók

    /// „bírom"
    static let zoneGreen = Color(hex: 0x5FB89C)
    static let zoneGreenLight = Color(hex: 0x86CBB5)
    /// „fárad" — kitöltés
    static let zoneOrange = Color(hex: 0xF4CE96)
    /// „fárad" — jelző
    static let zoneOrangeStrong = Color(hex: 0xF2A65A)
    /// „kimerül" — kitöltés
    static let zoneRed = Color(hex: 0xEDA6A0)
    /// „kimerül" — jelző
    static let zoneRedStrong = Color(hex: 0xE06A5E)

    /// A szín 0xRRGGBB hex értéke (sRGB-be konvertálva) — a ThemeSettings perzisztáláshoz.
    var hexValue: UInt32? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        func channel(_ value: CGFloat) -> UInt32 {
            UInt32((min(max(value, 0), 1) * 255).rounded())
        }
        return channel(red) << 16 | channel(green) << 8 | channel(blue)
    }

    // MARK: Panik-képernyő (sötét környezet)

    /// Chip / eszköz-felület a panik-képernyő sötét hátterén
    static let panicChipSurface = Color.white.opacity(0.15)
}

extension Theme {
    /// Kiemelőszín — USER-VÁLASZTHATÓ (a perzisztálás a `ThemeSettings` dolga,
    /// itt csak az alapérték és a preset sor van). Az accent viszi: Panik gomb,
    /// töltés-csík, aktív tab, elsődleges gombok, kiemelt kártya, napló-progress.
    enum Accent {
        /// Periwinkle — alapértelmezett
        static let defaultHex: UInt32 = 0x8A7DE0
        /// Preset sor a Kinézet-képernyőhöz; szabad választó (color picker) is megengedett.
        static let presetHexes: [UInt32] = [0x8A7DE0, 0x5FB89C, 0xEC6F9E, 0xF2A65A, 0x6FA8E8]

        static var `default`: Color { Color(hex: defaultHex) }
        static var presets: [Color] { presetHexes.map { Color(hex: $0) } }
    }
}
