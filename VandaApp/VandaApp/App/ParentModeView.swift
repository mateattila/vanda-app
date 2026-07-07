//
//  ParentModeView.swift
//  VandaApp
//
//  Szülő mód váz — a tartalma (riasztások fogadása, párosítás-kezelés,
//  megosztott aksi%/progress nézet) a 4. fázisban érkezik.
//

import SwiftUI

struct ParentModeView: View {
    @AppStorage("appRole") private var appRoleRaw: String = ""

    var body: some View {
        ZStack {
            Theme.BackgroundGradient.default.gradient
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.cardGap) {
                Spacer()

                VStack(spacing: 8) {
                    Text("🫶")
                        .font(.system(size: 48))
                    Text("Szülő mód")
                        .font(.vandaDisplay())
                        .foregroundStyle(Color.ink)
                    Text("A riasztások fogadása és a család-párosítás a 4. fázisban érkezik ide.")
                        .font(.vandaBody())
                        .foregroundStyle(Color.inkMuted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .vandaCard()

                Button("Másik szerepet választok") {
                    appRoleRaw = ""
                }
                .font(.vandaBodyStrong(13))
                .foregroundStyle(Color.inkMuted)

                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
        }
    }
}

#Preview {
    ParentModeView()
}
