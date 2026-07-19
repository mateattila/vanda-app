//
//  NotificationPermissionTests.swift
//  VandaAppTests
//
//  Az engedély-állapot értelmezésének tesztjei. Magát a rendszer-dialógust nem
//  teszteljük (az eszközös kör dolga) — csak azt, hogy mikor kell szólni.
//

import Foundation
import Testing
import UserNotifications
@testable import VandaApp

// A `NotificationPermission` @MainActor lett (lásd finding 2), ez a statikus
// segédfüggvényeire is átterjed — ugyanaz a minta, mint a testvér
// `FamilyLinkModelTests`-ben.
@MainActor
struct NotificationPermissionTests {

    @Test func authorizedNeedsNoAttention() {
        #expect(NotificationPermission.needsAttention(for: .authorized) == false)
    }

    @Test func provisionalNeedsNoAttention() {
        #expect(NotificationPermission.needsAttention(for: .provisional) == false)
    }

    @Test func notDeterminedNeedsAttention() {
        #expect(NotificationPermission.needsAttention(for: .notDetermined))
    }

    @Test func deniedNeedsAttention() {
        #expect(NotificationPermission.needsAttention(for: .denied))
    }

    @Test func onlyDeniedSendsYouToSettings() {
        #expect(NotificationPermission.requiresSettingsTrip(for: .denied))
        #expect(NotificationPermission.requiresSettingsTrip(for: .notDetermined) == false)
    }
}
