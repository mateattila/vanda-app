//
//  PanicTests.swift
//  VandaAppTests
//
//  A panik-képernyő logikájának tesztjei (4. fázis): hívás-URL-ek,
//  légzés-fázisok, grounding-lépések, érzés→eszköz-ajánlás.
//

import Foundation
import Testing
@testable import VandaApp

// MARK: - Hívható szülők (PanicContact)

struct PanicContactTests {

    private func contact(_ number: String) -> PanicContact {
        let c = PanicContact()
        c.label = "Anya"
        c.phoneNumber = number
        return c
    }

    @Test func dialableNumberStripsFormatting() {
        #expect(contact("06 30 123-4567").dialableNumber == "06301234567")
    }

    @Test func dialableNumberKeepsLeadingPlus() {
        #expect(contact("+36 30 123 4567").dialableNumber == "+36301234567")
    }

    @Test func plusIsOnlyKeptAtTheStart() {
        #expect(contact("06+30 123").dialableNumber == "0630123")
    }

    @Test func emptyNumberGivesNoURLs() {
        let c = contact("   ")
        #expect(c.telURL == nil)
        #expect(c.faceTimeVideoURL == nil)
        #expect(c.faceTimeAudioURL == nil)
    }

    @Test func urlsUseTheRightSchemes() {
        let c = contact("+36301234567")
        #expect(c.telURL?.absoluteString == "tel://+36301234567")
        #expect(c.faceTimeVideoURL?.absoluteString == "facetime://+36301234567")
        #expect(c.faceTimeAudioURL?.absoluteString == "facetime-audio://+36301234567")
    }
}

// MARK: - Légzés-fázisok

struct BreathingPatternTests {

    @Test func boxCycleIsSixteenSeconds() {
        #expect(BreathingPattern.box.cycleDuration == 16)
        #expect(BreathingPattern.box.phases.count == 4)
    }

    @Test func fourSevenEightDurations() {
        let durations = BreathingPattern.fourSevenEight.phases.map(\.duration)
        #expect(durations == [4, 7, 8])
    }

    @Test func phaseAtZeroIsInhale() {
        #expect(BreathingPattern.box.phase(at: 0).phase.kind == .inhale)
    }

    @Test func boxPhaseAtFiveSecondsIsHold() {
        #expect(BreathingPattern.box.phase(at: 5).phase.kind == .hold)
    }

    @Test func phaseWrapsAroundTheCycle() {
        let wrapped = BreathingPattern.box.phase(at: 16.5)
        #expect(wrapped.phase.kind == .inhale)
        #expect(abs(wrapped.progress - 0.125) < 0.001)
    }

    @Test func circleGrowsDuringInhaleAndHoldsAfter() {
        let pattern = BreathingPattern.box
        #expect(pattern.circleScale(at: 0) < 0.7)
        #expect(pattern.circleScale(at: 3.999) > 0.99)
        // inhale utáni hold: kitágulva marad
        #expect(pattern.circleScale(at: 5) == 1.0)
        // exhale utáni hold: összehúzva marad
        #expect(pattern.circleScale(at: 13) < 0.7)
    }
}
