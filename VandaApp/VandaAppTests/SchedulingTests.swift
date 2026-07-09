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

// MARK: - Árva alarmok (fantom ébresztés)

struct OrphanAlarmTests {

    @Test func alarmsUnknownToAnyProfileAreOrphans() {
        let tracked = UUID()
        let orphan = UUID()
        let result = AlarmScheduler.orphanAlarmIDs(
            system: [tracked, orphan],
            tracked: [tracked]
        )
        #expect(result == [orphan])
    }

    @Test func nothingIsOrphanWhenAllTracked() {
        let a = UUID()
        let b = UUID()
        #expect(AlarmScheduler.orphanAlarmIDs(system: [a, b], tracked: [a, b]).isEmpty)
    }

    @Test func trackedButNotScheduledIsNotAnOrphan() {
        // A defaults-ban őrzött, de a rendszerben már nem élő ID nem söprendő.
        let system = UUID()
        let onlyTracked = UUID()
        #expect(AlarmScheduler.orphanAlarmIDs(
            system: [system],
            tracked: [system, onlyTracked]
        ).isEmpty)
    }
}

// MARK: - Emlékeztető: szundi-akciók

struct ReminderSnoozeTests {

    @Test func snoozeActionsMapToTheirIntervals() {
        #expect(ReminderScheduler.snoozeInterval(for: ReminderScheduler.snooze10ActionID) == TimeInterval(10 * 60))
        #expect(ReminderScheduler.snoozeInterval(for: ReminderScheduler.snooze30ActionID) == TimeInterval(30 * 60))
        #expect(ReminderScheduler.snoozeInterval(for: ReminderScheduler.snooze60ActionID) == TimeInterval(60 * 60))
    }

    @Test func nonSnoozeActionsHaveNoInterval() {
        #expect(ReminderScheduler.snoozeInterval(for: ReminderScheduler.doneActionID) == nil)
        #expect(ReminderScheduler.snoozeInterval(for: ReminderScheduler.skipTodayActionID) == nil)
        #expect(ReminderScheduler.snoozeInterval(for: "UNNotificationDefaultActionIdentifier") == nil)
    }
}
