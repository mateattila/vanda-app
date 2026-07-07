//
//  ThemeSettings.swift
//  VandaApp
//
//  Spec 3. + 2.1, design-tokens 2. és 5. fejezet: Vanda testreszabása —
//  háttér (gradiens vagy saját fotó) + kiemelőszín. CloudKiten szinkronizálódik,
//  így az iPhone és az iPad kinézete együtt mozog.
//

import Foundation
import SwiftData
import SwiftUI

enum ThemeBackgroundKind: String, Codable {
    case gradient
    case photo
}

enum ThemeScope: String, Codable {
    case global
    // képernyőnkénti hatókör: későbbi bővítés (spec 2.1)
}

@Model
final class ThemeSettings {
    var backgroundKindRaw: String = ThemeBackgroundKind.gradient.rawValue
    /// `Theme.BackgroundGradient` rawValue
    var gradientID: String = Theme.BackgroundGradient.default.rawValue
    /// Saját fotó-háttér (fotó-háttérnél overlay + 0.9-es kártya-opacitás jár hozzá)
    @Attribute(.externalStorage) var photoData: Data? = nil
    /// Kiemelőszín 0xRRGGBB-ként — presetek mellett bármilyen szín megengedett
    var accentHex: Int = 0x8A7DE0
    var scopeRaw: String = ThemeScope.global.rawValue

    init() {}
}

extension ThemeSettings {
    var backgroundKind: ThemeBackgroundKind {
        get { ThemeBackgroundKind(rawValue: backgroundKindRaw) ?? .gradient }
        set { backgroundKindRaw = newValue.rawValue }
    }

    var gradient: Theme.BackgroundGradient {
        get { Theme.BackgroundGradient(rawValue: gradientID) ?? .default }
        set { gradientID = newValue.rawValue }
    }

    var accentColor: Color {
        get { Color(hex: UInt32(clamping: accentHex)) }
        set { accentHex = Int(newValue.hexValue ?? Theme.Accent.defaultHex) }
    }

    /// Aktív fotó-háttér van-e (ilyenkor a kártyák 0.9-es opacitást kapnak)
    var usesPhotoBackground: Bool {
        backgroundKind == .photo && photoData != nil
    }

    /// Kártya-felületszín az aktuális háttérhez
    var cardSurface: Color {
        Color.surface.opacity(usesPhotoBackground ? Theme.cardOpacityOnPhoto : 1)
    }

    /// A meglévő beállítás, vagy ha még nincs, egy frissen létrehozott alapértelmezett.
    /// (CloudKit-szinkronnál előfordulhat átmeneti duplikátum — a determinisztikus
    /// sorrend miatt minden eszköz ugyanazt az elsőt használja.)
    static func ensureCurrent(in context: ModelContext) -> ThemeSettings {
        var descriptor = FetchDescriptor<ThemeSettings>(sortBy: [SortDescriptor(\.accentHex)])
        descriptor.fetchLimit = 1
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        let settings = ThemeSettings()
        context.insert(settings)
        return settings
    }
}
