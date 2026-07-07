//
//  TodayView.swift
//  VandaApp
//
//  A Ma képernyő — az induló fül. Fejlécében a kiemelt, lüktető Panik gomb
//  (app-nyitásból 1 érintésre) és a fogaskerék a Beállításokhoz.
//  A tartalom (töltöttség-fal, barométer mini, Unatkozol?-kártya) az 1–2.
//  fázisban élesedik; itt még placeholder kártyák állnak.
//

import SwiftUI
import SwiftData

struct TodayView: View {
    @Query private var themeSettings: [ThemeSettings]
    @State private var isPanicPresented = false

    private var theme: ThemeSettings? { themeSettings.first }
    private var accent: Color { theme?.accentColor ?? Theme.Accent.default }
    private var cardSurface: Color { theme?.cardSurface ?? .surface }

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground(settings: theme)

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
                        header
                        chargeCard
                        boredomCard
                    }
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                    .padding(.bottom, Theme.Spacing.screenMargin)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $isPanicPresented) {
                PanicPlaceholderView()
            }
        }
    }

    // MARK: - Fejléc

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.cardGap) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Szia, Vanda 🌙")
                    .font(.vandaDisplay(25))
                    .foregroundStyle(Color.ink)
                Text(formattedToday)
                    .font(.vandaBodyStrong(13))
                    .foregroundStyle(accent)
            }

            Spacer()

            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.inkMuted)
                    .frame(width: 38, height: 38)
                    .background(cardSurface, in: Circle())
                    .softShadow()
            }
            .padding(.top, 4)

            PanicButton(accent: accent) {
                isPanicPresented = true
            }
        }
        .padding(.top, 8)
    }

    private var formattedToday: String {
        let now = Date.now
        let weekday = now.formatted(.dateTime.weekday(.wide)).capitalized
        let monthDay = now.formatted(.dateTime.month(.abbreviated).day())
        return "\(weekday) · \(monthDay)"
    }

    // MARK: - Placeholder kártyák

    private var chargeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mai töltöttség")
                .vandaLabelStyle()
                .foregroundStyle(Color.inkFaint)
            Text("–")
                .font(.vandaBigNumber())
                .foregroundStyle(Color.ink)
            Text("Az emlékeztetők és a napi fal az 1. fázisban érkeznek ide 🌱")
                .font(.vandaBody())
                .foregroundStyle(Color.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vandaCard(surface: cardSurface)
    }

    private var boredomCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Unatkozol?")
                    .font(.vandaDisplay(20))
                    .foregroundStyle(.white)
                Text("A kártyafal az 1. fázisban nyílik 👀")
                    .font(.vandaBody(13))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.cardPadding)
        .background(accent, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .softShadow()
    }
}

#Preview {
    TodayView()
        .modelContainer(VandaStore.makeContainer())
}
