//
//  PushRegistrarTests.swift
//  VandaAppTests
//
//  Az APNs-token feltöltésének tesztjei: a token és a párosítás bármilyen
//  sorrendben érkezhet, és változatlan token nem generál felesleges hívást.
//

import Foundation
import Testing
@testable import VandaApp

private final class SpyUploader: PushUploader {
    var uploaded: [(apnsToken: String, token: String)] = []
    var nextError: BackendError?

    func uploadAPNsToken(_ apnsToken: String, token: String) async throws {
        if let nextError { throw nextError }
        uploaded.append((apnsToken, token))
    }
}

private func makeDefaults() -> UserDefaults {
    let suite = "PushRegistrarTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

private let credentials = DeviceCredentials(
    familyId: "f1", deviceId: "d1", token: "titkos", role: .parent, deviceName: "Anya telefonja"
)

struct PushRegistrarTests {

    @Test func hexEncodingMatchesAPNsFormat() {
        let data = Data([0x0A, 0xFF, 0x10])
        #expect(PushRegistrar.hexString(from: data) == "0aff10")
    }

    @Test func tokenArrivingAfterPairingIsUploaded() async {
        let uploader = SpyUploader()
        let registrar = PushRegistrar(
            uploader: uploader,
            store: InMemoryDeviceCredentialStore(credentials),
            defaults: makeDefaults()
        )
        registrar.didReceive(deviceTokenHex: "abcd")
        await registrar.flush()
        #expect(uploader.uploaded.count == 1)
        #expect(uploader.uploaded.first?.apnsToken == "abcd")
        #expect(uploader.uploaded.first?.token == "titkos")
    }

    @Test func tokenArrivingBeforePairingWaitsThenUploads() async {
        let uploader = SpyUploader()
        let store = InMemoryDeviceCredentialStore()
        let registrar = PushRegistrar(uploader: uploader, store: store, defaults: makeDefaults())

        registrar.didReceive(deviceTokenHex: "abcd")
        await registrar.flush()
        #expect(uploader.uploaded.isEmpty)

        store.save(credentials)
        await registrar.flush()
        #expect(uploader.uploaded.count == 1)
    }

    @Test func unchangedTokenIsNotUploadedTwice() async {
        let uploader = SpyUploader()
        let registrar = PushRegistrar(
            uploader: uploader,
            store: InMemoryDeviceCredentialStore(credentials),
            defaults: makeDefaults()
        )
        registrar.didReceive(deviceTokenHex: "abcd")
        await registrar.flush()
        await registrar.flush()
        #expect(uploader.uploaded.count == 1)
    }

    @Test func changedTokenIsUploadedAgain() async {
        let uploader = SpyUploader()
        let registrar = PushRegistrar(
            uploader: uploader,
            store: InMemoryDeviceCredentialStore(credentials),
            defaults: makeDefaults()
        )
        registrar.didReceive(deviceTokenHex: "abcd")
        await registrar.flush()
        registrar.didReceive(deviceTokenHex: "ef01")
        await registrar.flush()
        #expect(uploader.uploaded.map(\.apnsToken) == ["abcd", "ef01"])
    }

    @Test func failedUploadIsRetriedOnTheNextFlush() async {
        let uploader = SpyUploader()
        uploader.nextError = .transport("nincs net")
        let registrar = PushRegistrar(
            uploader: uploader,
            store: InMemoryDeviceCredentialStore(credentials),
            defaults: makeDefaults()
        )
        registrar.didReceive(deviceTokenHex: "abcd")
        await registrar.flush()
        #expect(uploader.uploaded.isEmpty)

        uploader.nextError = nil
        await registrar.flush()
        #expect(uploader.uploaded.count == 1)
    }

    @Test func unlinkingForgetsTheUploadedToken() async {
        let uploader = SpyUploader()
        let store = InMemoryDeviceCredentialStore(credentials)
        let registrar = PushRegistrar(uploader: uploader, store: store, defaults: makeDefaults())
        registrar.didReceive(deviceTokenHex: "abcd")
        await registrar.flush()

        registrar.forgetUploadState()
        store.save(credentials)
        await registrar.flush()
        #expect(uploader.uploaded.count == 2)
    }
}
