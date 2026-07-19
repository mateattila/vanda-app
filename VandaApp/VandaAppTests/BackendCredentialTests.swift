//
//  BackendCredentialTests.swift
//  VandaAppTests
//
//  A backend-hitelesítés tárolójának és a hoszt-konfigurációnak a tesztjei (4.2b).
//

import Foundation
import Security
import Testing
@testable import VandaApp

struct DeviceCredentialStoreTests {

    private func sample(role: AppRole = .child) -> DeviceCredentials {
        DeviceCredentials(
            familyId: "fam-1",
            deviceId: "dev-1",
            token: "titkos-token",
            role: role,
            deviceName: "Vanda telefonja"
        )
    }

    @Test func emptyStoreLoadsNothing() {
        let store = InMemoryDeviceCredentialStore()
        #expect(store.load() == nil)
    }

    @Test func savedCredentialsComeBackUnchanged() {
        let store = InMemoryDeviceCredentialStore()
        store.save(sample())
        #expect(store.load() == sample())
    }

    @Test func savingTwiceKeepsTheNewerValue() {
        let store = InMemoryDeviceCredentialStore()
        store.save(sample())
        store.save(sample(role: .parent))
        #expect(store.load()?.role == .parent)
    }

    @Test func clearRemovesEverything() {
        let store = InMemoryDeviceCredentialStore()
        store.save(sample())
        store.clear()
        #expect(store.load() == nil)
    }

    @Test func credentialsSurviveJSONRoundTrip() throws {
        let data = try JSONEncoder().encode(sample())
        let decoded = try JSONDecoder().decode(DeviceCredentials.self, from: data)
        #expect(decoded == sample())
    }
}

// MARK: - KeychainDeviceCredentialStore (valódi Keychain, szimulátoron)
//
// Az InMemoryDeviceCredentialStore fenti tesztjei nem futtatják soha a valódi
// KeychainDeviceCredentialStore-t, így egy regresszió (pl. visszaállított
// iCloud-szinkron) semmit nem buktatna el. Ez a struct a valódi Keychainen
// keresztül teszteli a tárolót — saját service/account alatt, hogy ne
// ütközzön az éles app Keychain-bejegyzésével.
//
// A Swift Testing alapból PÁRHUZAMOSAN futtatja egy suite @Test metódusait,
// úgyhogy egy közös, fix account-tal a négy teszt versenyhelyzetbe kerülne
// egymással a valódi Keychainen (ezt menet közben meg is figyeltük: teljes
// suite-futtatáskor `saveThenLoadRoundTrips` időnként elbukott, mert egy
// másik teszt `clear()`-je/`save()`-je közbeszólt). Ezért minden struct-
// példány (= minden teszt) egyedi, UUID-alapú account-ot kap az init()-ben —
// így a tesztek nemcsak sorrend-, hanem versenyhelyzet-függetlenek is, és
// minden teszt önmagát takarítja a `defer`-rel.
struct KeychainDeviceCredentialStoreTests {

    private let service = "hu.attis.VandaApp.backend.tests"
    private let account = "deviceCredentials.tests." + UUID().uuidString

    private func makeStore() -> KeychainDeviceCredentialStore {
        KeychainDeviceCredentialStore(service: service, account: account)
    }

    private func sample(role: AppRole = .child) -> DeviceCredentials {
        DeviceCredentials(
            familyId: "fam-1",
            deviceId: "dev-1",
            token: "titkos-token",
            role: role,
            deviceName: "Vanda telefonja"
        )
    }

    /// Nyers Keychain-lekérdezés a megadott synchronizable-értékkel — közvetlenül
    /// a Security-keretrendszeren keresztül, a tárolót megkerülve, hogy a
    /// synchronizable-attribútumot ténylegesen a szerveren tárolt értékből
    /// olvassuk vissza, ne a store belső logikájából következtessük ki.
    private func itemExists(synchronizable: Bool) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synchronizable,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    // Az account egyedi, de az init() itt is takarít ELŐTTE (defenzíven,
    // ha egy korábbi futás megszakadt volna a takarítás előtt), a
    // `defer { store.clear() }` pedig minden tesztben UTÁNA.
    init() {
        makeStore().clear()
    }

    @Test func saveThenLoadRoundTrips() {
        let store = makeStore()
        defer { store.clear() }
        store.save(sample())
        #expect(store.load() == sample())
    }

    @Test func savingTwiceKeepsTheNewerValue() {
        let store = makeStore()
        defer { store.clear() }
        store.save(sample())
        store.save(sample(role: .parent))
        #expect(store.load()?.role == .parent)
    }

    @Test func clearThenLoadIsNil() {
        let store = makeStore()
        defer { store.clear() }
        store.save(sample())
        store.clear()
        #expect(store.load() == nil)
    }

    /// A lényeg: a mentett bejegyzés semmiképp nem lehet iCloud-szinkronizált.
    /// Közvetlen Keychain-lekérdezéssel ellenőrizzük, nem a store API-ján
    /// keresztül — így akkor is elbukna, ha a `save`/`load` implementáció
    /// hallgatólagosan "Any" synchronizable-lekérdezést használna.
    @Test func savedItemIsNotSynchronizable() {
        let store = makeStore()
        defer { store.clear() }
        store.save(sample())

        #expect(itemExists(synchronizable: false) == true)
        #expect(itemExists(synchronizable: true) == false)
    }
}

struct BackendConfigTests {

    @Test func placeholderHostCountsAsUnconfigured() {
        #expect(BackendConfig.isConfigured(host: BackendConfig.placeholderHost) == false)
    }

    @Test func emptyHostCountsAsUnconfigured() {
        #expect(BackendConfig.isConfigured(host: "") == false)
    }

    @Test func realHostCountsAsConfigured() {
        #expect(BackendConfig.isConfigured(host: "vanda.attis.workers.dev"))
    }

    @Test func hostBecomesHTTPSURL() {
        #expect(BackendConfig.url(forHost: "vanda.attis.workers.dev")
                == URL(string: "https://vanda.attis.workers.dev"))
    }

    @Test func unconfiguredHostGivesNoURL() {
        #expect(BackendConfig.url(forHost: BackendConfig.placeholderHost) == nil)
    }
}
