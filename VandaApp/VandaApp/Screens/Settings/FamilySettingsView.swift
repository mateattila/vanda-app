//
//  FamilySettingsView.swift
//  VandaApp
//
//  Vanda oldalán a család-párosítás. Lusta: az első indításkor nincs hálózati
//  hívás, a döntés (család létrehozása vs. kód beváltása) itt születik — így
//  nem keletkezhet árva vagy második család.
//

import SwiftUI
import SwiftData

struct FamilySettingsView: View {
    @Query private var themeSettings: [ThemeSettings]
    @State private var model = FamilyLinkModel()
    @State private var enteredCode = ""
    @State private var editedName = ""
    @State private var showCodeSheet = false
    /// A sheet szerepe: a gomb-koppintáskor, MÉG a hálózati hívás előtt
    /// állítjuk be, hogy a sheet azonnal, szinkron módon megjelenhessen —
    /// enélkül a `Task { await model.issueCode(...) }` lefutása előtti
    /// pillanatban a sheet-nek nem lenne mit mutatnia (lásd finding 1).
    @State private var codeRole: AppRole = .child
    @State private var showUnlinkConfirm = false

    private var theme: ThemeSettings? { themeSettings.first }
    private var cardSurface: Color { theme?.cardSurface ?? .surface }

    private var defaultDeviceName: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "Vanda iPadje" : "Vanda telefonja"
    }

    var body: some View {
        ZStack {
            ThemedBackground(settings: theme)

            ScrollView {
                VStack(spacing: Theme.Spacing.cardGap) {
                    if let credentials = model.credentials {
                        linkedSection(credentials)
                    } else {
                        unlinkedSection
                    }

                    // Látható jelzés, amíg bármelyik hálózati művelet fut —
                    // az `isBusy` egyetlen közös flag, ez a legegyszerűbb hely
                    // rá, hogy a képernyő ne tűnjön lefagyottnak lassú neten.
                    if model.isBusy {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Folyamatban…")
                                .font(.vandaBody())
                                .foregroundStyle(Color.inkMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .vandaCard(surface: cardSurface)
                    }

                    if let message = model.errorMessage {
                        Text(message)
                            .font(.vandaBody())
                            .foregroundStyle(Color.zoneRedStrong)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .vandaCard(surface: cardSurface)
                    }
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, Theme.Spacing.cardGap)
            }
        }
        .navigationTitle("Család")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showCodeSheet) {
            // Feltétel nélkül megjelenítjük — a `PairingCodeSheet` maga dönti
            // el a `codeRole`-lal szűrve, hogy kódot, hibát vagy betöltést
            // mutat, így sose renderelődik `EmptyView` (lásd finding 1).
            PairingCodeSheet(role: codeRole, state: model.codeState) {
                Task { await model.issueCode(role: codeRole) }
            }
        }
        .confirmationDialog(
            "Biztosan lekötöd ezt az eszközt a családról?",
            isPresented: $showUnlinkConfirm,
            titleVisibility: .visible
        ) {
            Button("Igen, leválasztom", role: .destructive) {
                Task { await model.unlink() }
            }
            Button("Mégsem", role: .cancel) {}
        } message: {
            Text("Utána újra kell párosítani, hogy a jelzések működjenek.")
        }
        .onAppear { editedName = model.credentials?.deviceName ?? defaultDeviceName }
    }

    // MARK: - Nincs összekötve

    private var unlinkedSection: some View {
        VStack(spacing: Theme.Spacing.cardGap) {
            VStack(spacing: 8) {
                Text("🫂")
                    .font(.system(size: 40))
                Text("Még nincs összekötve")
                    .font(.vandaBodyStrong())
                    .foregroundStyle(Color.ink)
                Text("Ha ez az első eszközöd, hozz létre családot. Ha kaptál egy hat jegyű kódot, azt írd be.")
                    .font(.vandaCaption())
                    .foregroundStyle(Color.inkMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .vandaCard(surface: cardSurface)

            Button {
                Task { await model.createFamily(deviceName: editedName) }
            } label: {
                Text("Család létrehozása")
                    .font(.vandaBodyStrong())
                    .frame(maxWidth: .infinity)
                    .vandaCard(surface: cardSurface)
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)

            VStack(alignment: .leading, spacing: 10) {
                Text("Kódot kaptam")
                    .font(.vandaBodyStrong())
                    .foregroundStyle(Color.ink)
                TextField("123456", text: $enteredCode)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .disabled(model.isBusy)
                Button("Csatlakozás") {
                    Task { await model.joinWithCode(enteredCode, deviceName: editedName) }
                }
                .font(.vandaBodyStrong())
                .disabled(enteredCode.count != 6 || model.isBusy)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .vandaCard(surface: cardSurface)
        }
    }

    // MARK: - Össze van kötve

    private func linkedSection(_ credentials: DeviceCredentials) -> some View {
        VStack(spacing: Theme.Spacing.cardGap) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Össze van kötve 💛")
                    .font(.vandaBodyStrong())
                    .foregroundStyle(Color.ink)
                Text(credentials.role == .child ? "Ez az eszköz a tiéd." : "Ez az eszköz szülő módban van.")
                    .font(.vandaCaption())
                    .foregroundStyle(Color.inkMuted)

                TextField("Eszköz neve", text: $editedName)
                    .font(.vandaBody())
                    .disabled(model.isBusy)
                    .onSubmit { Task { await model.rename(to: editedName) } }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .vandaCard(surface: cardSurface)

            actionRow(symbol: "person.badge.plus", title: "Szülő meghívása") {
                // A sheet-et AZONNAL, szinkron módon nyitjuk, mielőtt a
                // hálózati hívás elindulna — így a felhasználó sose lát üres
                // sheet-et a kérés ideje alatt (lásd finding 1).
                codeRole = .parent
                showCodeSheet = true
                Task { await model.issueCode(role: .parent) }
            }

            actionRow(symbol: "ipad.and.iphone", title: "Másik eszközöm hozzáadása") {
                codeRole = .child
                showCodeSheet = true
                Task { await model.issueCode(role: .child) }
            }

            actionRow(symbol: "bell.badge", title: "Teszt-üzenet küldése") {
                Task { await model.sendTestPush() }
            }

            if let results = model.testPushResults {
                // `model.failedCount` (tesztelve: FamilyLinkModelTests) a
                // forrás igazság arra, hogy volt-e kudarc — nem duplikáljuk
                // a `results`-on újraszámolva, hogy a nézetben ne éljen saját,
                // teszteletlen döntési logika.
                let hasFailures = model.failedCount > 0
                VStack(spacing: 6) {
                    Text(TestPushSummary.text(for: results))
                        .font(.vandaBody())
                        .foregroundStyle(hasFailures ? Color.zoneOrangeStrong : Color.ink)
                        .multilineTextAlignment(.center)
                    if hasFailures {
                        Text("Ha nem jött meg, ellenőrizzétek, hogy a szülő telefonján be van-e kapcsolva az értesítés.")
                            .font(.vandaCaption())
                            .foregroundStyle(Color.inkMuted)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .vandaCard(surface: cardSurface)
            }

            Button("Összeköttetés bontása") { showUnlinkConfirm = true }
                .font(.vandaBodyStrong(13))
                .foregroundStyle(Color.inkMuted)
                .disabled(model.isBusy)
        }
    }

    private func actionRow(symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.cardPadding) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme?.accentColor ?? Theme.Accent.default)
                    .frame(width: 34, height: 34)
                    .background(
                        Color.surfaceTint,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.iconContainer, style: .continuous)
                    )
                Text(title)
                    .font(.vandaBodyStrong())
                    .foregroundStyle(Color.ink)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .vandaCard(surface: cardSurface)
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
    }
}

#Preview {
    NavigationStack {
        FamilySettingsView()
    }
    .modelContainer(VandaStore.makeContainer())
}
