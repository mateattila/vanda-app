//
//  ParentModeView.swift
//  VandaApp
//
//  Szülő mód: párosítás 6 jegyű kóddal, push-engedély, eszköznév.
//  A riasztások fogadása a 4.3-ban érkezik ide.
//

import SwiftUI
import UIKit

struct ParentModeView: View {
    @AppStorage("appRole") private var appRoleRaw: String = ""
    @State private var model = FamilyLinkModel()
    @State private var permission = NotificationPermission()
    @State private var enteredCode = ""
    @State private var deviceName = ""
    @State private var showUnlinkConfirm = false

    private var defaultDeviceName: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "Szülő iPadje" : "Szülő telefonja"
    }

    var body: some View {
        ZStack {
            Theme.BackgroundGradient.default.gradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.Spacing.cardGap) {
                    if model.isLinked {
                        linkedSection
                    } else {
                        pairingSection
                    }

                    // Látható jelzés, amíg bármelyik hálózati művelet fut —
                    // ugyanaz a minta, mint Vanda Család képernyőjén: az
                    // `isBusy` egyetlen közös flag, ez a legegyszerűbb hely
                    // rá, hogy a képernyő ne tűnjön lefagyottnak lassú neten.
                    if model.isBusy {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Folyamatban…")
                                .font(.vandaBody())
                                .foregroundStyle(Color.inkMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .vandaCard()
                    }

                    if let message = model.errorMessage {
                        Text(message)
                            .font(.vandaBody())
                            .foregroundStyle(Color.zoneRedStrong)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .vandaCard()
                    }

                    Button("Másik szerepet választok") { appRoleRaw = "" }
                        .font(.vandaBodyStrong(13))
                        .foregroundStyle(Color.inkMuted)
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, Theme.Spacing.cardGap)
            }
        }
        .task { await permission.refresh() }
        .onAppear { deviceName = model.credentials?.deviceName ?? defaultDeviceName }
        .confirmationDialog(
            "Biztosan leválasztod ezt az eszközt?",
            isPresented: $showUnlinkConfirm,
            titleVisibility: .visible
        ) {
            Button("Igen, leválasztom", role: .destructive) {
                Task { await model.unlink() }
            }
            Button("Mégsem", role: .cancel) {}
        } message: {
            Text("Utána Vanda jelzései nem érkeznek meg ide.")
        }
    }

    // MARK: - Párosítás

    private var pairingSection: some View {
        VStack(spacing: Theme.Spacing.cardGap) {
            VStack(spacing: 8) {
                Text("🫶")
                    .font(.system(size: 48))
                Text("Párosítás Vandával")
                    .font(.vandaDisplay())
                    .foregroundStyle(Color.ink)
                Text("Kérj Vandától egy hat jegyű kódot a telefonján: Beállítások → Család → Szülő meghívása.")
                    .font(.vandaBody())
                    .foregroundStyle(Color.inkMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .vandaCard()

            VStack(alignment: .leading, spacing: 10) {
                TextField("123456", text: $enteredCode)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .disabled(model.isBusy)

                TextField("Eszköz neve", text: $deviceName)
                    .font(.vandaBody())
                    .disabled(model.isBusy)

                Button("Csatlakozás") {
                    Task {
                        await model.joinWithCode(enteredCode, deviceName: deviceName)
                        // Párosítás után azonnal kérjük az engedélyt — ez a
                        // legjobb pillanat, mert itt derül ki, mire kell. A
                        // push-token feltöltését a `FamilyLinkModel` már
                        // maga elvégzi minden hívása végén (lásd `run(_:)`),
                        // így itt nincs szükség külön `flush()`-ra.
                        if model.isLinked, permission.status == .notDetermined {
                            await permission.request()
                        }
                    }
                }
                .font(.vandaBodyStrong())
                .disabled(enteredCode.count != 6 || model.isBusy)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .vandaCard()
        }
    }

    // MARK: - Össze van kötve

    private var linkedSection: some View {
        VStack(spacing: Theme.Spacing.cardGap) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Össze vagytok kötve 💛")
                    .font(.vandaBodyStrong())
                    .foregroundStyle(Color.ink)
                Text("Vanda jelzései ide fognak érkezni.")
                    .font(.vandaCaption())
                    .foregroundStyle(Color.inkMuted)
                TextField("Eszköz neve", text: $deviceName)
                    .font(.vandaBody())
                    .disabled(model.isBusy)
                    .onSubmit { Task { await model.rename(to: deviceName) } }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .vandaCard()

            if permission.needsAttention {
                permissionCard
            }

            Button("Összeköttetés bontása") { showUnlinkConfirm = true }
                .font(.vandaBodyStrong(13))
                .foregroundStyle(Color.inkMuted)
                .disabled(model.isBusy)
        }
    }

    private var permissionCard: some View {
        VStack(spacing: 10) {
            Text("Az értesítések ki vannak kapcsolva")
                .font(.vandaBodyStrong())
                .foregroundStyle(Color.ink)
            Text("Enélkül nem jelenik meg Vanda jelzése ezen a telefonon.")
                .font(.vandaCaption())
                .foregroundStyle(Color.inkMuted)
                .multilineTextAlignment(.center)

            Button(permission.requiresSettingsTrip ? "Beállítások megnyitása" : "Értesítések bekapcsolása") {
                Task {
                    if permission.requiresSettingsTrip {
                        if let url = NotificationPermission.settingsURL() {
                            await UIApplication.shared.open(url)
                        }
                    } else {
                        await permission.request()
                    }
                }
            }
            .font(.vandaBodyStrong())
        }
        .frame(maxWidth: .infinity)
        .vandaCard()
    }
}

#Preview {
    ParentModeView()
}
