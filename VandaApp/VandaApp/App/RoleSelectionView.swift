//
//  RoleSelectionView.swift
//  VandaApp
//
//  Első indításkori szerepválasztás. A párosítás (QR / 6 jegyű kód) a 4. fázisban
//  kapcsolódik ide.
//

import SwiftUI

struct RoleSelectionView: View {
    @AppStorage("appRole") private var appRoleRaw: String = ""

    var body: some View {
        ZStack {
            Theme.BackgroundGradient.default.gradient
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.cardGap) {
                Spacer()

                Text("👋")
                    .font(.system(size: 56))
                Text("Szia! Kié ez a készülék?")
                    .font(.vandaDisplay())
                    .foregroundStyle(Color.ink)
                Text("Ezt csak egyszer kérdezzük meg.")
                    .font(.vandaBody())
                    .foregroundStyle(Color.inkMuted)
                    .padding(.bottom, Theme.Spacing.cardGap)

                roleCard(
                    emoji: "🌙",
                    title: "Vandáé",
                    subtitle: "Ébresztő, napló, panik gomb — minden itt lesz."
                ) {
                    appRoleRaw = AppRole.child.rawValue
                }

                roleCard(
                    emoji: "🫶",
                    title: "Szülőé",
                    subtitle: "Riasztások fogadása és család-párosítás (később)."
                ) {
                    appRoleRaw = AppRole.parent.rawValue
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
        }
    }

    private func roleCard(
        emoji: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.cardPadding) {
                Text(emoji)
                    .font(.system(size: 34))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.vandaDisplay(20))
                        .foregroundStyle(Color.ink)
                    Text(subtitle)
                        .font(.vandaBody(13))
                        .foregroundStyle(Color.inkMuted)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.inkFaint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .vandaCard()
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RoleSelectionView()
}
