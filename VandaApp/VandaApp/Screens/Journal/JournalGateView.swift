//
//  JournalGateView.swift
//  VandaApp
//
//  A Napló fül kapuja: első használatkor beállítás (PIN + recovery-kulcs),
//  utána PIN-zár, nyitva a napló. Háttérbe kerüléskor automatikusan zárunk.
//

import SwiftData
import SwiftUI

struct JournalGateView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @State private var vault = JournalVault.shared
    /// A beállítás-flow a recovery-kulcs nyugtázásáig tart — akkor is, ha a
    /// vault közben már „beállított" állapotú.
    @State private var isSettingUp = false
    #if DEBUG
    @State private var isResetConfirmPresented = false
    #endif

    var body: some View {
        Group {
            if isSettingUp || !vault.isSetUp {
                JournalSetupView(vault: vault) {
                    isSettingUp = false
                    seedPhotoPromptReminder()
                }
            } else if !vault.isUnlocked {
                JournalLockView(vault: vault)
                    #if DEBUG
                    .safeAreaInset(edge: .bottom) {
                        Button("Napló törlése és újrakezdés (debug)") {
                            isResetConfirmPresented = true
                        }
                        .font(.vandaCaption())
                        .foregroundStyle(Color.zoneRed)
                        .padding(.bottom, Theme.Spacing.cardGap)
                    }
                    .confirmationDialog(
                        "Minden naplóbejegyzés, fotó és a PIN is törlődik. Ez nem vonható vissza.",
                        isPresented: $isResetConfirmPresented, titleVisibility: .visible
                    ) {
                        Button("Törlés és újrakezdés", role: .destructive) {
                            resetJournal()
                        }
                    }
                    #endif
            } else {
                JournalHomeView(vault: vault)
            }
        }
        .onAppear {
            isSettingUp = !vault.isSetUp
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                vault.lock()
            }
        }
    }

    #if DEBUG
    /// A borítékokkal együtt a tartalom is megy: az új kulccsal a régi
    /// bejegyzések úgysem nyithatók. Egyenként törlünk, hogy a CloudKit is kövesse.
    private func resetJournal() {
        try? modelContext.fetch(FetchDescriptor<JournalEntry>()).forEach(modelContext.delete)
        try? modelContext.fetch(FetchDescriptor<JournalPhoto>()).forEach(modelContext.delete)
        try? modelContext.fetch(FetchDescriptor<JournalAuditEvent>()).forEach(modelContext.delete)
        try? modelContext.save()
        vault.reset()
        isSettingUp = true
    }
    #endif

    /// Fotó-prompt emlékeztető (spec 4.5): a napló beállításakor kerül be,
    /// egyszer — utána a normál emlékeztető-rendszerben él (átírható, kikapcsolható).
    private func seedPhotoPromptReminder() {
        let key = "journalPhotoPromptSeeded"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let reminder = Reminder()
        reminder.title = "Fotó a napodról"
        reminder.text = "Tölts fel egy fotót a napodról a naplóba! 📸"
        reminder.symbolOrEmoji = "📸"
        reminder.colorHex = 0x8A7DE0
        reminder.source = .factory
        reminder.wantsFeedback = false
        var schedule = ReminderSchedule()
        schedule.times = [ReminderSchedule.TimeOfDay(hour: 18, minute: 30)]
        reminder.schedule = schedule
        modelContext.insert(reminder)

        Task { await ReminderScheduler.shared.resyncFromStore() }
    }
}

// MARK: - Közös PIN-elemek (sötét környezetre)

struct PinDots: View {
    let filled: Int
    let total: Int

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < filled ? Color.white : Color.white.opacity(0.35))
                    .frame(width: 14, height: 14)
            }
        }
    }
}

struct PinPad: View {
    @Binding var pin: String
    let maxLength: Int
    let onComplete: (String) -> Void

    private let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "⌫"]]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 26) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            tap(key)
                        } label: {
                            Text(key)
                                .font(.vandaDisplay(24))
                                .foregroundStyle(.white)
                                .frame(width: 74, height: 74)
                                .background(
                                    key.isEmpty ? Color.clear : Color.panicChipSurface,
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(key.isEmpty)
                    }
                }
            }
        }
    }

    private func tap(_ key: String) {
        if key == "⌫" {
            if !pin.isEmpty { pin.removeLast() }
            return
        }
        guard pin.count < maxLength else { return }
        pin.append(key)
        if pin.count == maxLength {
            let finished = pin
            onComplete(finished)
        }
    }
}
