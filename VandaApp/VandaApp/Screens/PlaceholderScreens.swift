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

struct JournalPlaceholderView: View {
    var body: some View {
        PlaceholderScreen(
            emoji: "🔒",
            title: "Napló",
            message: "A pecsétes záras, csak-a-tiéd napló a 3. fázisban nyílik."
        )
    }
}

#Preview {
    JournalPlaceholderView()
        .modelContainer(VandaStore.makeContainer())
}
