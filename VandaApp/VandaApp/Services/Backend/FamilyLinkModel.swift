//
//  FamilyLinkModel.swift
//  VandaApp
//
//  A párosítás állapotgépe: ezt fogyasztja Vanda Család képernyője és a szülő
//  mód egyaránt. A hálózati réteg protokoll mögött van, hogy a tesztek
//  hálózat nélkül futhassanak.
//

import Foundation
import Observation

/// A BackendClient azon szelete, amire a párosítás támaszkodik.
protocol FamilyLinking {
    func createFamily(deviceName: String) async throws -> DeviceCredentials
    func redeemPairingCode(_ code: String, deviceName: String) async throws -> DeviceCredentials
    func createPairingCode(role: AppRole, token: String) async throws -> PairingCode
    func sendTestPush(token: String) async throws -> [TestPushResult]
    func deleteDevice(token: String) async throws
}

extension BackendClient: FamilyLinking {}

enum FamilyLink: Equatable {
    case unlinked
    case linked(DeviceCredentials)
}

@Observable
final class FamilyLinkModel {

    private(set) var link: FamilyLink
    private(set) var isBusy = false
    var errorMessage: String?
    private(set) var activeCode: PairingCode?
    private(set) var testPushResults: [TestPushResult]?

    private let client: FamilyLinking
    private let store: DeviceCredentialStoring
    private let registrar: PushRegistrar

    init(
        client: FamilyLinking = BackendClient.shared,
        store: DeviceCredentialStoring = KeychainDeviceCredentialStore.shared,
        registrar: PushRegistrar = .shared
    ) {
        self.client = client
        self.store = store
        self.registrar = registrar
        self.link = store.load().map(FamilyLink.linked) ?? .unlinked
    }

    var credentials: DeviceCredentials? {
        if case .linked(let credentials) = link { return credentials }
        return nil
    }

    var isLinked: Bool { credentials != nil }
    var deliveredCount: Int { (testPushResults ?? []).filter(\.delivered).count }
    var failedCount: Int { (testPushResults ?? []).filter { !$0.delivered }.count }

    // MARK: - Műveletek

    func createFamily(deviceName: String) async {
        // Idempotencia-őr: mentett hitelesítés mellett soha ne keletkezzen
        // második, árva család (dupla koppintás, timeout utáni újrapróbálás).
        guard !isLinked else { return }
        await run {
            let credentials = try await self.client.createFamily(deviceName: deviceName)
            self.persist(credentials)
        }
    }

    func joinWithCode(_ code: String, deviceName: String) async {
        guard !isLinked else { return }
        await run {
            let credentials = try await self.client.redeemPairingCode(code, deviceName: deviceName)
            self.persist(credentials)
        }
    }

    func issueCode(role: AppRole) async {
        guard let credentials else { return }
        activeCode = nil
        await run {
            self.activeCode = try await self.client.createPairingCode(
                role: role, token: credentials.token
            )
        }
    }

    func rename(to newName: String) async {
        guard var credentials else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        credentials.deviceName = trimmed
        persist(credentials)
    }

    func sendTestPush() async {
        guard let credentials else { return }
        testPushResults = nil
        await run {
            self.testPushResults = try await self.client.sendTestPush(token: credentials.token)
        }
    }

    func unlink() async {
        guard let credentials else { return }
        isBusy = true
        errorMessage = nil
        // A szerver-hívás hibája sem ragaszthatja ide az eszközt: a helyi
        // törlés akkor is megtörténik, hogy újra lehessen párosítani.
        do {
            try await client.deleteDevice(token: credentials.token)
        } catch {
            errorMessage = (error as? BackendError)?.friendlyMessage
        }
        self.store.clear()
        registrar.forgetUploadState()
        link = .unlinked
        activeCode = nil
        testPushResults = nil
        isBusy = false
    }

    // MARK: - Belső

    /// Nem `store(_:)` a neve, hogy ne ütközzön a `store` property-vel.
    private func persist(_ credentials: DeviceCredentials) {
        store.save(credentials)
        link = .linked(credentials)
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        do {
            try await work()
        } catch let error as BackendError {
            errorMessage = error.friendlyMessage
        } catch {
            errorMessage = BackendError.transport(error.localizedDescription).friendlyMessage
        }
        isBusy = false
        await registrar.flush()
    }
}
