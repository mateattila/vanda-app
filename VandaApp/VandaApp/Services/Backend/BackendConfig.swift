//
//  BackendConfig.swift
//  VandaApp
//
//  A backend hosztja a Config/Backend.xcconfig-ból jön, az Info.plist
//  BackendHost kulcsán keresztül. Séma nélkül tároljuk (az xcconfig a "//"-t
//  kommentnek veszi), a https:// előtagot itt tesszük hozzá.
//

import Foundation

enum BackendConfig {

    /// Amíg nincs deploy, ez az érték áll az xcconfig-ban. Nem tekintjük
    /// konfigurációnak — így a hiba nem néma 404-ek formájában jelentkezik.
    static let placeholderHost = "vanda-backend.example.workers.dev"

    static var host: String {
        (Bundle.main.object(forInfoDictionaryKey: "BackendHost") as? String) ?? ""
    }

    static func isConfigured(host: String) -> Bool {
        !host.isEmpty && host != placeholderHost
    }

    static func url(forHost host: String) -> URL? {
        guard isConfigured(host: host) else { return nil }
        return URL(string: "https://\(host)")
    }

    /// `nil`, ha a hoszt hiányzik vagy még a placeholder — a BackendClient
    /// ilyenkor `BackendError.notConfigured`-del hasal el, beszédesen.
    static var baseURL: URL? { url(forHost: host) }

    static var isConfigured: Bool { isConfigured(host: host) }
}
