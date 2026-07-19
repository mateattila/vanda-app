//
//  DeviceCredentialStore.swift
//  VandaApp
//
//  A backend-hitelesítés tárolója. Keychain, de a napló KeyStore-jával
//  ellentétben SZÁNDÉKOSAN NEM iCloud-szinkronizált: a modellben minden eszköz
//  önálló identitás, saját APNs-tokennel — közös tokennel a két eszköz
//  felülírná egymás APNs-tokenjét, és a szerver nem tudná megkülönböztetni őket.
//

import Foundation
import Security

protocol DeviceCredentialStoring: AnyObject {
    func load() -> DeviceCredentials?
    func save(_ credentials: DeviceCredentials)
    func clear()
}

final class KeychainDeviceCredentialStore: DeviceCredentialStoring {
    static let shared = KeychainDeviceCredentialStore()

    private let service = "hu.attis.VandaApp.backend"
    private let account = "deviceCredentials"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    func load() -> DeviceCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(DeviceCredentials.self, from: data)
    }

    func save(_ credentials: DeviceCredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        clear()
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        // A push-kezelés háttérben is futhat, ezért AfterFirstUnlock.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// Tesztekhez és previewhoz.
final class InMemoryDeviceCredentialStore: DeviceCredentialStoring {
    private var stored: DeviceCredentials?

    init(_ initial: DeviceCredentials? = nil) { stored = initial }

    func load() -> DeviceCredentials? { stored }
    func save(_ credentials: DeviceCredentials) { stored = credentials }
    func clear() { stored = nil }
}
