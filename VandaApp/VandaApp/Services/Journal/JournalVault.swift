//
//  JournalVault.swift
//  VandaApp
//
//  A napló zárja: beállítás (PIN + recovery-kulcs), nyitás, zárás,
//  bejegyzés-titkosítás. A tartalomkulcs csak memóriában él, amíg a napló
//  nyitva van; háttérbe kerüléskor zárunk.
//
//  Recovery-nyitás = a pecsét feltörése: visszavonhatatlan JournalAuditEvent
//  keletkezik, amit Vanda a következő nyitáskor bannerként lát (spec 4.5).
//

import CryptoKit
import Foundation
import SwiftData

@Observable
final class JournalVault {
    static let shared = JournalVault(keyStore: KeychainKeyStore())

    private let keyStore: KeyStore
    private(set) var contentKey: SymmetricKey?

    private static let pinEnvelopeKey = "journal.pinEnvelope.v1"
    private static let recoveryEnvelopeKey = "journal.recoveryEnvelope.v1"

    init(keyStore: KeyStore) {
        self.keyStore = keyStore
    }

    var isSetUp: Bool {
        keyStore.data(for: Self.pinEnvelopeKey) != nil
    }

    var isUnlocked: Bool {
        contentKey != nil
    }

    // MARK: - Beállítás

    /// Létrehozza a tartalomkulcsot és mindkét borítékot; a visszaadott
    /// recovery-kódot az app EGYSZER jeleníti meg (lezárt borítékba való).
    func setUp(pin: String) throws -> String {
        let contentKey = JournalCrypto.makeContentKey()

        let salt = JournalCrypto.makeSalt()
        let pinKEK = try JournalCrypto.deriveKEK(pin: pin, salt: salt)
        let pinEnvelope = try JournalCrypto.makeEnvelope(
            contentKey: contentKey, kek: pinKEK, salt: salt, iterations: JournalCrypto.pbkdf2Iterations)

        let recovery = JournalCrypto.makeRecoveryKey()
        let recoveryEnvelope = try JournalCrypto.makeEnvelope(
            contentKey: contentKey,
            kek: JournalCrypto.recoveryKEK(from: recovery.material),
            salt: Data(), iterations: 0)

        let encoder = JSONEncoder()
        keyStore.set(try encoder.encode(pinEnvelope), for: Self.pinEnvelopeKey)
        keyStore.set(try encoder.encode(recoveryEnvelope), for: Self.recoveryEnvelopeKey)

        self.contentKey = contentKey
        return recovery.display
    }

    // MARK: - Nyitás / zárás

    func unlock(pin: String) throws {
        guard let data = keyStore.data(for: Self.pinEnvelopeKey),
              let envelope = try? JSONDecoder().decode(JournalCrypto.Envelope.self, from: data) else {
            throw JournalCryptoError.invalidEnvelope
        }
        let kek = try JournalCrypto.deriveKEK(pin: pin, salt: envelope.salt, iterations: envelope.iterations)
        contentKey = try JournalCrypto.openEnvelope(envelope, kek: kek)
    }

    /// Recovery-kulcsos nyitás — a pecsét nyomot hagy: visszavonhatatlan
    /// audit-esemény íródik, MIELŐTT a kulcs kinyílna.
    func unlockWithRecovery(code: String, context: ModelContext) throws {
        guard let data = keyStore.data(for: Self.recoveryEnvelopeKey),
              let envelope = try? JSONDecoder().decode(JournalCrypto.Envelope.self, from: data) else {
            throw JournalCryptoError.invalidEnvelope
        }
        let material = try JournalCrypto.recoveryMaterial(from: code)
        let key = try JournalCrypto.openEnvelope(envelope, kek: JournalCrypto.recoveryKEK(from: material))

        let audit = JournalAuditEvent()
        audit.kind = .recoveryUnlock
        context.insert(audit)
        try? context.save()

        contentKey = key
    }

    /// Új PIN (nyitott naplónál — pl. recovery-nyitás után): a tartalomkulcs
    /// marad, csak a PIN-boríték cserélődik.
    func setNewPIN(_ pin: String) throws {
        guard let contentKey else { throw JournalCryptoError.wrongKey }
        let salt = JournalCrypto.makeSalt()
        let kek = try JournalCrypto.deriveKEK(pin: pin, salt: salt)
        let envelope = try JournalCrypto.makeEnvelope(
            contentKey: contentKey, kek: kek, salt: salt, iterations: JournalCrypto.pbkdf2Iterations)
        keyStore.set(try JSONEncoder().encode(envelope), for: Self.pinEnvelopeKey)
    }

    func lock() {
        contentKey = nil
    }

    #if DEBUG
    /// Fejlesztői reset: mindkét boríték törlődik, a régi bejegyzések ezután
    /// semmivel nem nyithatók. Éles buildben nincs — nyom nélkül tüntetné el
    /// a pecsétet.
    func reset() {
        keyStore.remove(Self.pinEnvelopeKey)
        keyStore.remove(Self.recoveryEnvelopeKey)
        contentKey = nil
    }
    #endif

    // MARK: - Bejegyzések

    func seal(_ payload: JournalPayload, previousEntry: JournalEntry?) throws -> JournalEntry {
        guard let contentKey else { throw JournalCryptoError.wrongKey }
        let entry = JournalEntry()
        entry.encryptedBlob = try JournalCrypto.encrypt(JSONEncoder().encode(payload), contentKey: contentKey)
        entry.previousEntryHash = previousEntry?.encryptedBlob.map(JournalCrypto.chainHash(of:))
        return entry
    }

    func open(_ entry: JournalEntry) throws -> JournalPayload {
        guard let contentKey else { throw JournalCryptoError.wrongKey }
        guard let blob = entry.encryptedBlob else { throw JournalCryptoError.invalidEnvelope }
        return try JSONDecoder().decode(JournalPayload.self, from: JournalCrypto.decrypt(blob, contentKey: contentKey))
    }

    // MARK: - Fotók (kizárólag titkosítva)

    func sealPhoto(_ imageData: Data) throws -> JournalPhoto {
        guard let contentKey else { throw JournalCryptoError.wrongKey }
        let photo = JournalPhoto()
        photo.encryptedData = try JournalCrypto.encrypt(imageData, contentKey: contentKey)
        return photo
    }

    func openPhoto(_ photo: JournalPhoto) throws -> Data {
        guard let contentKey else { throw JournalCryptoError.wrongKey }
        guard let blob = photo.encryptedData else { throw JournalCryptoError.invalidEnvelope }
        return try JournalCrypto.decrypt(blob, contentKey: contentKey)
    }
}

/// Egy bejegyzés olvasható tartalma — CSAK titkosítva tárolódik/szinkronizálódik.
nonisolated struct JournalPayload: Codable {
    var text: String = ""
    /// Sablonválaszok: kérdés → válasz(ok)
    var templateAnswers: [TemplateAnswer] = []
    /// Titkosított fotófájlok azonosítói az app konténerében (3. fázis későbbi lépése)
    var photoRefs: [String] = []
    /// Az aznapi aksi%, ha Vanda hozzácsatolta
    var moodPercent: Int?

    struct TemplateAnswer: Codable {
        var question: String = ""
        var answers: [String] = []
    }
}
