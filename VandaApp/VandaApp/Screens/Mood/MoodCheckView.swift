//
//  MoodCheckView.swift
//  VandaApp
//
//  Hangulatbarométer-kitöltés (spec 4.3, design 02): függőleges aksi-mérő
//  (elem forma) → narancs/piros zónánál 2-3 töltő tevékenység ajánlása →
//  opcionális kérdés a forgó bankból (mindig átugorható). 5 másodperc az egész.
//

import SwiftUI
import SwiftData

struct MoodCheckView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var themeSettings: [ThemeSettings]
    @Query private var activities: [Activity]
    @Query private var questions: [Question]

    @State private var percent: Double = 60
    @State private var step: Step = .gauge
    @State private var suggestions: [Activity] = []
    @State private var question: Question?
    @State private var answerText = ""
    @State private var savedEntry: MoodEntry?

    private enum Step {
        case gauge, charge, question, done
    }

    private var theme: ThemeSettings? { themeSettings.first }
    private var accent: Color { theme?.accentColor ?? Theme.Accent.default }

    private var moodSettings: MoodSettings {
        MoodSettings.ensureCurrent(in: modelContext)
    }

    private var zone: MoodZone {
        moodSettings.zone(for: Int(percent))
    }

    var body: some View {
        ZStack {
            ThemedBackground(settings: theme)

            switch step {
            case .gauge: gaugeStep
            case .charge: chargeStep
            case .question: questionStep
            case .done: doneStep
            }
        }
    }

    // MARK: - 1. lépés: mérő

    private var gaugeStep: some View {
        VStack(spacing: Theme.Spacing.cardGap) {
            VStack(spacing: 4) {
                Text("Hogy állsz most?")
                    .font(.vandaDisplay())
                    .foregroundStyle(Color.ink)
                Text("Húzd oda, ahol érzed magad.")
                    .font(.vandaBody(13))
                    .foregroundStyle(Color.inkMuted)
            }
            .padding(.top, Theme.Spacing.screenMargin)

            BatteryGauge(percent: $percent, zone: zone)
                .frame(maxHeight: .infinity)

            HStack(spacing: 10) {
                ForEach([MoodZone.green, .orange, .red], id: \.rawValue) { z in
                    VStack(spacing: 1) {
                        Text(z.name)
                            .font(.vandaBodyStrong(13))
                        Text(z.label)
                            .font(.vandaCaption(10))
                    }
                    .foregroundStyle(zone == z ? .white : z.strongColor)
                    .padding(.vertical, Theme.Spacing.chipVertical)
                    .padding(.horizontal, Theme.Spacing.chipHorizontal)
                    .background(zone == z ? z.strongColor : Color.surfaceTint, in: Capsule())
                    .animation(.snappy, value: zone)
                }
            }

            Button(action: saveEntry) {
                Text("Ennyin vagyok")
                    .font(.vandaBodyStrong(15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.ink, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    .softShadow()
            }
            .buttonStyle(.plain)
            .padding(.bottom, Theme.Spacing.screenMargin)
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
    }

    // MARK: - 2. lépés: töltő ajánlás (narancs/piros zónában)

    private var chargeStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
            Spacer()

            Text("Egy kis töltő")
                .vandaLabelStyle()
                .foregroundStyle(Color.inkFaint)
            Text("Mit szólnál ehhez, mielőtt tovább merülnél?")
                .font(.vandaDisplay(20))
                .foregroundStyle(Color.ink)

            ForEach(suggestions) { activity in
                Button {
                    accept(activity)
                } label: {
                    HStack(spacing: 10) {
                        Text(activity.emoji)
                            .font(.system(size: 22))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.title)
                                .font(.vandaBodyStrong())
                                .foregroundStyle(Color.ink)
                                .multilineTextAlignment(.leading)
                            if !activity.metaLine.isEmpty {
                                Text(activity.metaLine)
                                    .font(.vandaCaption(11))
                                    .foregroundStyle(Color.inkFaint)
                            }
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .vandaCard(surface: theme?.cardSurface ?? .surface)
                }
                .buttonStyle(.plain)
            }

            Button("Most nem — és ez is oké 🫶") {
                advanceToQuestion()
            }
            .font(.vandaBodyStrong(13))
            .foregroundStyle(Color.inkMuted)
            .frame(maxWidth: .infinity)

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
    }

    // MARK: - 3. lépés: kérdés a bankból

    private var questionStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
            Spacer()

            Text("Ha van kedved…")
                .vandaLabelStyle()
                .foregroundStyle(Color.inkFaint)
            Text(question?.text ?? "")
                .font(.vandaDisplay(21))
                .foregroundStyle(Color.ink)

            TextField("Írd ide, ha szeretnéd…", text: $answerText, axis: .vertical)
                .font(.vandaBody(15))
                .foregroundStyle(Color.ink)
                .lineLimit(3...6)
                .padding(14)
                .background(
                    theme?.cardSurface ?? .surface,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous)
                )
                .softShadow()

            HStack(spacing: Theme.Spacing.cardGap) {
                Button("Átugrom") {
                    finish()
                }
                .font(.vandaBodyStrong(13))
                .foregroundStyle(Color.inkMuted)

                Spacer()

                Button {
                    saveAnswer()
                } label: {
                    Text("Mentem 💜")
                        .font(.vandaBodyStrong(14))
                        .foregroundStyle(.white)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 22)
                        .background(accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
    }

    // MARK: - 4. lépés: lezárás

    private var doneStep: some View {
        VStack(spacing: 10) {
            Text("💜")
                .font(.system(size: 48))
            Text("Kösz, hogy ránéztél magadra!")
                .font(.vandaDisplay(20))
                .foregroundStyle(Color.ink)
        }
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            dismiss()
        }
    }

    // MARK: - Folyamat

    private func saveEntry() {
        let entry = MoodEntry()
        entry.batteryPercent = Int(percent)
        entry.zone = zone
        modelContext.insert(entry)
        savedEntry = entry

        if zone != .green {
            suggestions = Array(
                activities
                    .filter { $0.activityTags.contains(.charging) }
                    .shuffled()
                    .prefix(3)
            )
            if !suggestions.isEmpty {
                withAnimation(.snappy) { step = .charge }
                return
            }
        }
        advanceToQuestion()
    }

    private func accept(_ activity: Activity) {
        let task = DailyTask()
        task.title = "\(activity.emoji) \(activity.title)"
        task.source = .today
        modelContext.insert(task)
        advanceToQuestion()
    }

    private func advanceToQuestion() {
        let settings = moodSettings
        guard settings.questionsEnabled else {
            finish()
            return
        }
        question = questions
            .filter { $0.isActive && $0.level <= settings.questionMaxLevel }
            .randomElement()
        guard question != nil else {
            finish()
            return
        }
        withAnimation(.snappy) { step = .question }
    }

    private func saveAnswer() {
        let text = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let question, !text.isEmpty {
            savedEntry?.answers.append(MoodAnswer(question: question.text, answer: text))
        }
        finish()
    }

    private func finish() {
        withAnimation(.snappy) { step = .done }
    }
}

// MARK: - Függőleges elem-mérő

private struct BatteryGauge: View {
    @Binding var percent: Double
    let zone: MoodZone

    var body: some View {
        VStack(spacing: 5) {
            // terminál a tetején
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.ink)
                .frame(width: 44, height: 12)

            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.surface)

                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(zone.fillColor)
                        .frame(height: max(28, geo.size.height * percent / 100))
                        .padding(7)
                        .animation(.snappy, value: zone)

                    Text("\(Int(percent))%")
                        .font(.vandaBigNumber(40))
                        .foregroundStyle(percent > 35 ? .white : Color.ink)
                        .frame(maxHeight: .infinity)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.ink, lineWidth: 3.5)
                )
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let raw = 100 * (1 - value.location.y / geo.size.height)
                            percent = min(100, max(0, raw))
                        }
                )
            }
            .frame(width: 170)
        }
        .accessibilityElement()
        .accessibilityLabel("Aksi-mérő")
        .accessibilityValue("\(Int(percent)) százalék")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: percent = min(100, percent + 5)
            case .decrement: percent = max(0, percent - 5)
            @unknown default: break
            }
        }
    }
}

#Preview {
    MoodCheckView()
        .modelContainer(VandaStore.makeContainer())
}
