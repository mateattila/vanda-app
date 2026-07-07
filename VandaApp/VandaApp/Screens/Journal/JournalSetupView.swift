//
//  JournalSetupView.swift
//  VandaApp
//
//  A napló első beállítása: PIN választás + megerősítés, majd a recovery-kulcs
//  EGYSZERI megjelenítése („a boríték maga a pecsét" — spec 4.5).
//

import SwiftUI

struct JournalSetupView: View {
    let vault: JournalVault
    /// A teljes flow végén (recovery-kód nyugtázva) hívódik.
    let onDone: () -> Void

    @State private var step: Step = .intro
    @State private var pin = ""
    @State private var firstPIN = ""
    @State private var mismatch = false
    @State private var recoveryCode = ""
    @State private var hasWrittenDown = false

    private enum Step {
        case intro, choosePIN, confirmPIN, recovery
    }

    var body: some View {
        ZStack {
            Theme.Gradients.journalEntry.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.cardGap) {
                switch step {
                case .intro: introStep
                case .choosePIN: pinStep(title: "Válassz egy PIN-kódot", subtitle: "4 számjegy — ezt csak te tudd, a szüleid sem.")
                case .confirmPIN: pinStep(title: "Még egyszer", subtitle: "Írd be újra, hogy biztos jól menjen.")
                case .recovery: recoveryStep
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
        }
    }

    // MARK: - Lépések

    private var introStep: some View {
        VStack(spacing: Theme.Spacing.cardGap) {
            Spacer()
            Image(systemName: "lock.heart.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(Color.panicChipSurface, in: Circle())
            Text("A te naplód")
                .font(.vandaDisplay())
                .foregroundStyle(.white)
            Text("Amit ide írsz, az csak a tiéd: a telefonod titkosítva tárolja, és olvashatóan soha nem kerül ki róla. A zárhoz PIN-t választasz, és kapsz egy recovery-kulcsot — az megy a lezárt borítékba.")
                .font(.vandaBody())
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)

            Button {
                step = .choosePIN
            } label: {
                Text("Csináljuk! 🔐")
                    .font(.vandaBodyStrong(15))
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            Spacer()
        }
    }

    private func pinStep(title: String, subtitle: String) -> some View {
        VStack(spacing: Theme.Spacing.cardGap) {
            Spacer()
            Text(title)
                .font(.vandaDisplay(20))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.vandaBody(13))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)

            PinDots(filled: pin.count, total: 4)
                .padding(.vertical, 8)

            if mismatch {
                Text("A két kód nem egyezett — kezdjük újra!")
                    .font(.vandaBodyStrong(13))
                    .foregroundStyle(Color.zoneRed)
            }

            PinPad(pin: $pin, maxLength: 4) { entered in
                handlePIN(entered)
            }
            Spacer()
        }
    }

    private var recoveryStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
            Spacer()
            Text("A pecsét: recovery-kulcs")
                .font(.vandaDisplay(20))
                .foregroundStyle(.white)
            Text("Ez a kulcs MOST látszik utoljára. Írjátok le, tegyétek lezárt borítékba — ha valaha ezzel nyitják ki a naplót, azt te látni fogod.")
                .font(.vandaBody(13))
                .foregroundStyle(.white.opacity(0.8))

            Text(recoveryCode)
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous))
                .textSelection(.enabled)

            Toggle(isOn: $hasWrittenDown) {
                Text("Leírtuk, borítékba tettük")
                    .font(.vandaBodyStrong(14))
                    .foregroundStyle(.white)
            }
            .tint(.zoneGreen)

            Button {
                recoveryCode = ""
                onDone()
            } label: {
                Text("Kész, mehet a napló ✨")
                    .font(.vandaBodyStrong(15))
                    .foregroundStyle(hasWrittenDown ? Color.ink : Color.inkFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Color.white.opacity(hasWrittenDown ? 1 : 0.5),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!hasWrittenDown)
            Spacer()
        }
    }

    private func handlePIN(_ entered: String) {
        switch step {
        case .choosePIN:
            firstPIN = entered
            pin = ""
            mismatch = false
            step = .confirmPIN
        case .confirmPIN:
            if entered == firstPIN {
                if let code = try? vault.setUp(pin: entered) {
                    recoveryCode = code
                    step = .recovery
                }
            } else {
                pin = ""
                firstPIN = ""
                mismatch = true
                step = .choosePIN
            }
        default:
            break
        }
    }
}
