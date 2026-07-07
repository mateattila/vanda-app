//
//  MainTabView.swift
//  VandaApp
//
//  4 fülös alsó tab bar (design-tokens: Ma · Ébresztő · Napló · Unatkozom).
//  A Panik NEM fül — kiemelt gomb a Ma képernyő fejlécében.
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query private var themeSettings: [ThemeSettings]
    @Query private var alarmProfiles: [AlarmProfile]

    /// Élő, megoldatlan lánc-ébresztés profilja — ilyenkor a feladvány-képernyő ül mindenen.
    @State private var puzzleProfile: AlarmProfile?
    /// Aksi-rákérdezés notificationjére koppintva nyílik.
    @State private var isMoodPromptPresented = false

    private var accent: Color {
        themeSettings.first?.accentColor ?? Theme.Accent.default
    }

    var body: some View {
        TabView {
            Tab("Ma", systemImage: "sun.max.fill") {
                TodayView()
            }
            Tab("Ébresztő", systemImage: "alarm.fill") {
                AlarmListView()
            }
            Tab("Napló", systemImage: "book.closed.fill") {
                JournalGateView()
            }
            Tab("Unatkozom", systemImage: "dice.fill") {
                BoredomView()
            }
        }
        .tint(accent)
        .fullScreenCover(item: $puzzleProfile) { profile in
            WakePuzzleView(profile: profile) {
                let solved = profile
                puzzleProfile = nil
                Task { await AlarmScheduler.shared.markSolvedAndReschedule(profile: solved) }
            }
        }
        .sheet(isPresented: $isMoodPromptPresented) {
            MoodCheckView()
        }
        .onAppear(perform: checkGates)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                checkGates()
                Task { await AlarmScheduler.shared.resync(profiles: alarmProfiles) }
            }
        }
    }

    private func checkGates() {
        guard puzzleProfile == nil else { return }
        puzzleProfile = AlarmScheduler.shared.profileNeedingPuzzle(from: alarmProfiles)

        // Aksi-rákérdezés csak akkor, ha nem áll feladvány-kapu az útban.
        if puzzleProfile == nil,
           UserDefaults.standard.bool(forKey: MoodPromptScheduler.pendingFlagKey) {
            UserDefaults.standard.set(false, forKey: MoodPromptScheduler.pendingFlagKey)
            isMoodPromptPresented = true
        }
    }
}

#Preview {
    MainTabView()
        .modelContainer(VandaStore.makeContainer())
}
