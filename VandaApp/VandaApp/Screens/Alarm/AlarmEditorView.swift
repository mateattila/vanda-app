//
//  AlarmEditorView.swift
//  VandaApp
//
//  Ébresztő-beállító (design 07): idő + napok · saját hang · 🔗 lánc-ébresztő ·
//  🧩 feladvány-nehézség (Nincs/Könnyű/Kemény).
//

import SwiftUI
import SwiftData

struct AlarmEditorView: View {
    /// nil = új ébresztő készül
    let profile: AlarmProfile?
    let accent: Color

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allProfiles: [AlarmProfile]

    @State private var name = ""
    @State private var time = defaultTime
    @State private var selectedWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var soundFileName: String?
    @State private var isChainEnabled = true
    @State private var chainCount = 5
    @State private var chainIntervalMinutes = 2
    @State private var puzzleChoice: PuzzleChoice = .easy
    @State private var requiredCorrect = 3
    @State private var isSoundPickerPresented = false

    private var isNew: Bool { profile == nil }

    private enum PuzzleChoice: String, CaseIterable, Identifiable {
        case none, easy, hard
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: "Nincs"
            case .easy: "Könnyű"
            case .hard: "Kemény"
            }
        }
    }

    private static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    private static var defaultTime: Date {
        Calendar.current.date(bySettingHour: 6, minute: 45, second: 0, of: Date()) ?? Date()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.BackgroundGradient.default.gradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
                        DatePicker("Időpont", selection: $time, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                            .background(
                                Color.surface,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            )

                        weekdayChips

                        TextField("Név (pl. Suli)", text: $name)
                            .font(.vandaBody(15))
                            .foregroundStyle(Color.ink)
                            .padding(14)
                            .background(
                                Color.surface,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous)
                            )

                        sectionLabel("Hang")
                        Button {
                            isSoundPickerPresented = true
                        } label: {
                            HStack {
                                Image(systemName: "music.note")
                                    .foregroundStyle(accent)
                                Text(soundFileName ?? "Alapértelmezett csörgés")
                                    .font(.vandaBody())
                                    .foregroundStyle(Color.ink)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.inkFaint)
                            }
                            .padding(14)
                            .background(
                                Color.surface,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)

                        sectionLabel("Lánc-ébresztő")
                        VStack(spacing: 10) {
                            Toggle(isOn: $isChainEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("🔗 Lánc-ébresztő")
                                        .font(.vandaBodyStrong())
                                        .foregroundStyle(Color.ink)
                                    Text("Amíg az appban meg nem oldod a feladványt, pár percenként újra csörög.")
                                        .font(.vandaCaption())
                                        .foregroundStyle(Color.inkMuted)
                                }
                            }
                            .tint(accent)

                            if isChainEnabled {
                                Stepper(value: $chainCount, in: 2...10) {
                                    Text("\(chainCount) csörgés")
                                        .font(.vandaBody())
                                        .foregroundStyle(Color.ink)
                                }
                                Stepper(value: $chainIntervalMinutes, in: 1...10) {
                                    Text("\(chainIntervalMinutes) percenként")
                                        .font(.vandaBody())
                                        .foregroundStyle(Color.ink)
                                }
                            }
                        }
                        .padding(14)
                        .background(
                            Color.surface,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous)
                        )

                        sectionLabel("Kikapcsoló feladvány")
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Feladvány", selection: $puzzleChoice) {
                                ForEach(PuzzleChoice.allCases) { choice in
                                    Text(choice.label).tag(choice)
                                }
                            }
                            .pickerStyle(.segmented)

                            if puzzleChoice != .none {
                                Stepper(value: $requiredCorrect, in: 1...5) {
                                    Text("\(requiredCorrect) jó válasz kell")
                                        .font(.vandaBody())
                                        .foregroundStyle(Color.ink)
                                }
                            }
                        }
                        .padding(14)
                        .background(
                            Color.surface,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous)
                        )
                    }
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                    .padding(.vertical, Theme.Spacing.cardGap)
                }
            }
            .navigationTitle(isNew ? "Új ébresztő" : "Szerkesztés")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Mégse") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mentés") { save() }
                }
            }
            .sheet(isPresented: $isSoundPickerPresented) {
                SoundLibraryView(selectedFileName: $soundFileName, accent: accent)
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.large])
    }

    private var weekdayChips: some View {
        HStack(spacing: 6) {
            ForEach(Self.weekdayOrder, id: \.self) { weekday in
                let isOn = selectedWeekdays.contains(weekday)
                Button {
                    if isOn { selectedWeekdays.remove(weekday) } else { selectedWeekdays.insert(weekday) }
                } label: {
                    Text(ReminderSchedule.dayAbbreviations[weekday] ?? "?")
                        .font(.vandaBodyStrong(13))
                        .foregroundStyle(isOn ? .white : Color.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.chipVertical)
                        .background(isOn ? accent : Color.surface, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func load() {
        guard let profile else { return }
        name = profile.name
        time = Calendar.current.date(
            bySettingHour: profile.hour, minute: profile.minute, second: 0, of: Date()
        ) ?? Self.defaultTime
        selectedWeekdays = Set(profile.repeatWeekdays)
        soundFileName = profile.soundFileName
        isChainEnabled = profile.isChainEnabled
        chainCount = profile.chainCount
        chainIntervalMinutes = profile.chainIntervalMinutes
        requiredCorrect = profile.puzzleRequiredCorrect
        switch (profile.puzzleKind, profile.puzzleDifficulty) {
        case (.none, _): puzzleChoice = .none
        case (.math, ..<2): puzzleChoice = .easy
        case (.math, _): puzzleChoice = .hard
        }
    }

    private func save() {
        let target = profile ?? AlarmProfile()
        target.name = name.trimmingCharacters(in: .whitespaces)
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        target.hour = components.hour ?? 6
        target.minute = components.minute ?? 45
        target.repeatWeekdays = selectedWeekdays.sorted()
        target.soundFileName = soundFileName
        target.isChainEnabled = isChainEnabled
        target.chainCount = chainCount
        target.chainIntervalMinutes = chainIntervalMinutes
        target.puzzleRequiredCorrect = requiredCorrect
        switch puzzleChoice {
        case .none:
            target.puzzleKind = .none
        case .easy:
            target.puzzleKind = .math
            target.puzzleDifficulty = 1
        case .hard:
            target.puzzleKind = .math
            target.puzzleDifficulty = 2
        }
        target.isEnabled = true

        if isNew {
            modelContext.insert(target)
        }
        var snapshot = allProfiles
        if isNew { snapshot.append(target) }
        Task { await AlarmScheduler.shared.resync(profiles: snapshot) }
        dismiss()
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .vandaLabelStyle()
            .foregroundStyle(Color.inkFaint)
    }
}

#Preview {
    AlarmEditorView(profile: nil, accent: Theme.Accent.default)
        .modelContainer(VandaStore.makeContainer())
}
