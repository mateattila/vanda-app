//
//  SettingsView.swift
//  VandaApp
//
//  Beállítások — a Ma fejlécének fogaskerék-ikonjáról nyílik (spec 2.1).
//  A „Kinézet" van legfelül, mert Vanda ezt fogja a legtöbbet piszkálni.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var themeSettings: [ThemeSettings]
    @AppStorage("appRole") private var appRoleRaw: String = ""

    private var theme: ThemeSettings? { themeSettings.first }
    private var cardSurface: Color { theme?.cardSurface ?? .surface }

    var body: some View {
        ZStack {
            ThemedBackground(settings: theme)

            ScrollView {
                VStack(spacing: Theme.Spacing.cardGap) {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        settingsRow(
                            symbol: "paintpalette.fill",
                            title: "Kinézet",
                            subtitle: "Háttér és kiemelőszín"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        MoodSettingsView()
                    } label: {
                        settingsRow(
                            symbol: "battery.75percent",
                            title: "Barométer",
                            subtitle: "Zónahatárok, napi rákérdezés, kérdések"
                        )
                    }
                    .buttonStyle(.plain)

                    settingsRow(
                        symbol: "person.2.fill",
                        title: "Megosztás a szülőkkel",
                        subtitle: "A 4. fázisban kapcsol be — addig semmi sem megy ki"
                    )
                    .opacity(0.55)

                    Button {
                        appRoleRaw = ""
                    } label: {
                        settingsRow(
                            symbol: "arrow.triangle.2.circlepath",
                            title: "Szerepválasztás újra",
                            subtitle: "Gyerek / szülő mód váltása"
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, Theme.Spacing.cardGap)
            }
        }
        .navigationTitle("Beállítások")
        .navigationBarTitleDisplayMode(.large)
    }

    private func settingsRow(symbol: String, title: String, subtitle: String) -> some View {
        HStack(spacing: Theme.Spacing.cardPadding) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme?.accentColor ?? Theme.Accent.default)
                .frame(width: 34, height: 34)
                .background(
                    Color.surfaceTint,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.iconContainer, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.vandaBodyStrong())
                    .foregroundStyle(Color.ink)
                Text(subtitle)
                    .font(.vandaCaption())
                    .foregroundStyle(Color.inkMuted)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vandaCard(surface: cardSurface)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(VandaStore.makeContainer())
}
