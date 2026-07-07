//
//  KeyStore.swift
//  VandaApp
//
//  A borítékok tárolója. Éles implementáció: Keychain, iCloud Keychain
//  szinkronnal (a kulcsok Vanda eszközei közt szinkronizálódnak, szerverre
//  SOHA nem kerülnek — spec 4.5). A tesztek memóriabeli implementációt kapnak.
//

import Foundation
import Security

protocol KeyStore {
    func data(for key: String) -> Data?
    func set(_ data: Data, for key: String)
    func remove(_ key: String)
}

final class KeychainKeyStore: KeyStore {
    private let service = "hu.attis.VandaApp.journal"

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
    }

    func data(for key: String) -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    func set(_ data: Data, for key: String) {
        remove(key)
        var attributes = baseQuery(for: key)
        attributes[kSecAttrSynchronizable as String] = true
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func remove(_ key: String) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }
}

/// Tesztekhez és previewhoz.
final class InMemoryKeyStore: KeyStore {
    private var storage: [String: Data] = [:]

    func data(for key: String) -> Data? { storage[key] }
    func set(_ data: Data, for key: String) { storage[key] = data }
    func remove(_ key: String) { storage[key] = nil }
}
