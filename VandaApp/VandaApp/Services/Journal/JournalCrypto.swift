//
//  JournalCrypto.swift
//  VandaApp
//
//  A „pecsétes zár" kriptográfiai magja (spec 4.5 és 6. fejezet).
//  Tiszta függvények — a unit tesztek ezt a réteget fedik le.
//
//  Séma: a tartalomkulcs (256 bit, véletlen) két „borítékban" van:
//   1. PIN-út:      KEK = PBKDF2-HMAC-SHA256(PIN, só, 600k iteráció)
//   2. Recovery-út: KEK = HKDF-SHA256(160 bit véletlen recovery-kulcs)
//  Mindkét boríték AES-GCM-mel zárja a tartalomkulcsot; a bejegyzések
//  AES-GCM-mel titkosítódnak, és hash-láncba fűződnek.
//

import CommonCrypto
import CryptoKit
import Foundation

enum JournalCryptoError: Error {
    case keyDerivationFailed
    case invalidEnvelope
    case wrongKey
    case invalidRecoveryCode
}

nonisolated enum JournalCrypto {

    // MARK: - Kulcsderiválás (PIN-út)

    static let pbkdf2Iterations = 600_000

    static func deriveKEK(pin: String, salt: Data, iterations: Int = pbkdf2Iterations) throws -> SymmetricKey {
        var derived = Data(count: 32)
        let pinData = Data(pin.utf8)
        let status = derived.withUnsafeMutableBytes { derivedPtr in
            salt.withUnsafeBytes { saltPtr in
                pinData.withUnsafeBytes { pinPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pinPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                        pinData.count,
                        saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw JournalCryptoError.keyDerivationFailed }
        return SymmetricKey(data: derived)
    }

    static func makeSalt() -> Data {
        Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
    }

    static func makeContentKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    // MARK: - Boríték (a tartalomkulcs be- és kicsomagolása)

    struct Envelope: Codable {
        var version: Int = 1
        var salt: Data
        var iterations: Int
        var sealed: Data
    }

    static func makeEnvelope(contentKey: SymmetricKey, kek: SymmetricKey, salt: Data, iterations: Int) throws -> Envelope {
        let keyData = contentKey.withUnsafeBytes { Data($0) }
        let sealed = try AES.GCM.seal(keyData, using: kek).combined!
        return Envelope(salt: salt, iterations: iterations, sealed: sealed)
    }

    static func openEnvelope(_ envelope: Envelope, kek: SymmetricKey) throws -> SymmetricKey {
        guard let box = try? AES.GCM.SealedBox(combined: envelope.sealed),
              let keyData = try? AES.GCM.open(box, using: kek) else {
            throw JournalCryptoError.wrongKey
        }
        return SymmetricKey(data: keyData)
    }

    // MARK: - Recovery-kulcs (a pecsét)

    private static let base32Alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// 160 bit véletlen → 32 karakteres Crockford-Base32, 4-es csoportokban.
    /// A megjelenített szöveg EGYSZER látszik; utána csak a boríték őrzi.
    static func makeRecoveryKey() -> (display: String, material: Data) {
        let material = Data((0..<20).map { _ in UInt8.random(in: .min ... .max) })
        return (display: encodeBase32(material), material: material)
    }

    static func recoveryKEK(from material: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: material),
            info: Data("vanda-journal-recovery".utf8),
            outputByteCount: 32
        )
    }

    /// A beírt recovery-kód visszafejtése (kötőjelek, kisbetűk, O/I/L elgépelések tolerálva).
    static func recoveryMaterial(from input: String) throws -> Data {
        let cleaned = input.uppercased()
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "I", with: "1")
            .replacingOccurrences(of: "L", with: "1")
            .filter { base32Alphabet.contains($0) }
        guard cleaned.count == 32, let material = decodeBase32(cleaned) else {
            throw JournalCryptoError.invalidRecoveryCode
        }
        return material
    }

    private static func encodeBase32(_ data: Data) -> String {
        var bits = 0, value = 0
        var output = ""
        for byte in data {
            value = (value << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                output.append(base32Alphabet[(value >> (bits - 5)) & 31])
                bits -= 5
            }
        }
        if bits > 0 {
            output.append(base32Alphabet[(value << (5 - bits)) & 31])
        }
        // 4-es csoportok kötőjellel
        return stride(from: 0, to: output.count, by: 4).map {
            let start = output.index(output.startIndex, offsetBy: $0)
            let end = output.index(start, offsetBy: min(4, output.count - $0))
            return String(output[start..<end])
        }.joined(separator: "-")
    }

    private static func decodeBase32(_ string: String) -> Data? {
        var bits = 0, value = 0
        var output = Data()
        for char in string {
            guard let index = base32Alphabet.firstIndex(of: char) else { return nil }
            value = (value << 5) | index
            bits += 5
            if bits >= 8 {
                output.append(UInt8((value >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        return output
    }

    // MARK: - Bejegyzés-titkosítás + hash-lánc

    static func encrypt(_ payload: Data, contentKey: SymmetricKey) throws -> Data {
        try AES.GCM.seal(payload, using: contentKey).combined!
    }

    static func decrypt(_ blob: Data, contentKey: SymmetricKey) throws -> Data {
        guard let box = try? AES.GCM.SealedBox(combined: blob),
              let payload = try? AES.GCM.open(box, using: contentKey) else {
            throw JournalCryptoError.wrongKey
        }
        return payload
    }

    /// A lánc: minden bejegyzés az ELŐZŐ bejegyzés blobjának hash-ét hordozza —
    /// egy korábbi állapot visszaállítása vagy egy elem cseréje így észrevehető.
    static func chainHash(of blob: Data) -> Data {
        Data(SHA256.hash(data: blob))
    }

    /// Végigellenőrzi a láncot; a hibás indexeket adja vissza (üres = ép).
    static func verifyChain(blobs: [Data], previousHashes: [Data?]) -> [Int] {
        var broken: [Int] = []
        for index in blobs.indices {
            let expected: Data? = index == 0 ? nil : chainHash(of: blobs[index - 1])
            if previousHashes[index] != expected {
                broken.append(index)
            }
        }
        return broken
    }
}
