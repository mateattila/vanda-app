//
//  AlarmIntents.swift
//  VandaApp
//
//  A rendszer-alarm „Leállítom" gombjához kötött intent (lánc-ébresztős
//  profiloknál): a leállítással együtt az appba dob, ahol a feladvány-kapu
//  (MainTabView) azonnal felteszi a kérdéseket.
//

import AppIntents

struct OpenVandaPuzzleIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Ébresztő-feladvány megnyitása"
    static let description = IntentDescription("Megnyitja a Vanda appot a kikapcsoló feladványhoz.")
    static let openAppWhenRun: Bool = true
    static let isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        // Nincs teendő: az app előtérbe kerül, a feladvány-kaput a
        // MainTabView scenePhase-figyelője nyitja.
        .result()
    }
}
