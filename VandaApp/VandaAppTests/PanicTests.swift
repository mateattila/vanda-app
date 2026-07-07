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
