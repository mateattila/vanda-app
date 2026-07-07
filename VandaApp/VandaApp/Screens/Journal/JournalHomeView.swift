//
//  JournalHomeView.swift
//  VandaApp
//
//  A nyitott napló: felnyitás-banner (ha recovery-nyitás történt), hash-lánc
//  ellenőrzés, bejegyzés-lista és egyszerű szabad szöveges bejegyzés.
//  A választós sablonok, fotó-csatolás és aksi%-csatolás a fázis következő
//  lépésében jönnek.
//

import SwiftUI
import SwiftData

struct JournalHomeView: View {
    let vault: JournalVault

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JournalEntry.timestamp, order: .reverse) private var entries: [JournalEntry]
    @Query(sort: \JournalAuditEvent.timestamp) private var auditEvents: [JournalAuditEvent]
    @Query private var themeSettings: [ThemeSettings]

    @State private var isEditorPresented = false

    private var theme: ThemeSettings? { themeSettings.first }
    private var accent: Color { theme?.accentColor ?? Theme.Accent.default }
    private var cardSurface: Color { theme?.cardSurface ?? .surface }

    private var unacknowledged: [JournalAuditEvent] {
        auditEvents.filter { $0.acknowledgedAt == nil }
    }

    /// Hash-lánc ellenőrzés az időrendbe rakott bejegyzéseken.
    private var brokenChain: Bool {
        let ordered = entries.sorted { $0.timestamp < $1.timestamp }
        let blobs = ordered.compactMap(\.encryptedBlob)
        guard blobs.count == ordered.count else { return !ordered.isEmpty }
        return !JournalCrypto.verifyChain(
            blobs: blobs,
            previousHashes: ordered.map(\.previousEntryHash)
        ).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground(settings: theme)

                ScrollView {
                    VStack(spacing: Theme.Spacing.cardGap) {
                        if !unacknowledged.isEmpty {
                            auditBanner
                        }
                        if brokenChain {
                            chainWarning
                        }
                        if entries.isEmpty {
                            emptyState
                        }
                        ForEach(entries) { entry in
                            entryCard(entry)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                    .padding(.vertical, Theme.Spacing.cardGap)
                }
            }
            .navigationTitle("Napló")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isEditorPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Új bejegyzés")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        vault.lock()
                    } label: {
                        Image(systemName: "lock.fill")
                    }
                    .accessibilityLabel("Napló zárása")
                }
            }
            .sheet(isPresented: $isEditorPresented) {
                JournalEntryEditorView(vault: vault)
            }
        }
    }

    // MARK: - Bannerek

    private var auditBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🔓 A naplódat recovery-kulccsal nyitották meg")
                .font(.vandaBodyStrong())
                .foregroundStyle(Color.ink)
            ForEach(unacknowledged) { event in
                Text(event.timestamp.formatted(date: .long, time: .shortened))
                    .font(.vandaBody(13))
                    .foregroundStyle(Color.inkMuted)
            }
            Text("Ha nem te voltál, beszéljetek róla — pont ezért van a pecsét.")
                .font(.vandaCaption())
                .foregroundStyle(Color.inkMuted)
            Button("Láttam, értem") {
                for event in unacknowledged {
                    event.acknowledgedAt = Date()
                }
            }
            .font(.vandaBodyStrong(13))
            .foregroundStyle(Color.zoneRedStrong)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.cardPadding)
        .background(Color.zoneRed.opacity(0.35), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Color.zoneRedStrong.opacity(0.5))
        )
    }

    private var chainWarning: some View {
        Text("⚠️ A bejegyzés-lánc nem folytonos — lehet, hogy egy korábbi mentést állítottak vissza. Ha nem tudod mire vélni, beszéljetek róla.")
            .font(.vandaBody(13))
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.cardPadding)
            .background(Color.zoneOrange.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("📓")
                .font(.system(size: 44))
            Text("Üres még — és ez izgalmas!")
                .font(.vandaDisplay(20))
                .foregroundStyle(Color.ink)
            Text("A + gombbal írhatod az első bejegyzésed. Csak a tiéd marad.")
                .font(.vandaBody(13))
                .foregroundStyle(Color.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .vandaCard(surface: cardSurface)
    }

    // MARK: - Bejegyzések

    private func entryCard(_ entry: JournalEntry) -> some View {
        let payload = try? vault.open(entry)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .vandaLabelStyle()
                    .foregroundStyle(Color.inkFaint)
                Spacer()
                if let percent = payload?.moodPercent {
                    Text("🔋 \(percent)%")
                        .font(.vandaCaption(11))
                        .foregroundStyle(Color.inkMuted)
                }
            }
            Text(payload?.text ?? "— nem olvasható —")
                .font(.vandaBody())
                .foregroundStyle(Color.ink)
                .lineLimit(6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vandaCard(surface: cardSurface)
    }
}

// MARK: - Egyszerű bejegyzés-szerkesztő (v1: szabad szöveg + aksi%)

struct JournalEntryEditorView: View {
    let vault: JournalVault

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \JournalEntry.timestamp) private var entries: [JournalEntry]
    @Query(sort: \MoodEntry.timestamp) private var moodEntries: [MoodEntry]

    @State private var text = ""
    @State private var attachMood = false

    private var todayMood: MoodEntry? {
        moodEntries.last { Calendar.current.isDateInToday($0.timestamp) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.BackgroundGradient.default.gradient.ignoresSafeArea()

                VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
                    TextEditor(text: $text)
                        .font(.vandaBody(15))
                        .foregroundStyle(Color.ink)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 200)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous))

                    if let mood = todayMood {
                        Toggle(isOn: $attachMood) {
                            Text("Mai aksi hozzácsatolása (\(mood.batteryPercent)%)")
                                .font(.vandaBody())
                                .foregroundStyle(Color.ink)
                        }
                        .tint(Theme.Accent.default)
                        .padding(14)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous))
                    }

                    Spacer()
                }
                .padding(Theme.Spacing.screenMargin)
            }
            .navigationTitle("Új bejegyzés")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Mégse") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mentés") { save() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        var payload = JournalPayload()
        payload.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if attachMood, let mood = todayMood {
            payload.moodPercent = mood.batteryPercent
        }
        guard let entry = try? vault.seal(payload, previousEntry: entries.last) else { return }
        modelContext.insert(entry)
        dismiss()
    }
}
