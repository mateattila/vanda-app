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
    /// `false`, ha a mentés nem sikerült (pl. a Keychain elutasította az
    /// írást). A hívó (`FamilyLinkModel`) ezt köteles látható hibaként
    /// kezelni, NEM sikeres párosításként: a bearer token, amit itt
    /// mentenénk, egy EGYSZER-használatos párosító kódból lett kiváltva — ha
    /// csendben elveszik, a kód se nem redeem-elhető újra, se az app nem
    /// mutat valós állapotot.
    @discardableResult
    func save(_ credentials: DeviceCredentials) -> Bool
    func clear()
}

final class KeychainDeviceCredentialStore: DeviceCredentialStoring {
    static let shared = KeychainDeviceCredentialStore()

    private let service: String
    private let account: String

    /// A service/account paraméterezhető, hogy a tesztek saját, izolált
    /// Keychain-bejegyzést használhassanak az éles tárolótól elkülönítve —
    /// az alapérték az éles viselkedést őrzi.
    init(service: String = "hu.attis.VandaApp.backend", account: String = "deviceCredentials") {
        self.service = service
        self.account = account
    }

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

    @discardableResult
    func save(_ credentials: DeviceCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(credentials) else { return false }
        clear()
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        // A push-kezelés háttérben is futhat, ezért AfterFirstUnlock.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
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
    @discardableResult
    func save(_ credentials: DeviceCredentials) -> Bool {
        stored = credentials
        return true
    }
    func clear() { stored = nil }
}
