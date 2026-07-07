//
//  Journal.swift
//  VandaApp
//
//  Spec 3. + 4.5: napló („pecsétes zár"). A tartalom MINDENHOL csak titkosított
//  blobként létezik — a titkosítási réteg (PIN, kulcsderiválás, hash-lánc,
//  recovery) a 3. fázisban épül rá; itt csak a perzisztens váz van.
//

import Foundation
import SwiftData

@Model
final class JournalEntry {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    /// AES-GCM titkosított tartalom: szöveg + sablonválaszok + fotóhivatkozások (3. fázis)
    @Attribute(.externalStorage) var encryptedBlob: Data? = nil
    /// Hash-lánc: az előző bejegyzés hash-e — korábbi állapot visszaállítása így észrevehető
    var previousEntryHash: Data? = nil

    init() {}
}

enum JournalAuditKind: String, Codable {
    /// A naplót recovery-kulccsal nyitották meg
    case recoveryUnlock
}

@Model
final class JournalAuditEvent {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var kindRaw: String = JournalAuditKind.recoveryUnlock.rawValue
    /// Vanda mikor nyugtázta a bannert — az esemény maga VISSZAVONHATATLAN,
    /// az app soha nem törli, csak a banner tűnik el.
    var acknowledgedAt: Date? = nil

    init() {}

    var kind: JournalAuditKind {
        get { JournalAuditKind(rawValue: kindRaw) ?? .recoveryUnlock }
        set { kindRaw = newValue.rawValue }
    }
}

/// Egy sablonkérdés — választós, nem kifejtős (chipek / skála / emoji-választó)
nonisolated struct TemplateQuestion: Codable {
    enum Kind: String, Codable {
        case chips, scale, emoji
    }

    var text: String = ""
    var kind: Kind = .chips
    /// Chipeknél a választék; emoji-skálánál az emojik; skálánál a végpont-feliratok
    var options: [String] = []
    /// Chipeknél: több válasz is jelölhető-e („többet is")
    var allowsMultiple: Bool = false
}

/// Naplóhoz csatolt fotó — KIZÁRÓLAG titkosítva (a kulcs a napló tartalomkulcsa).
/// CloudKiten titkosított blobként szinkronizálódik Vanda eszközei közt.
@Model
final class JournalPhoto {
    var id: UUID = UUID()
    @Attribute(.externalStorage) var encryptedData: Data? = nil
    var createdAt: Date = Date()

    init() {}
}

@Model
final class JournalTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var questions: [TemplateQuestion] = []
    var isActive: Bool = true

    init() {}
}
