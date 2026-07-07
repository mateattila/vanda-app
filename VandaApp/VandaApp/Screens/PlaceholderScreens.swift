//
//  PlaceholderScreens.swift
//  VandaApp
//
//  A még nem élesedett fülek placeholder képernyői — témázott háttérrel,
//  kedves hangnemben, a fázis megjelölésével.
//

import SwiftUI
import SwiftData

private struct PlaceholderScreen: View {
    let emoji: String
    let title: String
    let message: String

    @Query private var themeSettings: [ThemeSettings]

    var body: some View {
        ZStack {
            ThemedBackground(settings: themeSettings.first)

            VStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 48))
                Text(title)
                    .font(.vandaDisplay())
                    .foregroundStyle(Color.ink)
                Text(message)
                    .font(.vandaBody())
                    .foregroundStyle(Color.inkMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .vandaCard(surface: themeSettings.first?.cardSurface ?? .surface)
            .padding(.horizontal, Theme.Spacing.screenMargin)
        }
    }
}

struct AlarmPlaceholderView: View {
    var body: some View {
        PlaceholderScreen(
            emoji: "⏰",
            title: "Ébresztő",
            message: "A kedvenc zenéddel ébresztünk majd — az 1. fázis nagy dobása. 🎸"
        )
    }
}

struct JournalPlaceholderView: View {
    var body: some View {
        PlaceholderScreen(
            emoji: "🔒",
            title: "Napló",
            message: "A pecsétes záras, csak-a-tiéd napló a 3. fázisban nyílik."
        )
    }
}

struct BoredomPlaceholderView: View {
    var body: some View {
        PlaceholderScreen(
            emoji: "🎲",
            title: "Unatkozom",
            message: "A kártyafal és a „Pörgess egyet!” az 1. fázisban érkezik."
        )
    }
}

#Preview {
    BoredomPlaceholderView()
        .modelContainer(VandaStore.makeContainer())
}
