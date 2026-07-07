//
//  TodayView.swift
//  VandaApp
//
//  A Ma képernyő — az induló fül. Fejlécében a kiemelt, lüktető Panik gomb
//  (app-nyitásból 1 érintésre) és a fogaskerék a Beállításokhoz.
//  Napi progress fal (spec 4.6): emlékeztető-pipák + saját teendők + töltődő
//  aksi vizuál. Éjfélkor tiszta lap; nincs streak, nincs múlt-nézet, a hangnem
//  30%-nál is kedves.
//

import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var themeSettings: [ThemeSettings]
    @Query(sort: \Reminder.createdAt) private var reminders: [Reminder]
    @Query(sort: \DailyTask.date) private var allTasks: [DailyTask]
    @Query private var allLogs: [ReminderLog]
    @Query(sort: \MoodEntry.timestamp) private var moodEntries: [MoodEntry]

    @State private var isPanicPresented = false
    @State private var isMoodCheckPresented = false
    @State private var newTaskTitle = ""

    /// A nagy szám skálázásához nem-szöveg méret is tartozik (akku-csík) —
    /// Dynamic Type-pal együtt nő.
    @ScaledMetric(relativeTo: .largeTitle) private var batteryBarHeight: CGFloat = 26

    private var theme: ThemeSettings? { themeSettings.first }
    private var accent: Color { theme?.accentColor ?? Theme.Accent.default }
    private var cardSurface: Color { theme?.cardSurface ?? .surface }

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground(settings: theme)

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
                        header
                        chargeCard
                        barometerCard
                        wallCard
                        remindersCard
                        boredomCard
                    }
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                    .padding(.bottom, Theme.Spacing.screenMargin)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $isPanicPresented) {
                PanicPlaceholderView()
            }
            .sheet(isPresented: $isMoodCheckPresented) {
                MoodCheckView()
            }
        }
    }

    // MARK: - Mai adatok

    private struct ReminderWallItem: Identifiable {
        let reminder: Reminder
        let total: Int
        let done: Int
        var id: UUID { reminder.id }
        var isComplete: Bool { done >= total }
    }

    private var todayLogs: [ReminderLog] {
        allLogs.filter { Calendar.current.isDateInToday($0.date) && $0.status == .done }
    }

    private var reminderItems: [ReminderWallItem] {
        let logCounts = Dictionary(grouping: todayLogs.compactMap(\.reminderID)) { $0 }
            .mapValues(\.count)
        return reminders.compactMap { reminder in
            let total = reminder.occurrences(on: Date())
            guard total > 0 else { return nil }
            let done = min(logCounts[reminder.id] ?? 0, total)
            return ReminderWallItem(reminder: reminder, total: total, done: done)
        }
    }

    private var todayTasks: [DailyTask] {
        allTasks.filter { Calendar.current.isDateInToday($0.date) }
    }

    /// A nap töltöttsége: kész egységek / összes egység (emlékeztető-előfordulások + teendők)
    private var progress: (done: Int, total: Int) {
        let reminderTotal = reminderItems.reduce(0) { $0 + $1.total }
        let reminderDone = reminderItems.reduce(0) { $0 + $1.done }
        let taskTotal = todayTasks.count
        let taskDone = todayTasks.filter(\.isDone).count
        return (reminderDone + taskDone, reminderTotal + taskTotal)
    }

    private var percent: Int {
        let p = progress
        guard p.total > 0 else { return 0 }
        return Int((Double(p.done) / Double(p.total) * 100).rounded())
    }

    /// Mindig kedves, sosem számonkérő (spec 4.6 + alapelvek). A megfogalmazás
    /// szándékosan a NAPRÓL szól („a napod"), nem Vandáról — az ő aksija a
    /// hangulatbarométer (2. fázis), a kettő rímel, de nem keverendő.
    private var kindMessage: String {
        guard progress.total > 0 else { return "Tiszta lap — kezdd azzal, ami jólesik ✨" }
        switch percent {
        case 0: return "Nyugis kezdés, minden oké 🫶"
        case ..<34: return "Nyugis nap, ez is oké 🫶"
        case ..<67: return "A napod szépen halad 🌱"
        case ..<100: return "A napod szép ívben töltődik 🐨"
        default: return "Minden megvolt mára — ez igen! 🎉"
        }
    }

    // MARK: - Fejléc

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.cardGap) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Szia, Vanda 🌙")
                    .font(.vandaDisplay(25))
                    .foregroundStyle(Color.ink)
                Text(formattedToday)
                    .font(.vandaBodyStrong(13))
                    .foregroundStyle(accent)
            }

            Spacer()

            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.inkMuted)
                    .frame(width: 38, height: 38)
                    .background(cardSurface, in: Circle())
                    .softShadow()
            }
            .padding(.top, 4)

            PanicButton(accent: accent) {
                isPanicPresented = true
            }
        }
        .padding(.top, 8)
    }

    private var formattedToday: String {
        let now = Date.now
        let weekday = now.formatted(.dateTime.weekday(.wide)).capitalized
        let monthDay = now.formatted(.dateTime.month(.abbreviated).day())
        return "\(weekday) · \(monthDay)"
    }

    // MARK: - Töltöttség-kártya

    private var chargeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A napod")
                .vandaLabelStyle()
                .foregroundStyle(Color.inkFaint)

            HStack(alignment: .center, spacing: Theme.Spacing.cardPadding) {
                (Text("\(percent)").font(.vandaBigNumber())
                 + Text(" %").font(.vandaDisplay(20)))
                    .foregroundStyle(Color.ink)

                batteryBar
            }

            Text(kindMessage)
                .font(.vandaBody())
                .foregroundStyle(Color.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vandaCard(surface: cardSurface)
    }

    /// Kirajzolt elem-akku csík: sín + accent kitöltés + terminál-pötty a végén
    private var batteryBar: some View {
        HStack(spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: batteryBarHeight / 3, style: .continuous)
                        .fill(Color.surfaceTint)
                    RoundedRectangle(cornerRadius: batteryBarHeight / 3, style: .continuous)
                        .fill(accent)
                        .frame(width: max(batteryBarHeight / 3, geo.size.width * Double(percent) / 100))
                        .animation(.snappy, value: percent)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: batteryBarHeight / 3, style: .continuous)
                        .strokeBorder(Color.hairline)
                )
            }
            .frame(height: batteryBarHeight)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.inkFaint)
                .frame(width: 3.5, height: batteryBarHeight * 0.4)
        }
    }

    // MARK: - Barométer mini

    private var todayMood: MoodEntry? {
        moodEntries.last { Calendar.current.isDateInToday($0.timestamp) }
    }

    private var barometerCard: some View {
        HStack(spacing: Theme.Spacing.cardPadding) {
            Button {
                isMoodCheckPresented = true
            } label: {
                HStack(spacing: Theme.Spacing.cardPadding) {
                    Text("🔋")
                        .font(.system(size: 20))
                        .frame(width: 40, height: 40)
                        .background(
                            Color.surfaceTint,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.iconContainer, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hangulatbarométer")
                            .font(.vandaBodyStrong())
                            .foregroundStyle(Color.ink)
                        if let mood = todayMood {
                            Text("\(mood.zone.name) zóna · \(mood.batteryPercent)%")
                                .font(.vandaCaption())
                                .foregroundStyle(mood.zone.strongColor)
                        } else {
                            Text("Hány százalékos az aksid?")
                                .font(.vandaCaption())
                                .foregroundStyle(Color.inkMuted)
                        }
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            NavigationLink {
                MoodTrendView()
            } label: {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.inkMuted)
                    .frame(width: 32, height: 32)
                    .background(Color.surfaceTint, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Aksi-trend")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vandaCard(surface: cardSurface)
    }

    // MARK: - Mai nap fal

    private var wallCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mai nap")
                .vandaLabelStyle()
                .foregroundStyle(Color.inkFaint)

            ForEach(reminderItems) { item in
                reminderRow(item)
            }

            ForEach(todayTasks) { task in
                taskRow(task)
            }

            if reminderItems.isEmpty && todayTasks.isEmpty {
                Text("Ma még üres a fal — írj be valamit, vagy pörgess az Unatkozom fülön 🎲")
                    .font(.vandaBody(13))
                    .foregroundStyle(Color.inkMuted)
            }

            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent)
                TextField("Írj be egy mai teendőt…", text: $newTaskTitle)
                    .font(.vandaBody())
                    .foregroundStyle(Color.ink)
                    .onSubmit(addTask)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vandaCard(surface: cardSurface)
    }

    private func reminderRow(_ item: ReminderWallItem) -> some View {
        Button {
            toggleReminder(item)
        } label: {
            HStack(spacing: 10) {
                Text(item.reminder.symbolOrEmoji)
                    .font(.system(size: 17))
                Text(item.reminder.title)
                    .font(.vandaBody())
                    .foregroundStyle(item.isComplete ? Color.inkMuted : Color.ink)
                    .strikethrough(item.isComplete, color: .inkMuted)
                if item.total > 1 {
                    Text("\(item.done)/\(item.total)")
                        .font(.vandaCaption(11))
                        .foregroundStyle(Color.inkFaint)
                }
                Spacer()
                checkCircle(done: item.isComplete)
            }
        }
        .buttonStyle(.plain)
    }

    private func taskRow(_ task: DailyTask) -> some View {
        Button {
            task.isDone.toggle()
        } label: {
            HStack(spacing: 10) {
                Text(task.title)
                    .font(.vandaBody())
                    .foregroundStyle(task.isDone ? Color.inkMuted : Color.ink)
                    .strikethrough(task.isDone, color: .inkMuted)
                Spacer()
                checkCircle(done: task.isDone)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                modelContext.delete(task)
            } label: {
                Label("Törlés", systemImage: "trash")
            }
        }
    }

    private func checkCircle(done: Bool) -> some View {
        ZStack {
            Circle()
                .fill(done ? accent : Color.surfaceTint)
                .frame(width: 24, height: 24)
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    private func toggleReminder(_ item: ReminderWallItem) {
        if item.done < item.total {
            let log = ReminderLog()
            log.reminderID = item.reminder.id
            log.status = .done
            modelContext.insert(log)
        } else {
            // teljesen kipipált → visszavonás: a mai logok törlése
            for log in todayLogs where log.reminderID == item.reminder.id {
                modelContext.delete(log)
            }
        }
    }

    private func addTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let task = DailyTask()
        task.title = title
        task.source = .today
        modelContext.insert(task)
        newTaskTitle = ""
    }

    // MARK: - Belépő kártyák

    private var remindersCard: some View {
        NavigationLink {
            RemindersListView()
        } label: {
            HStack(spacing: Theme.Spacing.cardPadding) {
                Text("🔔")
                    .font(.system(size: 20))
                    .frame(width: 40, height: 40)
                    .background(
                        Color.surfaceTint,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.iconContainer, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Emlékeztetők")
                        .font(.vandaBodyStrong())
                        .foregroundStyle(Color.ink)
                    Text("Kedves noszogatások — a te szavaiddal")
                        .font(.vandaCaption())
                        .foregroundStyle(Color.inkMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.inkFaint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .vandaCard(surface: cardSurface)
        }
        .buttonStyle(.plain)
    }

    private var boredomCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Unatkozol?")
                    .font(.vandaDisplay(20))
                    .foregroundStyle(.white)
                Text("Ugorj az Unatkozom fülre egy ötletért 👀")
                    .font(.vandaBody(13))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.cardPadding)
        .background(accent, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .softShadow()
    }
}

#Preview {
    TodayView()
        .modelContainer(VandaStore.makeContainer())
}
