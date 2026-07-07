//
//  ReminderEditorView.swift
//  VandaApp
//
//  Emlékeztető felvétele / szerkesztése (spec 4.2): cím, saját szöveg, emoji,
//  szín, ütemezés (napok + időpontok), visszajelzés-kapcsoló.
//

import SwiftUI
import SwiftData

struct ReminderEditorView: View {
    /// nil = új emlékeztető készül
    let reminder: Reminder?
    let accent: Color

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var text = ""
    @State private var emoji = "🔔"
    @State private var colorHex = 0x8A7DE0
    /// `Calendar` konvenció (1 = vasárnap … 7 = szombat); mind a 7 = naponta
    @State private var selectedWeekdays: Set<Int> = Set(1...7)
    @State private var times: [Date] = [defaultTime]
    @State private var wantsFeedback = true

    private var isNew: Bool { reminder == nil }

    /// Hétfő-kezdő sorrend a chipekhez
    private static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    private static var defaultTime: Date {
        Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private static let colorOptions: [Int] = [
        0x8A7DE0, 0x5FB89C, 0xEC6F9E, 0xF2A65A, 0x6FA8E8, 0xE06A5E, 0x86CBB5, 0x3A3550,
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.BackgroundGradient.default.gradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
                        sectionLabel("Mi legyen?")
                        HStack(spacing: 10) {
                            TextField("🔔", text: $emoji)
                                .font(.system(size: 24))
                                .multilineTextAlignment(.center)
                                .frame(width: 54, height: 54)
                                .background(
                                    Color.surface,
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.iconContainer, style: .continuous)
                                )
                                .onChange(of: emoji) { _, newValue in
                                    if let first = newValue.first { emoji = String(first) }
                                }

                            TextField("pl. Vitamin", text: $title)
                                .font(.vandaBody(15))
                                .foregroundStyle(Color.ink)
                                .padding(14)
                                .background(
                                    Color.surface,
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous)
                                )
                        }

                        TextField("Az értesítés szövege — a te szavaiddal", text: $text, axis: .vertical)
                            .font(.vandaBody(15))
                            .foregroundStyle(Color.ink)
                            .padding(14)
                            .background(
                                Color.surface,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous)
                            )

                        sectionLabel("Szín")
                        HStack(spacing: 10) {
                            ForEach(Self.colorOptions, id: \.self) { hex in
                                Button {
                                    colorHex = hex
                                } label: {
                                    Circle()
                                        .fill(Color(hex: UInt32(hex)))
                                        .frame(width: 32, height: 32)
                                        .overlay {
                                            if colorHex == hex {
                                                Circle().strokeBorder(Color.ink, lineWidth: 2).padding(-4)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        sectionLabel("Mikor?")
                        weekdayChips
                        timesEditor

                        sectionLabel("Visszajelzés")
                        Toggle(isOn: $wantsFeedback) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("✓ Kész gomb az értesítésen")
                                    .font(.vandaBodyStrong())
                                    .foregroundStyle(Color.ink)
                                Text("A pipák a napi faladra kerülnek — csak neked.")
                                    .font(.vandaCaption())
                                    .foregroundStyle(Color.inkMuted)
                            }
                        }
                        .tint(accent)
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
            .navigationTitle(isNew ? "Új emlékeztető" : "Szerkesztés")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Mégse") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mentés") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty
                                  || selectedWeekdays.isEmpty
                                  || times.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.large])
    }

    // MARK: - Ütemezés-szerkesztő

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

    private var timesEditor: some View {
        VStack(spacing: 8) {
            ForEach(times.indices, id: \.self) { index in
                HStack {
                    DatePicker(
                        "Időpont",
                        selection: $times[index],
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()

                    Spacer()

                    if times.count > 1 {
                        Button {
                            times.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(Color.zoneRedStrong)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Időpont törlése")
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
                .background(
                    Color.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous)
                )
            }

            Button {
                times.append(Self.defaultTime)
            } label: {
                Label("Időpont hozzáadása", systemImage: "plus")
                    .font(.vandaBodyStrong(13))
                    .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
        }
    }

    // MARK: - Betöltés / mentés

    private func load() {
        guard let reminder else { return }
        title = reminder.title
        text = reminder.text
        emoji = reminder.symbolOrEmoji
        colorHex = reminder.colorHex
        wantsFeedback = reminder.wantsFeedback

        let schedule = reminder.schedule
        selectedWeekdays = schedule.isDaily ? Set(1...7) : Set(schedule.weekdays)
        let calendar = Calendar.current
        let loaded = schedule.times.compactMap {
            calendar.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: Date())
        }
        times = loaded.isEmpty ? [Self.defaultTime] : loaded
    }

    private func save() {
        let target = reminder ?? Reminder()
        target.title = title.trimmingCharacters(in: .whitespaces)
        target.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if target.text.isEmpty { target.text = target.title }
        target.symbolOrEmoji = emoji.isEmpty ? "🔔" : emoji
        target.colorHex = colorHex
        target.wantsFeedback = wantsFeedback

        var schedule = ReminderSchedule()
        let calendar = Calendar.current
        schedule.times = times.map {
            let components = calendar.dateComponents([.hour, .minute], from: $0)
            return ReminderSchedule.TimeOfDay(hour: components.hour ?? 8, minute: components.minute ?? 0)
        }
        if selectedWeekdays.count == 7 {
            schedule.frequency = .daily
            schedule.weekdays = []
        } else {
            schedule.frequency = .weekly
            schedule.weekdays = selectedWeekdays.sorted()
        }
        target.schedule = schedule

        if isNew {
            target.source = .custom
            modelContext.insert(target)
        }
        Task { await ReminderScheduler.shared.resyncFromStore() }
        dismiss()
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .vandaLabelStyle()
            .foregroundStyle(Color.inkFaint)
    }
}

#Preview {
    ReminderEditorView(reminder: nil, accent: Theme.Accent.default)
        .modelContainer(VandaStore.makeContainer())
}
