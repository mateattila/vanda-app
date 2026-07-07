//
//  RemindersListView.swift
//  VandaApp
//
//  Emlékeztetők kezelése (spec 4.2) — a Ma fülről nyílik. Gyári + saját egy
//  rendszerben: a gyáriak ki-be kapcsolhatók és átírhatók, a sajátok
//  törölhetők is.
//

import SwiftUI
import SwiftData

struct RemindersListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Reminder.createdAt) private var reminders: [Reminder]
    @Query private var themeSettings: [ThemeSettings]

    @State private var editorReminder: Reminder?
    @State private var isCreatingNew = false
    @State private var notificationsDenied = false

    private var theme: ThemeSettings? { themeSettings.first }
    private var accent: Color { theme?.accentColor ?? Theme.Accent.default }
    private var cardSurface: Color { theme?.cardSurface ?? .surface }

    var body: some View {
        ZStack {
            ThemedBackground(settings: theme)

            ScrollView {
                VStack(spacing: Theme.Spacing.cardGap) {
                    if notificationsDenied {
                        deniedBanner
                    }
                    ForEach(reminders) { reminder in
                        reminderRow(reminder)
                    }
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.vertical, Theme.Spacing.cardGap)
            }
        }
        .navigationTitle("Emlékeztetők")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCreatingNew = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Új emlékeztető")
            }
        }
        .sheet(item: $editorReminder) { reminder in
            ReminderEditorView(reminder: reminder, accent: accent)
        }
        .sheet(isPresented: $isCreatingNew) {
            ReminderEditorView(reminder: nil, accent: accent)
        }
        .task {
            ReminderSeeder.seedFactoryPackIfNeeded(in: modelContext)
            notificationsDenied = !(await ReminderScheduler.shared.ensureAuthorization())
            await ReminderScheduler.shared.resyncFromStore()
        }
    }

    private func reminderRow(_ reminder: Reminder) -> some View {
        HStack(spacing: Theme.Spacing.cardPadding) {
            Text(reminder.symbolOrEmoji)
                .font(.system(size: 20))
                .frame(width: 40, height: 40)
                .background(
                    Color(hex: UInt32(clamping: reminder.colorHex)).opacity(0.22),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.iconContainer, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .font(.vandaBodyStrong())
                    .foregroundStyle(Color.ink)
                Text(reminder.text)
                    .font(.vandaCaption())
                    .foregroundStyle(Color.inkMuted)
                    .lineLimit(1)
                Text(reminder.schedule.summary)
                    .font(.vandaCaption(11))
                    .foregroundStyle(Color.inkFaint)
            }

            Spacer()

            Toggle("", isOn: activeBinding(reminder))
                .labelsHidden()
                .tint(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vandaCard(surface: cardSurface)
        .opacity(reminder.isActive ? 1 : 0.6)
        .contentShape(Rectangle())
        .onTapGesture { editorReminder = reminder }
        .contextMenu {
            Button {
                editorReminder = reminder
            } label: {
                Label("Szerkesztés", systemImage: "pencil")
            }
            if reminder.source == .custom {
                Button(role: .destructive) {
                    modelContext.delete(reminder)
                    Task { await ReminderScheduler.shared.resyncFromStore() }
                } label: {
                    Label("Törlés", systemImage: "trash")
                }
            }
        }
    }

    private func activeBinding(_ reminder: Reminder) -> Binding<Bool> {
        Binding(
            get: { reminder.isActive },
            set: { newValue in
                reminder.isActive = newValue
                Task { await ReminderScheduler.shared.resyncFromStore() }
            }
        )
    }

    private var deniedBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("🔕 Az értesítések ki vannak kapcsolva")
                .font(.vandaBodyStrong())
                .foregroundStyle(Color.ink)
            Text("Így az emlékeztetők nem tudnak szólni. A rendszer-Beállításokban tudod visszakapcsolni.")
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
    NavigationStack {
        RemindersListView()
    }
    .modelContainer(VandaStore.makeContainer())
}
