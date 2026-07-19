//
//  TestPushSummaryTests.swift
//  VandaAppTests
//
//  A teszt-push összefoglalója. Elv (spec 5.): a riasztás soha ne vesszen el
//  csendben — a részleges kudarcot is ki kell mondani.
//

import Foundation
import Testing
@testable import VandaApp

struct TestPushSummaryTests {

    @Test func noParentsIsExplained() {
        #expect(TestPushSummary.text(for: []) ==
                "Még nincs párosított szülői készülék, ezért nem volt kinek szólni.")
    }

    @Test func allDeliveredIsCheerful() {
        let results = [
            TestPushResult(deviceId: "a", status: 200),
            TestPushResult(deviceId: "b", status: 200),
        ]
        #expect(TestPushSummary.text(for: results) == "Elment 2 készülékre 💛")
    }

    @Test func singleDeliveryUsesSingularWording() {
        #expect(TestPushSummary.text(for: [TestPushResult(deviceId: "a", status: 200)])
                == "Elment 1 készülékre 💛")
    }

    @Test func partialFailureIsNamedOutLoud() {
        let results = [
            TestPushResult(deviceId: "a", status: 200),
            TestPushResult(deviceId: "b", status: 0),
        ]
        #expect(TestPushSummary.text(for: results) ==
                "Elment 1 készülékre, 1 készüléknél viszont nem sikerült.")
    }

    @Test func totalFailureIsNamedOutLoud() {
        let results = [
            TestPushResult(deviceId: "a", status: 410),
            TestPushResult(deviceId: "b", status: 0),
        ]
        #expect(TestPushSummary.text(for: results) ==
                "Egyik készülékre sem sikerült elküldeni (2 próbálkozás).")
    }
}
