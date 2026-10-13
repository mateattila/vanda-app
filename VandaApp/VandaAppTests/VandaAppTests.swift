//
//  VandaAppTests.swift
//  VandaAppTests
//
//  A napló titkosítási rétegének tesztjei (spec 10. fejezet: kulcsderiválás,
//  hash-lánc, felnyitási napló — „ne működik-jó-lesz alapon").
//

import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import VandaApp

// MARK: - Kulcsderiválás

struct KeyDerivationTests {

    @Test func samePinAndSaltGivesSameKey() throws {
        let salt = JournalCrypto.makeSalt()
        let a = try JournalCrypto.deriveKEK(pin: "1234", salt: salt, iterations: 1_000)
        let b = try JournalCrypto.deriveKEK(pin: "1234", salt: salt, iterations: 1_000)
        #expect(a == b)
    }

    @Test func differentPinGivesDifferentKey() throws {
        let salt = JournalCrypto.makeSalt()
        let a = try JournalCrypto.deriveKEK(pin: "1234", salt: salt, iterations: 1_000)
        let b = try JournalCrypto.deriveKEK(pin: "1235", salt: salt, iterations: 1_000)
        #expect(a != b)
    }

    @Test func differentSaltGivesDifferentKey() throws {
        let a = try JournalCrypto.deriveKEK(pin: "1234", salt: JournalCrypto.makeSalt(), iterations: 1_000)
        let b = try JournalCrypto.deriveKEK(pin: "1234", salt: JournalCrypto.makeSalt(), iterations: 1_000)
        #expect(a != b)
    }
}

// MARK: - Borítékok (PIN-út + recovery-út)

struct EnvelopeTests {

    @Test func pinEnvelopeRoundtrip() throws {
        let contentKey = JournalCrypto.makeContentKey()
        let salt = JournalCrypto.makeSalt()
        let kek = try JournalCrypto.deriveKEK(pin: "4242", salt: salt, iterations: 1_000)
        let envelope = try JournalCrypto.makeEnvelope(contentKey: contentKey, kek: kek, salt: salt, iterations: 1_000)

        let reopened = try JournalCrypto.openEnvelope(envelope, kek: kek)
        #expect(reopened == contentKey)
    }

    @Test func wrongPinFailsToOpenEnvelope() throws {
        let contentKey = JournalCrypto.makeContentKey()
        let salt = JournalCrypto.makeSalt()
        let good = try JournalCrypto.deriveKEK(pin: "4242", salt: salt, iterations: 1_000)
        let bad = try JournalCrypto.deriveKEK(pin: "0000", salt: salt, iterations: 1_000)
        let envelope = try JournalCrypto.makeEnvelope(contentKey: contentKey, kek: good, salt: salt, iterations: 1_000)

        #expect(throws: JournalCryptoError.self) {
            _ = try JournalCrypto.openEnvelope(envelope, kek: bad)
        }
    }

    @Test func recoveryCodeRoundtrip() throws {
        let recovery = JournalCrypto.makeRecoveryKey()
        let parsed = try JournalCrypto.recoveryMaterial(from: recovery.display)
        #expect(parsed == recovery.material)
    }

    @Test func recoveryCodeParsingIsForgiving() throws {
        let recovery = JournalCrypto.makeRecoveryKey()
        // kisbetűvel, kötőjelek helyett szóközökkel is ugyanazt kell adnia
        let sloppy = recovery.display
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
        let parsed = try JournalCrypto.recoveryMaterial(from: sloppy)
        #expect(parsed == recovery.material)
    }

    @Test func recoveryCodeToleratesAmbiguousCharacters() throws {
        let recovery = JournalCrypto.makeRecoveryKey()
        // O→0, I/L→1 elgépelések
        let typo = recovery.display
            .replacingOccurrences(of: "0", with: "O")
            .replacingOccurrences(of: "1", with: "I")
        let parsed = try JournalCrypto.recoveryMaterial(from: typo)
        #expect(parsed == recovery.material)
    }

    @Test func invalidRecoveryCodeThrows() {
        #expect(throws: JournalCryptoError.self) {
            _ = try JournalCrypto.recoveryMaterial(from: "EZ-NEM-JO-KOD")
        }
    }

    @Test func recoveryEnvelopeRoundtrip() throws {
        let contentKey = JournalCrypto.makeContentKey()
        let recovery = JournalCrypto.makeRecoveryKey()
        let kek = JournalCrypto.recoveryKEK(from: recovery.material)
        let envelope = try JournalCrypto.makeEnvelope(contentKey: contentKey, kek: kek, salt: Data(), iterations: 0)

        let material = try JournalCrypto.recoveryMaterial(from: recovery.display)
        let reopened = try JournalCrypto.openEnvelope(envelope, kek: JournalCrypto.recoveryKEK(from: material))
        #expect(reopened == contentKey)
    }
}

// MARK: - Bejegyzés-titkosítás + hash-lánc

struct ChainTests {

    @Test func encryptDecryptRoundtrip() throws {
        let key = JournalCrypto.makeContentKey()
        let payload = Data("Kedves Napló! 🌙".utf8)
        let blob = try JournalCrypto.encrypt(payload, contentKey: key)
        #expect(try JournalCrypto.decrypt(blob, contentKey: key) == payload)
    }

    @Test func wrongKeyFailsToDecrypt() throws {
        let blob = try JournalCrypto.encrypt(Data("titok".utf8), contentKey: JournalCrypto.makeContentKey())
        #expect(throws: JournalCryptoError.self) {
            _ = try JournalCrypto.decrypt(blob, contentKey: JournalCrypto.makeContentKey())
        }
    }

    @Test func tamperedBlobFailsToDecrypt() throws {
        let key = JournalCrypto.makeContentKey()
        var blob = try JournalCrypto.encrypt(Data("titok".utf8), contentKey: key)
        blob[blob.count - 1] ^= 0xFF
        #expect(throws: JournalCryptoError.self) {
            _ = try JournalCrypto.decrypt(blob, contentKey: key)
        }
    }

    private func makeChain(count: Int, key: SymmetricKey) throws -> (blobs: [Data], hashes: [Data?]) {
        var blobs: [Data] = []
        var hashes: [Data?] = []
        for index in 0..<count {
            let blob = try JournalCrypto.encrypt(Data("bejegyzés \(index)".utf8), contentKey: key)
            hashes.append(blobs.last.map(JournalCrypto.chainHash(of:)))
            blobs.append(blob)
        }
        return (blobs, hashes)
    }

    @Test func intactChainVerifies() throws {
        let chain = try makeChain(count: 5, key: JournalCrypto.makeContentKey())
        #expect(JournalCrypto.verifyChain(blobs: chain.blobs, previousHashes: chain.hashes).isEmpty)
    }

    @Test func replacedEntryBreaksChain() throws {
        let key = JournalCrypto.makeContentKey()
        var chain = try makeChain(count: 5, key: key)
        // a 2. bejegyzés cseréje (mintha valaki átírta volna)
        chain.blobs[2] = try JournalCrypto.encrypt(Data("hamis".utf8), contentKey: key)
        let broken = JournalCrypto.verifyChain(blobs: chain.blobs, previousHashes: chain.hashes)
        #expect(broken.contains(3)) // a KÖVETKEZŐ elem previous-hash-e bukik
    }

    @Test func removedEntryBreaksChain() throws {
        let key = JournalCrypto.makeContentKey()
        var chain = try makeChain(count: 5, key: key)
        // a 2. bejegyzés törlése (mintha korábbi állapotot állítottak volna vissza)
        chain.blobs.remove(at: 2)
        chain.hashes.remove(at: 2)
        #expect(!JournalCrypto.verifyChain(blobs: chain.blobs, previousHashes: chain.hashes).isEmpty)
    }

    @Test func reorderedEntriesBreakChain() throws {
        var chain = try makeChain(count: 5, key: JournalCrypto.makeContentKey())
        chain.blobs.swapAt(1, 3)
        #expect(!JournalCrypto.verifyChain(blobs: chain.blobs, previousHashes: chain.hashes).isEmpty)
    }
}

// MARK: - A zár (vault) + felnyitási napló

@MainActor
struct VaultTests {

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: JournalAuditEvent.self, configurations: configuration)
        return ModelContext(container)
    }

    @Test func setupUnlockLockCycle() throws {
        let vault = JournalVault(keyStore: InMemoryKeyStore())
        #expect(!vault.isSetUp)

        let recoveryCode = try vault.setUp(pin: "1234")
        #expect(vault.isSetUp)
        #expect(vault.isUnlocked)
        #expect(recoveryCode.count == 39) // 32 karakter + 7 kötőjel

        vault.lock()
        #expect(!vault.isUnlocked)

        #expect(throws: (any Error).self) {
            try vault.unlock(pin: "9999")
        }
        #expect(!vault.isUnlocked)

        try vault.unlock(pin: "1234")
        #expect(vault.isUnlocked)
    }

    @Test func resetReturnsVaultToNotSetUp() throws {
        let vault = JournalVault(keyStore: InMemoryKeyStore())
        let recoveryCode = try vault.setUp(pin: "1234")

        vault.reset()
        #expect(!vault.isSetUp)
        #expect(!vault.isUnlocked)
        #expect(throws: (any Error).self) {
            try vault.unlock(pin: "1234")
        }
        #expect(throws: (any Error).self) {
            try vault.unlockWithRecovery(code: recoveryCode, context: try makeContext())
        }
    }

    @Test func recoveryUnlockWritesAuditEvent() throws {
        let vault = JournalVault(keyStore: InMemoryKeyStore())
        let recoveryCode = try vault.setUp(pin: "1234")
        vault.lock()

        let context = try makeContext()
        try vault.unlockWithRecovery(code: recoveryCode, context: context)
        #expect(vault.isUnlocked)

        let events = try context.fetch(FetchDescriptor<JournalAuditEvent>())
        #expect(events.count == 1)
        #expect(events.first?.kind == .recoveryUnlock)
        #expect(events.first?.acknowledgedAt == nil)
    }

    @Test func failedRecoveryDoesNotUnlockAndDoesNotLog() throws {
        let vault = JournalVault(keyStore: InMemoryKeyStore())
        _ = try vault.setUp(pin: "1234")
        vault.lock()

        let context = try makeContext()
        #expect(throws: (any Error).self) {
            try vault.unlockWithRecovery(code: "AAAA-AAAA-AAAA-AAAA-AAAA-AAAA-AAAA-AAAA", context: context)
        }
        #expect(!vault.isUnlocked)
        let events = try context.fetch(FetchDescriptor<JournalAuditEvent>())
        #expect(events.isEmpty)
    }

    @Test func newPINAfterRecoveryKeepsContent() throws {
        let vault = JournalVault(keyStore: InMemoryKeyStore())
        let recoveryCode = try vault.setUp(pin: "1234")

        var payload = JournalPayload()
        payload.text = "első bejegyzés"
        let entry = try vault.seal(payload, previousEntry: nil)
        vault.lock()

        let context = try makeContext()
        try vault.unlockWithRecovery(code: recoveryCode, context: context)
        try vault.setNewPIN("5678")
        vault.lock()

        #expect(throws: (any Error).self) {
            try vault.unlock(pin: "1234") // a régi PIN már nem jó
        }
        try vault.unlock(pin: "5678")
        #expect(try vault.open(entry).text == "első bejegyzés")
    }

    @Test func sealSetsChainHash() throws {
        let vault = JournalVault(keyStore: InMemoryKeyStore())
        _ = try vault.setUp(pin: "1234")

        var first = JournalPayload()
        first.text = "első"
        var second = JournalPayload()
        second.text = "második"
        let entryA = try vault.seal(first, previousEntry: nil)
        let entryB = try vault.seal(second, previousEntry: entryA)

        #expect(entryA.previousEntryHash == nil)
        #expect(entryB.previousEntryHash == JournalCrypto.chainHash(of: entryA.encryptedBlob!))
        #expect(try vault.open(entryB).text == "második")
    }
}
