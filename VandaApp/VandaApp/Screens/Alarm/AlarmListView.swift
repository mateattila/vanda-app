//
//  AlarmListView.swift
//  VandaApp
//
//  Ébresztő fül (spec 4.1): profilok listája, ki-be kapcsolás, szerkesztés.
//  A megszólalás rendszer-UI (AlarmKit), azt nem mi rajzoljuk.
//

import SwiftUI
import SwiftData

struct AlarmListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AlarmProfile.createdAt) private var profiles: [AlarmProfile]
    @Query private var themeSettings: [ThemeSettings]

    @State private var editorProfile: AlarmProfile?
    @State private var isCreatingNew = false
    @State private var authorizationDenied = false

    private var theme: ThemeSettings? { themeSettings.first }
    private var accent: Color { theme?.accentColor ?? Theme.Accent.default }
    private var cardSurface: Color { theme?.cardSurface ?? .surface }

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground(settings: theme)

                ScrollView {
                    VStack(spacing: Theme.Spacing.cardGap) {
                        if authorizationDenied {
                            deniedBanner
                        }
                        if profiles.isEmpty {
                            emptyState
                        }
                        ForEach(profiles) { profile in
                            alarmRow(profile)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                    .padding(.vertical, Theme.Spacing.cardGap)
                }
            }
            .navigationTitle("Ébresztő")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCreatingNew = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Új ébresztő")
                }
            }
            .sheet(item: $editorProfile) { profile in
                AlarmEditorView(profile: profile, accent: accent)
            }
            .sheet(isPresented: $isCreatingNew) {
                AlarmEditorView(profile: nil, accent: accent)
            }
            .task {
                authorizationDenied = !(await AlarmScheduler.shared.ensureAuthorization())
                await AlarmScheduler.shared.resync(profiles: profiles)
            }
        }
    }

    private func alarmRow(_ profile: AlarmProfile) -> some View {
        HStack(spacing: Theme.Spacing.cardPadding) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(format: "%d:%02d", profile.hour, profile.minute))
                    .font(.vandaBigNumber(38))
                    .foregroundStyle(profile.isEnabled ? Color.ink : Color.inkFaint)

                Text(daysSummary(profile))
                    .font(.vandaCaption())
                    .foregroundStyle(Color.inkMuted)

                HStack(spacing: 8) {
                    if !profile.name.isEmpty {
                        Text(profile.name)
                    }
                    if profile.isChainEnabled {
                        Text("🔗 \(profile.chainCount)×\(profile.chainIntervalMinutes)′")
                    }
                    if profile.puzzleKind != AlarmPuzzleKind.none {
                        Text("🧩 \(profile.puzzleDifficulty >= 2 ? "kemény" : "könnyű")")
                    }
                    if let sound = profile.soundFileName {
                        Text("🎵 \(sound)").lineLimit(1)
                    }
                }
                .font(.vandaCaption(11))
                .foregroundStyle(Color.inkFaint)
            }

            Spacer()

            Toggle("", isOn: enabledBinding(profile))
                .labelsHidden()
                .tint(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vandaCard(surface: cardSurface)
        .contentShape(Rectangle())
        .onTapGesture { editorProfile = profile }
        .contextMenu {
            Button {
                editorProfile = profile
            } label: {
                Label("Szerkesztés", systemImage: "pencil")
            }
            Button(role: .destructive) {
                let target = profile
                Task { await AlarmScheduler.shared.removeAll(for: target) }
                modelContext.delete(profile)
            } label: {
                Label("Törlés", systemImage: "trash")
            }
        }
    }

    private func daysSummary(_ profile: AlarmProfile) -> String {
        if profile.repeatWeekdays.isEmpty { return "Egyszeri" }
        if profile.repeatWeekdays.count == 7 { return "Minden nap" }
        if Set(profile.repeatWeekdays) == Set([2, 3, 4, 5, 6]) { return "Hétköznap" }
        return profile.repeatWeekdays
            .sorted { ($0 == 1 ? 8 : $0) < ($1 == 1 ? 8 : $1) }
            .compactMap { ReminderSchedule.dayAbbreviations[$0] }
            .joined(separator: " · ")
    }

    private func enabledBinding(_ profile: AlarmProfile) -> Binding<Bool> {
        Binding(
            get: { profile.isEnabled },
            set: { newValue in
                profile.isEnabled = newValue
                let snapshot = profiles
                Task { await AlarmScheduler.shared.resync(profiles: snapshot) }
            }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("⏰")
                .font(.system(size: 44))
            Text("Még nincs ébresztőd")
                .font(.vandaDisplay(20))
                .foregroundStyle(Color.ink)
            Text("A + gombbal csinálhatsz egyet — a kedvenc zenéddel, lánc-ébresztéssel, feladvánnyal.")
                .font(.vandaBody(13))
                .foregroundStyle(Color.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .vandaCard(surface: cardSurface)
    }

    private var deniedBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("⏰ Az ébresztő-engedély hiányzik")
                .font(.vandaBodyStrong())
                .foregroundStyle(Color.ink)
            Text("Az app nem tud csörögni, amíg a rendszer-Beállításokban nem engedélyezed az ébresztőket.")
                .font(.vandaBody(13))
                .foregroundStyle(Color.inkMuted)
            Button("Beállítások megnyitása") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.vandaBodyStrong(13))
            .foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vandaCard(surface: cardSurface)
    }
}

#Preview {
    AlarmListView()
        .modelContainer(VandaStore.makeContainer())
}
