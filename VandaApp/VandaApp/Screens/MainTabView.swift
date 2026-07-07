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
    @Query private var themeSettings: [ThemeSettings]

    private var accent: Color {
        themeSettings.first?.accentColor ?? Theme.Accent.default
    }

    var body: some View {
        TabView {
            Tab("Ma", systemImage: "sun.max.fill") {
                TodayView()
            }
            Tab("Ébresztő", systemImage: "alarm.fill") {
                AlarmPlaceholderView()
            }
            Tab("Napló", systemImage: "book.closed.fill") {
                JournalPlaceholderView()
            }
            Tab("Unatkozom", systemImage: "dice.fill") {
                BoredomPlaceholderView()
            }
        }
        .tint(accent)
    }
}

#Preview {
    MainTabView()
        .modelContainer(VandaStore.makeContainer())
}
