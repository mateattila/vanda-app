//
//  MoodSettingsView.swift
//  VandaApp
//
//  Barométer-beállítások (spec 4.3): zónahatárok, napi rákérdezések idősávja,
//  kérdésbank-szint, megosztás-kapcsolók (élesben a 4. fázistól).
//

import SwiftUI
import SwiftData

struct MoodSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var themeSettings: [ThemeSettings]
    @Query private var moodSettingsList: [MoodSettings]

    private var theme: ThemeSettings? { themeSettings.first }
    private var accent: Color { theme?.accentColor ?? Theme.Accent.default }
    private var cardSurface: Color { theme?.cardSurface ?? .surface }

    private var settings: MoodSettings {
        moodSettingsList.first ?? MoodSettings.ensureCurrent(in: modelContext)
    }

    var body: some View {
        ZStack {
            ThemedBackground(settings: theme)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
                    sectionLabel("Zónahatárok")
                    VStack(spacing: 10) {
                        zoneRow(zone: .green, text: "Zöld e fölött:") {
                            Stepper(value: greenBinding, in: (settings.orangeMinPercent + 5)...95, step: 5) {
                                Text("\(settings.greenMinPercent)%")
                                    .font(.vandaBodyStrong())
                                    .foregroundStyle(Color.ink)
                            }
                        }
                        zoneRow(zone: .orange, text: "Narancs e fölött:") {
                            Stepper(value: orangeBinding, in: 5...(settings.greenMinPercent - 5), step: 5) {
                                Text("\(settings.orangeMinPercent)%")
                                    .font(.vandaBodyStrong())
                                    .foregroundStyle(Color.ink)
                            }
                        }
                        HStack {
                            Circle().fill(MoodZone.red.strongColor).frame(width: 12, height: 12)
                            Text("Alatta piros — „kimerül”")
                                .font(.vandaCaption())
                                .foregroundStyle(Color.inkMuted)
                            Spacer()
                        }
                    }
                    .padding(14)
                    .background(cardSurface, in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous))
                    .softShadow()

                    sectionLabel("Napi rákérdezés")
                    VStack(spacing: 10) {
                        Stepper(value: promptsBinding, in: 0...2) {
                            Text(settings.promptsPerDay == 0 ? "Kikapcsolva" : "Naponta \(settings.promptsPerDay)×")
                                .font(.vandaBody())
                                .foregroundStyle(Color.ink)
                        }
                        if settings.promptsPerDay > 0 {
                            Stepper(value: windowStartBinding, in: 6...(settings.promptWindowEndHour - 1)) {
                                Text("Ettől: \(settings.promptWindowStartHour):00")
                                    .font(.vandaBody())
                                    .foregroundStyle(Color.ink)
                            }
                            Stepper(value: windowEndBinding, in: (settings.promptWindowStartHour + 1)...22) {
                                Text("Eddig: \(settings.promptWindowEndHour):00")
                                    .font(.vandaBody())
                                    .foregroundStyle(Color.ink)
                            }
                            Text("Az időpont a sávon belül véletlenszerű — sosem kiszámítható időben jön.")
                                .font(.vandaCaption())
                                .foregroundStyle(Color.inkFaint)
                        }
                    }
                    .padding(14)
                    .background(cardSurface, in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous))
                    .softShadow()

                    sectionLabel("Kérdések")
                    VStack(spacing: 10) {
                        Toggle(isOn: questionsBinding) {
                            Text("Kérdés az aksi% után")
                                .font(.vandaBody())
                                .foregroundStyle(Color.ink)
                        }
                        .tint(accent)
                        if settings.questionsEnabled {
                            Picker("Mélység", selection: levelBinding) {
                                Text("Könnyű").tag(1)
                                Text("Közepes").tag(2)
                                Text("Mély is").tag(3)
                            }
                            .pickerStyle(.segmented)
                            Text("Minden kérdés átugorható — a válasz csak a te eszközeiden marad.")
                                .font(.vandaCaption())
                                .foregroundStyle(Color.inkFaint)
                        }
                    }
                    .padding(14)
                    .background(cardSurface, in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous))
                    .softShadow()

                    sectionLabel("Megosztás a szülőkkel")
                    VStack(spacing: 10) {
                        Toggle(isOn: shareMoodBinding) {
                            Text("Napi aksi% és zóna")
                                .font(.vandaBody())
                                .foregroundStyle(Color.ink)
                        }
                        .tint(accent)
                        Toggle(isOn: shareProgressBinding) {
                            Text("Napi progress %")
                                .font(.vandaBody())
                                .foregroundStyle(Color.ink)
                        }
                        .tint(accent)
                        Text("Ez a kapcsoló a 4. fázisban élesedik — addig semmi nem megy ki. A kérdésekre adott válaszaid SOHA nem oszthatók meg.")
                            .font(.vandaCaption())
                            .foregroundStyle(Color.inkFaint)
                    }
                    .padding(14)
                    .background(cardSurface, in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous))
                    .softShadow()
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.vertical, Theme.Spacing.cardGap)
            }
        }
        .navigationTitle("Barométer")
        .navigationBarTitleDisplayMode(.large)
        .onDisappear {
            let container = modelContext.container
            Task { await MoodPromptScheduler.shared.resyncFromStore(container: container) }
        }
    }

    private func zoneRow<Content: View>(zone: MoodZone, text: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Circle().fill(zone.strongColor).frame(width: 12, height: 12)
            Text(text)
                .font(.vandaBody())
                .foregroundStyle(Color.ink)
            Spacer()
            content()
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .vandaLabelStyle()
            .foregroundStyle(Color.inkFaint)
    }

    // MARK: - Bindingok (a SwiftData-objektumra írnak)

    private var greenBinding: Binding<Int> {
        Binding(get: { settings.greenMinPercent }, set: { settings.greenMinPercent = $0 })
    }
    private var orangeBinding: Binding<Int> {
        Binding(get: { settings.orangeMinPercent }, set: { settings.orangeMinPercent = $0 })
    }
    private var promptsBinding: Binding<Int> {
        Binding(get: { settings.promptsPerDay }, set: { settings.promptsPerDay = $0 })
    }
    private var windowStartBinding: Binding<Int> {
        Binding(get: { settings.promptWindowStartHour }, set: { settings.promptWindowStartHour = $0 })
    }
    private var windowEndBinding: Binding<Int> {
        Binding(get: { settings.promptWindowEndHour }, set: { settings.promptWindowEndHour = $0 })
    }
    private var questionsBinding: Binding<Bool> {
        Binding(get: { settings.questionsEnabled }, set: { settings.questionsEnabled = $0 })
    }
    private var levelBinding: Binding<Int> {
        Binding(get: { settings.questionMaxLevel }, set: { settings.questionMaxLevel = $0 })
    }
    private var shareMoodBinding: Binding<Bool> {
        Binding(get: { settings.shareMoodWithParents }, set: { settings.shareMoodWithParents = $0 })
    }
    private var shareProgressBinding: Binding<Bool> {
        Binding(get: { settings.shareProgressWithParents }, set: { settings.shareProgressWithParents = $0 })
    }
}

#Preview {
    NavigationStack {
        MoodSettingsView()
    }
    .modelContainer(VandaStore.makeContainer())
}
