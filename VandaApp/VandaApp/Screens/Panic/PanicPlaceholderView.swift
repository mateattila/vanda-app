//
//  PanicPlaceholderView.swift
//  VandaApp
//
//  A panik-képernyő helye — saját, sötétebb környezet (design-tokens 2. fejezet).
//  Az eszközök (légzés, grounding, nyugi-mappa, hívás) és a riasztás a 4. fázisban
//  élesednek; a gomb helye és útvonala kezdettől él.
//

import SwiftUI

struct PanicPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.Gradients.panic
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.cardGap) {
                Spacer()

                Text("🫂")
                    .font(.system(size: 52))
                Text("Itt leszünk, ha nehéz")
                    .font(.vandaDisplay())
                    .foregroundStyle(.white)
                Text("A nyugi-eszközök és a „Szólok anyáéknak” gomb a 4. fázisban kerülnek ide.")
                    .font(.vandaBody())
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.screenMargin)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Vissza")
                        .font(.vandaBodyStrong())
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Color.white,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.bottom, Theme.Spacing.screenMargin)
            }
        }
    }
}

#Preview {
    PanicPlaceholderView()
}
