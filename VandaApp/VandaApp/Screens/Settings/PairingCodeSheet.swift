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
    let code: PairingCode
    /// Igaz, amíg a modellben bármilyen hálózati művelet fut — az „Új kódot
    /// kérek" is `issueCode`-ot hív, tehát ugyanannak a `claim()`-nek van
    /// kitéve, mint a főképernyő gombjai. Enélkül egy dupla koppintás
    /// csendben elveszne (lásd FamilyLinkModel.claim).
    let isBusy: Bool
    let onRefresh: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // A visszaszámlálás logikája a PairingCode-ban van (tesztelt), itt csak megjelenik.
    private var isExpired: Bool { code.isExpired(at: now) }
    private var countdownText: String { code.remainingText(at: now) }

    private var title: String {
        code.role == .child ? "Vanda másik eszközéhez" : "Szülő meghívása"
    }

    private var hint: String {
        code.role == .child
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
                        Text("Még \(countdownText) percig érvényes")
                            .font(.vandaCaption())
                            .foregroundStyle(Color.inkMuted)
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity)
                .vandaCard()

                Text(hint)
                    .font(.vandaBody())
                    .foregroundStyle(Color.inkMuted)
                    .multilineTextAlignment(.center)

                if isBusy {
                    ProgressView()
                } else {
                    Button(isExpired ? "Kérek újat" : "Új kódot kérek", action: onRefresh)
                        .font(.vandaBodyStrong())
                }

                Button("Kész") { dismiss() }
                    .font(.vandaBodyStrong(13))
                    .foregroundStyle(Color.inkMuted)
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
        }
        .onReceive(tick) { now = $0 }
    }
}
