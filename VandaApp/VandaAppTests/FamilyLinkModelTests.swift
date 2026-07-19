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

/// Egylövetű találkozó-pont (rendezvous) a párhuzamossági tesztekhez.
///
/// A cél: a teszt maga kényszerítse ki a két hívás sorrendjét, ne a
/// (nyelv által nem garantált) ütemezőre bízza. A `FakeBackend` gated
/// metódusa `enter()`-t hív, amint belépett — ez szinkron `claim()` UTÁN
/// történik, hiszen a hívó `FamilyLinkModel`-metódusban a `claim()` az
/// egyetlen sor az első `await` előtt. A teszt `waitForEntry()`-vel
/// megvárja ezt, és csak utána indítja a második hívást — ekkorra az első
/// `isBusy`-ja garantáltan igaz. Az `enter()` a `release()`-ig blokkol, hogy
/// a teszt a második hívás lezajlása UTÁN, kontrollált sorrendben engedhesse
/// tovább az elsőt.
private actor Gate {
    private var entered = false
    private var released = false
    private var entryContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    /// A gated hívás oldaláról: jelzi a belépést, majd vár a felszabadításra.
    func enter() async {
        entered = true
        entryContinuation?.resume()
        entryContinuation = nil
        if released { return }
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    /// A teszt oldaláról: megvárja, amíg a gated hívás belép.
    func waitForEntry() async {
        if entered { return }
        await withCheckedContinuation { entryContinuation = $0 }
    }

    /// A teszt oldaláról: elengedi a bent (vagy majd bent) várakozó felet.
    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private final class FakeBackend: FamilyLinking {
    var createFamilyResult: Result<DeviceCredentials, BackendError> = .failure(.notConfigured)
    var redeemResult: Result<DeviceCredentials, BackendError> = .failure(.unknownCode)
    var codeResult: Result<PairingCode, BackendError> = .failure(.notConfigured)
    var testPushResult: Result<[TestPushResult], BackendError> = .success([])
    var deleteResult: Result<Void, BackendError> = .success(())
    var deleteCalls = 0

    /// Ha egy teszt beállítja, a megfelelő metódus ezen a kapun áll meg a
    /// hálózati hívás szimulálása helyett — lásd `Gate`.
    var createFamilyGate: Gate?
    var redeemGate: Gate?
    var codeGate: Gate?

    private let createFamilyTracker = CallTracker()
    private let redeemTracker = CallTracker()
    private let codeTracker = CallTracker()
    var createFamilyCallCount: Int {
        get async { await createFamilyTracker.count }
    }
    var redeemCallCount: Int {
        get async { await redeemTracker.count }
    }
    var codeCallCount: Int {
        get async { await codeTracker.count }
    }

    func createFamily(deviceName: String) async throws -> DeviceCredentials {
        await createFamilyTracker.record()
        if let createFamilyGate {
            await createFamilyGate.enter()
        } else {
            // Szándékosan felfüggesztjük, hogy a hívás ne térjen vissza
            // azonnal — ez a nem-versenyhelyzet-teszteknek elég valósághű
            // hálózati késleltetést szimulál.
            await Task.yield()
            await Task.yield()
        }
        return try createFamilyResult.get()
    }
    func redeemPairingCode(_ code: String, deviceName: String) async throws -> DeviceCredentials {
        await redeemTracker.record()
        if let redeemGate {
            await redeemGate.enter()
        } else {
            await Task.yield()
            await Task.yield()
        }
        return try redeemResult.get()
    }
    func createPairingCode(role: AppRole, token: String) async throws -> PairingCode {
        await codeTracker.record()
        if let codeGate {
            await codeGate.enter()
        } else {
            await Task.yield()
            await Task.yield()
        }
        return try codeResult.get()
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
        // állítania, mielőtt a backendet elérné. A sorrendet a `Gate`
        // kényszeríti ki: a második hívás csak azután indul, hogy az első
        // bizonyítottan túljutott a saját, szinkron `claim()`-jén (vagyis
        // `isBusy` már igaz) — ez nem a (nyelv által nem garantált)
        // ütemezési sorrendre bízza a tesztet.
        let backend = FakeBackend()
        backend.createFamilyResult = .success(childCredentials)
        let gate = Gate()
        backend.createFamilyGate = gate
        let store = InMemoryDeviceCredentialStore()
        let model = makeModel(backend: backend, store: store)

        async let first: () = model.createFamily(deviceName: "Első próba")
        await gate.waitForEntry()

        // Ezen a ponton az első hívás `claim()`-je garantáltan lefutott —
        // a második hívásnak tehát azonnal, hálózat nélkül el kell vérzenie
        // az őrön.
        await model.createFamily(deviceName: "Második próba")

        await gate.release()
        _ = await first

        #expect(await backend.createFamilyCallCount == 1)
        #expect(store.load() != nil)
        #expect(model.isBusy == false)
    }

    @Test func overlappingJoinWithCodeCallsOnlyHitTheNetworkOnce() async {
        let backend = FakeBackend()
        backend.redeemResult = .success(childCredentials)
        let gate = Gate()
        backend.redeemGate = gate
        let store = InMemoryDeviceCredentialStore()
        let model = makeModel(backend: backend, store: store)

        async let first: () = model.joinWithCode("111111", deviceName: "Első próba")
        await gate.waitForEntry()

        await model.joinWithCode("222222", deviceName: "Második próba")

        await gate.release()
        _ = await first

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

        #expect(model.codeState == .idle)
    }

    @Test func issuingACodeWhenLinkedPublishesIt() async {
        let backend = FakeBackend()
        backend.codeResult = .success(PairingCode(
            code: "123456", expiresAt: Date(timeIntervalSince1970: 1), role: .child
        ))
        let model = makeModel(backend: backend, store: InMemoryDeviceCredentialStore(childCredentials))

        await model.issueCode(role: .child)

        #expect(model.codeState == .ready(PairingCode(
            code: "123456", expiresAt: Date(timeIntervalSince1970: 1), role: .child
        )))
    }

    @Test func issuingACodeThatFailsRecordsTheFailureAgainstItsRole() async {
        // A hibát a `codeState`-nek kell hordoznia, szerephez kötve — ez az,
        // amit a sheet ténylegesen meg tud jeleníteni (lásd finding 1: a
        // korábbi megoldás a megosztott `errorMessage`-be írt, ami a nyitott
        // sheet MÖGÖTT, láthatatlanul jelent meg).
        let backend = FakeBackend()
        backend.codeResult = .failure(.notConfigured)
        let model = makeModel(backend: backend, store: InMemoryDeviceCredentialStore(childCredentials))

        await model.issueCode(role: .parent)

        #expect(model.codeState == .failed(role: .parent, message: BackendError.notConfigured.friendlyMessage))
        #expect(model.isBusy == false)
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

    @Test func unlinkWhileACodeIsBeingIssuedDoesNotCorruptTheModel() async {
        // Ugyanaz a versenyhelyzet, mint az `overlappingCreateFamilyCalls...`
        // teszteknél, de a két oldal itt `issueCode` és `unlink`: az
        // issueCode elsőként indul, a `Gate` segítségével bizonyítottan
        // túljut a saját `claim()`-jén (isBusy már igaz), mielőtt az unlink
        // egyáltalán elindulna. Ha az unlink nem menne át ugyanazon a
        // `claim`-en, minden ellenőrzés nélkül végigfutna, és a
        // `deleteDevice` letörölné az állapotot, miközben az issueCode
        // hálózati hívása még folyamatban van — az issueCode késve
        // visszaíródó `codeState`-je ekkor egy már leválasztott modellbe
        // kerülne, ellentmondó végállapotot hagyva maga után (`link ==
        // .unlinked`, de `codeState` mégis kész kódot tartalmaz).
        let backend = FakeBackend()
        backend.codeResult = .success(PairingCode(
            code: "654321", expiresAt: Date(timeIntervalSince1970: 1), role: .child
        ))
        let gate = Gate()
        backend.codeGate = gate
        let store = InMemoryDeviceCredentialStore(childCredentials)
        let model = makeModel(backend: backend, store: store)

        async let issue: () = model.issueCode(role: .child)
        await gate.waitForEntry()

        // Ezen a ponton az issueCode `claim()`-je garantáltan lefutott —
        // az unlinknek tehát azonnal, hálózat nélkül el kell vérzenie.
        await model.unlink()

        await gate.release()
        _ = await issue

        // A helyes kimenet: az unlink a `claim`-en elvérzik (isBusy-t már az
        // issueCode birtokolja), ezért csendben nem csinál semmit — nem éri
        // el a hálózatot, és az issueCode zavartalanul lefut. A modell a
        // verseny után is koherens: még mindig párosítva van, érvényes
        // kóddal a `codeState`-ben, a store pedig érintetlen.
        #expect(await backend.codeCallCount == 1)
        #expect(backend.deleteCalls == 0)
        #expect(model.link == .linked(childCredentials))
        #expect(model.codeState == .ready(PairingCode(
            code: "654321", expiresAt: Date(timeIntervalSince1970: 1), role: .child
        )))
        #expect(store.load() == childCredentials)
        #expect(model.isBusy == false)
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
