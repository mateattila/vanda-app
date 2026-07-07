//
//  JournalLockView.swift
//  VandaApp
//
//  Napló-belépés (design 04): sötét környezet, PIN-pöttyök + numpad.
//  Elfelejtett PIN → recovery-kulcsos nyitás (pecsét: audit-esemény + banner),
//  utána új PIN kötelező.
//

import SwiftUI
import SwiftData

struct JournalLockView: View {
    let vault: JournalVault

    @Environment(\.modelContext) private var modelContext
    @State private var pin = ""
    @State private var isWrong = false
    @State private var isRecoveryPresented = false

    var body: some View {
        ZStack {
            Theme.Gradients.journalEntry
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.cardGap) {
                Spacer()

                Image(systemName: "lock.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 72, height: 72)
                    .background(Color.panicChipSurface, in: Circle())

                Text("A te naplód")
                    .font(.vandaDisplay())
                    .foregroundStyle(.white)
                Text("Ez csak a tiéd. Írd be a kódod a belépéshez.")
                    .font(.vandaBody(13))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)

                PinDots(filled: pin.count, total: 4)
                    .padding(.vertical, 8)

                if isWrong {
                    Text("Nem jó kód — próbáld újra!")
                        .font(.vandaBodyStrong(13))
                        .foregroundStyle(Color.zoneRed)
                }

                PinPad(pin: $pin, maxLength: 4) { entered in
                    attemptUnlock(entered)
                }

                Button("Elfelejtetted? Nyitás recovery-kulccsal") {
                    isRecoveryPresented = true
                }
                .font(.vandaCaption())
                .foregroundStyle(.white.opacity(0.55))
                .padding(.bottom, Theme.Spacing.screenMargin)

                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
        }
        .sheet(isPresented: $isRecoveryPresented) {
            RecoveryUnlockView(vault: vault)
        }
    }

    private func attemptUnlock(_ entered: String) {
        // A PBKDF2 szándékosan lassú — háttérszálon fut, addig a pöttyök tele vannak.
        Task {
            do {
                try vault.unlock(pin: entered)
                isWrong = false
            } catch {
                isWrong = true
            }
            pin = ""
        }
    }
}

// MARK: - Recovery-nyitás

struct RecoveryUnlockView: View {
    let vault: JournalVault

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var errorText: String?
    @State private var newPIN = ""
    @State private var isUnlocked = false

    var body: some View {
        ZStack {
            Theme.Gradients.journalEntry.ignoresSafeArea()

            VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
                if !isUnlocked {
                    recoveryStep
                } else {
                    newPINStep
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, Theme.Spacing.screenMargin)
        }
        .interactiveDismissDisabled(isUnlocked)
    }

    private var recoveryStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
            Text("Nyitás recovery-kulccsal")
                .font(.vandaDisplay(20))
                .foregroundStyle(.white)

            Text("A borítékban lévő kódot írd be. Fontos, hogy tudd: a recovery-nyitás nyomot hagy — a napló jelezni fogja, hogy ezzel a kulccsal nyitották ki.")
                .font(.vandaBody(13))
                .foregroundStyle(.white.opacity(0.75))

            TextField("XXXX-XXXX-XXXX-…", text: $code)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous))

            if let errorText {
                Text(errorText)
                    .font(.vandaBodyStrong(13))
                    .foregroundStyle(Color.zoneRed)
            }

            Button {
                attempt()
            } label: {
                Text("Kinyitom — vállalom, hogy nyoma marad")
                    .font(.vandaBodyStrong(14))
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            }
            .buttonStyle(.plain)

            Button("Mégse") { dismiss() }
                .font(.vandaBodyStrong(13))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity)

            Spacer()
        }
    }

    private var newPINStep: some View {
        VStack(spacing: Theme.Spacing.cardGap) {
            Text("Új PIN-kód")
                .font(.vandaDisplay(20))
                .foregroundStyle(.white)
            Text("A napló kinyílt. Adj meg egy új, 4 számjegyű kódot — ezt csak te tudd.")
                .font(.vandaBody(13))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)

            PinDots(filled: newPIN.count, total: 4)
                .padding(.vertical, 8)

            PinPad(pin: $newPIN, maxLength: 4) { entered in
                try? vault.setNewPIN(entered)
                dismiss()
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func attempt() {
        do {
            try vault.unlockWithRecovery(code: code, context: modelContext)
            errorText = nil
            isUnlocked = true
        } catch {
            errorText = "Ez a kód így nem stimmel — nézd meg még egyszer a borítékban."
        }
    }
}
