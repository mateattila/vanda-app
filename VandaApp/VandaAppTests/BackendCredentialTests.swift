//
//  BackendCredentialTests.swift
//  VandaAppTests
//
//  A backend-hitelesítés tárolójának és a hoszt-konfigurációnak a tesztjei (4.2b).
//

import Foundation
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
