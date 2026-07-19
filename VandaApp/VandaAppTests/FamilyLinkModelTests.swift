//
//  FamilyLinkModelTests.swift
//  VandaAppTests
//
//  A párosítási állapotgép tesztjei — hálózat és felület nélkül.
//

import Foundation
import Testing
@testable import VandaApp

/// Szálbiztos hívásszámláló a párhuzamossági tesztekhez: a `FakeBackend`
/// maga nem izolált, ezért az átfedő hívások számlálását egy actorba
/// tesszük, nehogy a teszt saját magába vigyen be adatversenyt.
private actor CallTracker {
    private(set) var count = 0
    func record() { count += 1 }
}

private final class FakeBackend: FamilyLinking {
    var createFamilyResult: Result<DeviceCredentials, BackendError> = .failure(.notConfigured)
    var redeemResult: Result<DeviceCredentials, BackendError> = .failure(.unknownCode)
    var codeResult: Result<PairingCode, BackendError> = .failure(.notConfigured)
    var testPushResult: Result<[TestPushResult], BackendError> = .success([])
    var deleteResult: Result<Void, BackendError> = .success(())
    var deleteCalls = 0

    private let createFamilyTracker = CallTracker()
    private let redeemTracker = CallTracker()
    var createFamilyCallCount: Int {
        get async { await createFamilyTracker.count }
    }
    var redeemCallCount: Int {
        get async { await redeemTracker.count }
    }

    func createFamily(deviceName: String) async throws -> DeviceCredentials {
        await createFamilyTracker.record()
        // Szándékosan felfüggesztjük, hogy egy második, átfedő hívás valóban
        // el tudjon indulni, mielőtt ez itt visszatérne — enélkül a teszt nem
        // a valódi versenyhelyzetet mérné, csak a gyors visszatérés miatti
        // véletlen sorrendet.
        await Task.yield()
        await Task.yield()
        return try createFamilyResult.get()
    }
    func redeemPairingCode(_ code: String, deviceName: String) async throws -> DeviceCredentials {
        await redeemTracker.record()
        await Task.yield()
        await Task.yield()
        return try redeemResult.get()
    }
    func createPairingCode(role: AppRole, token: String) async throws -> PairingCode {
        try codeResult.get()
    }
    func sendTestPush(token: String) async throws -> [TestPushResult] {
        try testPushResult.get()
    }
    func deleteDevice(token: String) async throws {
        deleteCalls += 1
        try deleteResult.get()
    }
}

private let childCredentials = DeviceCredentials(
    familyId: "f1", deviceId: "d1", token: "tok", role: .child, deviceName: "Vanda telefonja"
)

@MainActor
private func makeModel(
    backend: FakeBackend, store: InMemoryDeviceCredentialStore = InMemoryDeviceCredentialStore()
) -> FamilyLinkModel {
    FamilyLinkModel(
        client: backend,
        store: store,
        registrar: PushRegistrar(
            uploader: NoopUploader(),
            store: store,
            defaults: UserDefaults(suiteName: "FamilyLinkModelTests-\(UUID().uuidString)")!
        )
    )
}

private final class NoopUploader: PushUploader {
    func uploadAPNsToken(_ apnsToken: String, token: String) async throws {}
}

@MainActor
struct FamilyLinkModelTests {

    @Test func startsUnlinkedWithAnEmptyStore() {
        let model = makeModel(backend: FakeBackend())
        #expect(model.link == .unlinked)
        #expect(model.isLinked == false)
    }

    @Test func picksUpCredentialsAlreadyInTheStore() {
        let store = InMemoryDeviceCredentialStore(childCredentials)
        let model = makeModel(backend: FakeBackend(), store: store)
        #expect(model.link == .linked(childCredentials))
        #expect(model.credentials?.role == .child)
    }

    @Test func creatingAFamilyStoresTheCredentials() async {
        let backend = FakeBackend()
        backend.createFamilyResult = .success(childCredentials)
        let store = InMemoryDeviceCredentialStore()
        let model = makeModel(backend: backend, store: store)

        await model.createFamily(deviceName: "Vanda telefonja")

        #expect(model.link == .linked(childCredentials))
        #expect(store.load() == childCredentials)
        #expect(model.errorMessage == nil)
        #expect(model.isBusy == false)
    }

    @Test func creatingAFamilyTwiceIsRefused() async {
        let backend = FakeBackend()
        backend.createFamilyResult = .success(childCredentials)
        let store = InMemoryDeviceCredentialStore(childCredentials)
        let model = makeModel(backend: backend, store: store)

        await model.createFamily(deviceName: "Másik név")

        #expect(store.load()?.deviceName == "Vanda telefonja")
    }

    @Test func overlappingCreateFamilyCallsOnlyHitTheNetworkOnce() async {
        // Két, egymást átfedő createFamily hívás (pl. dupla koppintás) közül
        // csak az egyik juthat el a hálózatig — a másiknak az őrnek le kell
        // állítania, mielőtt a backendet elérné.
        let backend = FakeBackend()
        backend.createFamilyResult = .success(childCredentials)
        let store = InMemoryDeviceCredentialStore()
        let model = makeModel(backend: backend, store: store)

        async let first: () = model.createFamily(deviceName: "Első próba")
        async let second: () = model.createFamily(deviceName: "Második próba")
        _ = await (first, second)

        #expect(await backend.createFamilyCallCount == 1)
        #expect(store.load() != nil)
        #expect(model.isBusy == false)
    }

    @Test func overlappingJoinWithCodeCallsOnlyHitTheNetworkOnce() async {
        let backend = FakeBackend()
        backend.redeemResult = .success(childCredentials)
        let store = InMemoryDeviceCredentialStore()
        let model = makeModel(backend: backend, store: store)

        async let first: () = model.joinWithCode("111111", deviceName: "Első próba")
        async let second: () = model.joinWithCode("222222", deviceName: "Második próba")
        _ = await (first, second)

        #expect(await backend.redeemCallCount == 1)
        #expect(store.load() != nil)
    }

    @Test func joiningWithABadCodeSurfacesAKindMessage() async {
        let backend = FakeBackend()
        backend.redeemResult = .failure(.unknownCode)
        let model = makeModel(backend: backend)

        await model.joinWithCode("000000", deviceName: "Vanda iPadje")

        #expect(model.link == .unlinked)
        #expect(model.errorMessage == BackendError.unknownCode.friendlyMessage)
    }

    @Test func joiningWithAnExpiredCodeSurfacesTheExpiryMessage() async {
        let backend = FakeBackend()
        backend.redeemResult = .failure(.codeExpiredOrUsed)
        let model = makeModel(backend: backend)

        await model.joinWithCode("123456", deviceName: "Anya telefonja")

        #expect(model.errorMessage == BackendError.codeExpiredOrUsed.friendlyMessage)
    }

    @Test func issuingACodeRequiresBeingLinked() async {
        let backend = FakeBackend()
        backend.codeResult = .success(PairingCode(
            code: "123456", expiresAt: Date(timeIntervalSince1970: 1), role: .parent
        ))
        let model = makeModel(backend: backend)

        await model.issueCode(role: .parent)

        #expect(model.activeCode == nil)
    }

    @Test func issuingACodeWhenLinkedPublishesIt() async {
        let backend = FakeBackend()
        backend.codeResult = .success(PairingCode(
            code: "123456", expiresAt: Date(timeIntervalSince1970: 1), role: .child
        ))
        let model = makeModel(backend: backend, store: InMemoryDeviceCredentialStore(childCredentials))

        await model.issueCode(role: .child)

        #expect(model.activeCode?.code == "123456")
        #expect(model.activeCode?.role == .child)
    }

    @Test func renamingKeepsTheRestOfTheCredentials() async {
        let store = InMemoryDeviceCredentialStore(childCredentials)
        let model = makeModel(backend: FakeBackend(), store: store)

        await model.rename(to: "Vanda új telefonja")

        #expect(store.load()?.deviceName == "Vanda új telefonja")
        #expect(store.load()?.token == "tok")
    }

    @Test func unlinkingClearsTheStoreEvenIfTheServerCallFails() async {
        let backend = FakeBackend()
        backend.deleteResult = .failure(.transport("nincs net"))
        let store = InMemoryDeviceCredentialStore(childCredentials)
        let model = makeModel(backend: backend, store: store)

        await model.unlink()

        #expect(backend.deleteCalls == 1)
        #expect(store.load() == nil)
        #expect(model.link == .unlinked)
    }

    @Test func testPushResultsAreKept() async {
        let backend = FakeBackend()
        backend.testPushResult = .success([
            TestPushResult(deviceId: "a", status: 200),
            TestPushResult(deviceId: "b", status: 0),
        ])
        let model = makeModel(backend: backend, store: InMemoryDeviceCredentialStore(childCredentials))

        await model.sendTestPush()

        #expect(model.testPushResults?.count == 2)
        #expect(model.deliveredCount == 1)
        #expect(model.failedCount == 1)
    }
}
