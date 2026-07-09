//
//  AlarmScheduler.swift
//  VandaApp
//
//  AlarmKit-integráció (spec 4.1). Lánc-ébresztő: egy „ébresztés" = N darab
//  alarm, M percenként. A hátralévő tagok csak akkor törlődnek, ha Vanda az
//  appban teljesítette a feladványt — a rendszer-alarm lecsapása után 2 perc
//  múlva jön a következő.
//
//  Megvalósítás: a lánc tagjai FIX időpontú alarmok a következő előfordulásra;
//  minden app-indulás/előtérbe kerülés/szerkesztés/megoldás után újraütemezünk.
//  (Az ébresztés-állapot — ütemezett ID-k, megoldás dátuma — eszköz-lokális,
//  ezért UserDefaults, nem a CloudKit-szinkronizált modell.)
//
//  FONTOS: valódi eszközön tesztelendő — a szimulátor az alarm-viselkedésre
//  megbízhatatlan (spec 4.1).
//

import ActivityKit
import AlarmKit
import Foundation
import SwiftUI

struct VandaAlarmMetadata: AlarmMetadata {}

final class AlarmScheduler {
    static let shared = AlarmScheduler()

    private let defaults = UserDefaults.standard

    // MARK: - Engedély

    func ensureAuthorization() async -> Bool {
        let manager = AlarmManager.shared
        switch manager.authorizationState {
        case .notDetermined:
            let state = try? await manager.requestAuthorization()
            return state == .authorized
        case .authorized:
            return true
        default:
            return false
        }
    }

    // MARK: - Újraszinkron

    /// A rendszerben élő, de egyik profil nyilvántartásában sem szereplő
    /// alarmok — pl. régebbi buildek maradványai. Ezek „fantomként" csörögnek:
    /// az app nem ismeri fel őket, feladvány és leállítás sincs hozzájuk
    /// (2026-07-09-i eszközös visszajelzés).
    static func orphanAlarmIDs(system: Set<UUID>, tracked: Set<UUID>) -> Set<UUID> {
        system.subtracting(tracked)
    }

    /// Minden profil láncának újraütemezése a következő előfordulásra.
    /// Aktív (épp csörgő/futó) láncot nem piszkál — azt a feladvány zárja le.
    /// Elsőként az árva alarmokat söpri ki a rendszerből.
    func resync(profiles: [AlarmProfile]) async {
        sweepOrphanAlarms(profiles: profiles)
        for profile in profiles {
            if isChainWindowActive(for: profile) && !isSolvedCurrentOccurrence(profile) {
                continue
            }
            await cancelStoredChain(for: profile)
            if profile.isEnabled {
                await scheduleChain(for: profile)
            }
        }
    }

    /// A feladvány megoldásakor: a hátralévő tagok leállítása/törlése + a
    /// következő előfordulás beütemezése. A megoldottság az AKTUÁLIS
    /// előforduláshoz (t0) kötődik, nem a naphoz — így ugyanaznap egy későbbi
    /// ébresztés újra feladványt kér.
    func markSolvedAndReschedule(profile: AlarmProfile) async {
        if let occurrence = defaults.object(forKey: occurrenceKey(profile)) as? Date {
            defaults.set(occurrence, forKey: solvedKey(profile))
        }
        await cancelStoredChain(for: profile)
        if profile.isEnabled {
            await scheduleChain(for: profile)
        }
    }

    // MARK: - Lánc-ütemezés

    private func scheduleChain(for profile: AlarmProfile) async {
        guard await ensureAuthorization() else { return }
        guard let firstDate = nextOccurrence(for: profile) else { return }

        let memberCount = profile.isChainEnabled ? max(1, profile.chainCount) : 1
        let interval = TimeInterval(max(1, profile.chainIntervalMinutes) * 60)

        var scheduledIDs: [String] = []
        for index in 0..<memberCount {
            let fireDate = firstDate.addingTimeInterval(Double(index) * interval)
            let id = UUID()
            do {
                try await schedule(id: id, at: fireDate, profile: profile, memberIndex: index)
                scheduledIDs.append(id.uuidString)
            } catch {
                // Egy tag hibája ne vigye el a többit; eszközön naplózható.
            }
        }
        defaults.set(scheduledIDs, forKey: chainKey(profile))
        defaults.set(firstDate, forKey: occurrenceKey(profile))
    }

    private func schedule(id: UUID, at date: Date, profile: AlarmProfile, memberIndex: Int) async throws {
        let title: LocalizedStringResource = memberIndex == 0
            ? "\(profile.name.isEmpty ? "Ébresztő" : profile.name) ⏰"
            : "Még csörgök! Feladvány az appban 🧩"

        let stopButton = AlarmButton(
            text: "Leállítom",
            textColor: .white,
            systemImageName: "stop.circle"
        )
        let alert = AlarmPresentation.Alert(title: title, stopButton: stopButton)
        let attributes = AlarmAttributes<VandaAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: Color.ink
        )

        let sound: AlertConfiguration.AlertSound
        if let file = profile.soundFileName, !file.isEmpty {
            sound = .named(file)
        } else {
            sound = .default
        }

        // Lánc-ébresztésnél a leállítás az appba dob (ott vár a feladvány);
        // sima ébresztőnél a stop csak leállít.
        let configuration = AlarmManager.AlarmConfiguration<VandaAlarmMetadata>(
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: profile.isChainEnabled ? OpenVandaPuzzleIntent() : nil,
            sound: sound
        )
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }

    private func cancelStoredChain(for profile: AlarmProfile) async {
        let ids = (defaults.stringArray(forKey: chainKey(profile)) ?? [])
            .compactMap(UUID.init(uuidString:))
        for id in ids {
            // Az épp csörgőt a stop hallgattatja el, a jövőbelieket a cancel törli.
            try? AlarmManager.shared.stop(id: id)
            try? AlarmManager.shared.cancel(id: id)
        }
        defaults.removeObject(forKey: chainKey(profile))
    }

    private func sweepOrphanAlarms(profiles: [AlarmProfile]) {
        let tracked = Set(
            profiles
                .flatMap { defaults.stringArray(forKey: chainKey($0)) ?? [] }
                .compactMap(UUID.init(uuidString:))
        )
        let system = Set(((try? AlarmManager.shared.alarms) ?? []).map(\.id))
        for id in Self.orphanAlarmIDs(system: system, tracked: tracked) {
            try? AlarmManager.shared.stop(id: id)
            try? AlarmManager.shared.cancel(id: id)
        }
    }

    /// Profil törlésekor hívandó.
    func removeAll(for profile: AlarmProfile) async {
        await cancelStoredChain(for: profile)
        defaults.removeObject(forKey: occurrenceKey(profile))
        defaults.removeObject(forKey: solvedKey(profile))
    }

    // MARK: - Előfordulás-számítás

    /// A következő megszólalás időpontja (most utáni első nap-idő egyezés).
    func nextOccurrence(for profile: AlarmProfile, after reference: Date = Date()) -> Date? {
        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = profile.hour
        components.minute = profile.minute

        if profile.repeatWeekdays.isEmpty {
            return calendar.nextDate(after: reference, matching: components, matchingPolicy: .nextTime)
        }

        let candidates: [Date] = profile.repeatWeekdays.compactMap { weekday in
            var c = components
            c.weekday = weekday
            return calendar.nextDate(after: reference, matching: c, matchingPolicy: .nextTime)
        }
        return candidates.min()
    }

    // MARK: - Aktív lánc-ablak (feladvány-kapu)

    /// Ha most egy lánc időablakában vagyunk (t0 … utolsó tag + ráhagyás),
    /// és a mai feladvány nincs megoldva, a lánc „élőnek" számít.
    func isChainWindowActive(for profile: AlarmProfile, at date: Date = Date()) -> Bool {
        guard profile.isEnabled, profile.isChainEnabled else { return false }
        guard let start = defaults.object(forKey: occurrenceKey(profile)) as? Date else { return false }
        let interval = TimeInterval(max(1, profile.chainIntervalMinutes) * 60)
        let grace: TimeInterval = 10 * 60
        let end = start.addingTimeInterval(Double(max(1, profile.chainCount) - 1) * interval + grace)
        return date >= start && date <= end
    }

    /// Az AKTUÁLIS előfordulás (t0) van-e megoldva — nem a nap.
    func isSolvedCurrentOccurrence(_ profile: AlarmProfile) -> Bool {
        guard let occurrence = defaults.object(forKey: occurrenceKey(profile)) as? Date,
              let solved = defaults.object(forKey: solvedKey(profile)) as? Date else { return false }
        return abs(solved.timeIntervalSince(occurrence)) < 1
    }

    /// Az a profil, amelyiknek épp élő, megoldatlan lánca van — ennek jár a feladvány.
    func profileNeedingPuzzle(from profiles: [AlarmProfile]) -> AlarmProfile? {
        profiles.first { isChainWindowActive(for: $0) && !isSolvedCurrentOccurrence($0) }
    }

    // MARK: - Kulcsok

    private func chainKey(_ profile: AlarmProfile) -> String { "alarmChain_\(profile.id.uuidString)" }
    private func occurrenceKey(_ profile: AlarmProfile) -> String { "alarmOccurrence_\(profile.id.uuidString)" }
    private func solvedKey(_ profile: AlarmProfile) -> String { "alarmSolved_\(profile.id.uuidString)" }
}
