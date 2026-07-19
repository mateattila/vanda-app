//
//  PushRegistrar.swift
//  VandaApp
//
//  Az APNs device-token és a párosítás bármilyen sorrendben érkezhet: a token
//  jöhet a párosítás előtt (indításkor regisztrálunk) és utána is. A registrar
//  ezért mindig eltárolja a legutóbb kapott tokent, és csak akkor tölti fel,
//  ha van hitelesítés ÉS a token eltér a legutóbb feltöltöttől.
//

import Foundation

protocol PushUploader {
    func uploadAPNsToken(_ apnsToken: String, token: String) async throws
}

extension BackendClient: PushUploader {}

final class PushRegistrar {
    static let shared = PushRegistrar()

    private let uploader: PushUploader
    private let store: DeviceCredentialStoring
    private let defaults: UserDefaults

    private let pendingKey = "backend.apnsToken.pending"
    private let uploadedKey = "backend.apnsToken.uploaded"

    init(
        uploader: PushUploader = BackendClient.shared,
        store: DeviceCredentialStoring = KeychainDeviceCredentialStore.shared,
        defaults: UserDefaults = .standard
    ) {
        self.uploader = uploader
        self.store = store
        self.defaults = defaults
    }

    static func hexString(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    func didReceive(deviceToken: Data) {
        didReceive(deviceTokenHex: Self.hexString(from: deviceToken))
    }

    func didReceive(deviceTokenHex: String) {
        defaults.set(deviceTokenHex, forKey: pendingKey)
    }

    /// Leválasztáskor hívandó: a következő párosítás után a token újra felmegy.
    func forgetUploadState() {
        defaults.removeObject(forKey: uploadedKey)
    }

    func flush() async {
        guard let pending = defaults.string(forKey: pendingKey),
              let credentials = store.load(),
              defaults.string(forKey: uploadedKey) != pending else { return }

        do {
            try await uploader.uploadAPNsToken(pending, token: credentials.token)
            defaults.set(pending, forKey: uploadedKey)
        } catch {
            // Nem végzetes: a következő indítás vagy párosítás újrapróbálja.
            // A 4.3 riasztás-ciklusa nem ettől függ, de a szülőnek jobb, ha
            // a token minél előbb felér — ezért nincs elnyelt, néma hiba.
            print("VandaApp: az APNs-token feltöltése nem sikerült — \(error)")
        }
    }
}
