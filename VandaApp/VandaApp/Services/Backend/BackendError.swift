//
//  BackendError.swift
//  VandaApp
//
//  A backend-hívások típusos hibái. A nyers Error helyett azért kell, hogy a
//  felület kedves, konkrét magyar mondatot tudjon mondani — és hogy a
//  hibakezelés tesztelhető legyen.
//

import Foundation

enum BackendError: Error, Equatable {
    /// Nincs beállítva a BACKEND_HOST (Config/Backend.xcconfig) — deploy előtti állapot.
    case notConfigured
    case unknownCode
    case codeExpiredOrUsed
    case unauthorized
    case forbidden
    case server(Int)
    case transport(String)
    case decoding

    /// Kedves, tegező magyar mondat a felületnek.
    var friendlyMessage: String {
        switch self {
        case .notConfigured:
            return "A backend címe még nincs beállítva ebben a buildben."
        case .unknownCode:
            return "Ilyen kódot nem találunk — lehet, hogy elgépeltük?"
        case .codeExpiredOrUsed:
            return "Ez a kód lejárt vagy már felhasználták. Kérj egy újat!"
        case .unauthorized:
            return "Megszakadt az összeköttetés a családdal — párosítsd újra az eszközt."
        case .forbidden:
            return "Ehhez ennek az eszköznek nincs jogosultsága."
        case .server:
            return "A szerver most nem tudott válaszolni. Próbáljuk újra?"
        case .transport:
            return "Úgy tűnik, most nincs net. Próbáljuk újra?"
        case .decoding:
            return "Furcsa választ kaptunk a szervertől. Próbáljuk újra?"
        }
    }

    /// A HTTP-státusz → hiba leképezés egy helyen, hogy tesztelhető legyen.
    static func forStatus(_ status: Int) -> BackendError? {
        switch status {
        case 200..<300: return nil
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .unknownCode
        case 410: return .codeExpiredOrUsed
        default: return .server(status)
        }
    }
}
