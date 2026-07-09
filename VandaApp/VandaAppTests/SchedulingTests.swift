//
//  SchedulingTests.swift
//  VandaAppTests
//
//  Az ütemezők döntési logikájának tesztjei (napi használati visszajelzések,
//  2026-07-09): mood-újrasorsolás mai nap kihagyása, árva alarmok, szundi.
//

import Foundation
import Testing
@testable import VandaApp

// MARK: - Mood: a mai nap kihagyása újrasorsoláskor

struct MoodPromptSkipTodayTests {

    private let calendar = Calendar.current
    private let noon = Calendar.current.date(
        bySettingHour: 12, minute: 0, second: 0, of: Date()
    )!

    @Test func skipsWhenAPromptAlreadyFiredToday() {
        let firedAt10 = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: noon)!
        #expect(MoodPromptScheduler.shouldSkipToday(
            storedFireDates: [firedAt10],
            hasEntryToday: false,
            pendingFlag: false,
            now: noon
        ))
    }

    @Test func doesNotSkipWhenStoredPromptIsStillAhead() {
        let laterAt15 = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: noon)!
        #expect(!MoodPromptScheduler.shouldSkipToday(
            storedFireDates: [laterAt15],
            hasEntryToday: false,
            pendingFlag: false,
            now: noon
        ))
    }

    @Test func doesNotSkipWhenStoredPromptWasYesterday() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: noon)!
        #expect(!MoodPromptScheduler.shouldSkipToday(
            storedFireDates: [yesterday],
            hasEntryToday: false,
            pendingFlag: false,
            now: noon
        ))
    }

    @Test func skipsWhenTodayAlreadyHasAnEntry() {
        #expect(MoodPromptScheduler.shouldSkipToday(
            storedFireDates: [],
            hasEntryToday: true,
            pendingFlag: false,
            now: noon
        ))
    }

    @Test func skipsWhenAPromptTapIsPending() {
        #expect(MoodPromptScheduler.shouldSkipToday(
            storedFireDates: [],
            hasEntryToday: false,
            pendingFlag: true,
            now: noon
        ))
    }

    @Test func doesNotSkipOnACleanDay() {
        #expect(!MoodPromptScheduler.shouldSkipToday(
            storedFireDates: [],
            hasEntryToday: false,
            pendingFlag: false,
            now: noon
        ))
    }
}
