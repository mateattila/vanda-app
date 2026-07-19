//
//  TestPushSummary.swift
//  VandaApp
//
//  A teszt-push eredményének kimondása. Részleges kudarcot is néven nevezünk:
//  a „riasztás soha ne vesszen el csendben" elvet (spec 5.) itt szoktatjuk a
//  felületbe, még a 4.3 éles riasztás előtt.
//

import Foundation

enum TestPushSummary {

    static func text(for results: [TestPushResult]) -> String {
        guard !results.isEmpty else {
            return "Még nincs párosított szülői készülék, ezért nem volt kinek szólni."
        }

        let delivered = results.filter(\.delivered).count
        let failed = results.count - delivered

        if failed == 0 {
            return "Elment \(delivered) készülékre 💛"
        }
        if delivered == 0 {
            return "Egyik készülékre sem sikerült elküldeni (\(results.count) próbálkozás)."
        }
        return "Elment \(delivered) készülékre, \(failed) készüléknél viszont nem sikerült."
    }
}
