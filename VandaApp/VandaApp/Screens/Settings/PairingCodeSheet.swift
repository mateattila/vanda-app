//
//  PairingCodeSheet.swift
//  VandaApp
//
//  A 6 jegyű párosító kód megjelenítése visszaszámlálóval. Nagy, jól olvasható
//  számjegyek — a másik eszközön valakinek be kell gépelnie.
//

import Combine
import SwiftUI

struct PairingCodeSheet: View {
    /// A sheet-et megnyitó gomb szerepe (szülő vagy gyerek eszköz). Ez —
    /// nem a modell aktuális `codeState`-je — dönti el, MIT jelenítünk meg:
    /// így egy korábbi, más szerephez tartozó kód vagy hiba sose villanhat
    /// fel tévesen, ha időközben egy másik kérés van/volt folyamatban.
    let role: AppRole
    /// A modell teljes párosítókód-állapota. A sheet ebből szűr a saját
    /// `role`-jára — lásd `phase` alább.
    let state: PairingCodeState
    let onRefresh: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// A sheet szempontjából releváns fázis: a `state.phase(for:)` (lásd
    /// `FamilyLinkModel.swift`) szűri rá a modell teljes állapotát a sheet
    /// saját szerepére — így garantált, hogy a sheet SOSE üres, és sosem
    /// mutat rossz szerephez tartozó kódot.
    private var phase: PairingCodePhase {
        state.phase(for: role)
    }

    private var title: String {
        role == .child ? "Vanda másik eszközéhez" : "Szülő meghívása"
    }

    private var hint: String {
        role == .child
            ? "Írd be ezt a kódot a másik eszközödön, a Beállítások → Család képernyőn."
            : "Írd be ezt a kódot anya vagy apa telefonján, a szülő módban."
    }

    var body: some View {
        ZStack {
            Theme.BackgroundGradient.default.gradient
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.cardGap) {
                Text(title)
                    .font(.vandaDisplay())
                    .foregroundStyle(Color.ink)

                statusCard

                Text(hint)
                    .font(.vandaBody())
                    .foregroundStyle(Color.inkMuted)
                    .multilineTextAlignment(.center)

                actionButton

                Button("Kész") { dismiss() }
                    .font(.vandaBodyStrong(13))
                    .foregroundStyle(Color.inkMuted)
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
        }
        .onReceive(tick) { now = $0 }
    }

    // MARK: - Belső darabok

    @ViewBuilder
    private var statusCard: some View {
        switch phase {
        case .ready(let code):
            let isExpired = code.isExpired(at: now)
            VStack(spacing: 12) {
                Text(code.grouped)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isExpired ? Color.inkFaint : Color.ink)

                if isExpired {
                    Text("Ez a kód lejárt.")
                        .font(.vandaBody())
                        .foregroundStyle(Color.inkMuted)
                } else {
                    Text("Még \(code.remainingText(at: now)) percig érvényes")
                        .font(.vandaCaption())
                        .foregroundStyle(Color.inkMuted)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity)
            .vandaCard()

        case .failed(let message):
            // A hiba ITT jelenik meg, a nyitva lévő sheet belsejében — nem a
            // mögötte lévő képernyőn, ahol láthatatlan maradna, amíg a sheet
            // takarja. Lásd finding 1.
            VStack(spacing: 8) {
                Text("Nem sikerült kódot kérni.")
                    .font(.vandaBodyStrong())
                    .foregroundStyle(Color.ink)
                Text(message)
                    .font(.vandaBody())
                    .foregroundStyle(Color.zoneRedStrong)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .vandaCard()

        case .loading:
            // Sem kész kód, sem hiba a mi szerepünkhöz: a kérés folyamatban
            // van (vagy épp csak most indul) — sose maradjon üres a sheet.
            VStack(spacing: 12) {
                ProgressView()
                Text("Kód kérése…")
                    .font(.vandaCaption())
                    .foregroundStyle(Color.inkMuted)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .vandaCard()
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch phase {
        case .ready(let code):
            Button(code.isExpired(at: now) ? "Kérek újat" : "Új kódot kérek", action: onRefresh)
                .font(.vandaBodyStrong())
        case .failed:
            Button("Próbáld újra", action: onRefresh)
                .font(.vandaBodyStrong())
        case .loading:
            // A `statusCard` már mutat egy ProgressView-t — itt nem
            // duplázzuk, csak helyet foglalunk, hogy a "Kész" gomb ne
            // ugráljon a fázisváltásokkor.
            Color.clear.frame(height: 20)
        }
    }
}
