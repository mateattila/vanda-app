//
//  JournalTemplateFillView.swift
//  VandaApp
//
//  Választós sablon kitöltése (design 05): lépés-progress, emoji-skála
//  (kiválasztott felnagyítva accent-körben), több-választós chipek, skála.
//  Egy kitöltés fél perc — nem kell mindig mindent újraírni.
//

import SwiftUI
import SwiftData

struct JournalTemplateFillView: View {
    let vault: JournalVault
    let template: JournalTemplate

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \JournalEntry.timestamp) private var entries: [JournalEntry]
    @Query(sort: \MoodEntry.timestamp) private var moodEntries: [MoodEntry]
    @Query private var themeSettings: [ThemeSettings]

    @State private var stepIndex = 0
    /// kérdés-index → kiválasztott opciók
    @State private var selections: [Int: Set<String>] = [:]
    @State private var freeText = ""

    private var theme: ThemeSettings? { themeSettings.first }
    private var accent: Color { theme?.accentColor ?? Theme.Accent.default }

    /// Az utolsó lépés a szabad szöveg (opcionális)
    private var totalSteps: Int { template.questions.count + 1 }
    private var isTextStep: Bool { stepIndex >= template.questions.count }

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground(settings: theme)

                VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
                    header

                    if isTextStep {
                        textStep
                    } else {
                        questionStep(template.questions[stepIndex], index: stepIndex)
                    }

                    Spacer()

                    controls
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.vertical, Theme.Spacing.cardGap)
            }
            .navigationTitle(template.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Mégse") { dismiss() }
                }
            }
        }
    }

    // MARK: - Fejléc + progress

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(stepIndex + 1) / \(totalSteps) · fél perc")
                .font(.vandaCaption())
                .foregroundStyle(Color.inkFaint)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.surfaceTint)
                    Capsule()
                        .fill(accent)
                        .frame(width: geo.size.width * Double(stepIndex + 1) / Double(totalSteps))
                        .animation(.snappy, value: stepIndex)
                }
            }
            .frame(height: 7)
        }
    }

    // MARK: - Kérdés-lépések

    private func questionStep(_ question: TemplateQuestion, index: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
            (Text(question.text)
                .font(.vandaDisplay(20))
                .foregroundStyle(Color.ink)
             + Text(question.allowsMultiple ? "  (többet is)" : "")
                .font(.vandaCaption())
                .foregroundStyle(Color.inkMuted))

            switch question.kind {
            case .emoji:
                emojiRow(question, index: index)
            case .chips:
                chipWall(question, index: index)
            case .scale:
                scaleRow(question, index: index)
            }
        }
        .padding(.top, Theme.Spacing.cardGap)
    }

    private func emojiRow(_ question: TemplateQuestion, index: Int) -> some View {
        HStack(spacing: 12) {
            ForEach(question.options, id: \.self) { emoji in
                let isSelected = selections[index]?.contains(emoji) == true
                Button {
                    selections[index] = [emoji]
                } label: {
                    Text(emoji)
                        .font(.system(size: isSelected ? 34 : 26))
                        .frame(width: isSelected ? 62 : 52, height: isSelected ? 62 : 52)
                        .background(isSelected ? accent : Color.surface, in: Circle())
                        .softShadow()
                }
                .buttonStyle(.plain)
                .animation(.snappy, value: isSelected)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func chipWall(_ question: TemplateQuestion, index: Int) -> some View {
        FlowChips(options: question.options, selected: selections[index] ?? []) { option in
            var current = selections[index] ?? []
            if question.allowsMultiple {
                if current.contains(option) { current.remove(option) } else { current.insert(option) }
            } else {
                current = [option]
            }
            selections[index] = current
        }
        .environment(\.vandaAccent, accent)
    }

    private func scaleRow(_ question: TemplateQuestion, index: Int) -> some View {
        let low = question.options.first ?? "1"
        let high = question.options.count > 1 ? question.options[1] : "5"
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { value in
                    let key = "\(value)"
                    let isSelected = selections[index]?.contains(key) == true
                    Button {
                        selections[index] = [key]
                    } label: {
                        Text(key)
                            .font(.vandaBodyStrong())
                            .foregroundStyle(isSelected ? .white : Color.inkMuted)
                            .frame(width: 46, height: 46)
                            .background(isSelected ? accent : Color.surface, in: Circle())
                            .softShadow()
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            HStack {
                Text(low)
                Spacer()
                Text(high)
            }
            .font(.vandaCaption())
            .foregroundStyle(Color.inkFaint)
        }
    }

    // MARK: - Szabad szöveg (opcionális)

    private var textStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
            Text("Ha akarsz, mondj hozzá pár szót")
                .font(.vandaDisplay(20))
                .foregroundStyle(Color.ink)
            Text("Ez is átugorható — a válaszaid már megvannak.")
                .font(.vandaCaption())
                .foregroundStyle(Color.inkMuted)

            TextEditor(text: $freeText)
                .font(.vandaBody(15))
                .foregroundStyle(Color.ink)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 140)
                .background(
                    theme?.cardSurface ?? .surface,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous)
                )
                .softShadow()
        }
        .padding(.top, Theme.Spacing.cardGap)
    }

    // MARK: - Léptetés + mentés

    private var controls: some View {
        HStack {
            if stepIndex > 0 {
                Button("← Vissza") {
                    withAnimation(.snappy) { stepIndex -= 1 }
                }
                .font(.vandaBodyStrong(13))
                .foregroundStyle(Color.inkMuted)
            }

            Spacer()

            Button {
                if isTextStep {
                    save()
                } else {
                    withAnimation(.snappy) { stepIndex += 1 }
                }
            } label: {
                Text(isTextStep ? "Mentés 💜" : "Tovább →")
                    .font(.vandaBodyStrong(14))
                    .foregroundStyle(.white)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 26)
                    .background(accent, in: Capsule())
                    .softShadow()
            }
            .buttonStyle(.plain)
        }
    }

    private func save() {
        var payload = JournalPayload()
        payload.text = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        payload.templateAnswers = template.questions.enumerated().compactMap { index, question in
            guard let selected = selections[index], !selected.isEmpty else { return nil }
            return JournalPayload.TemplateAnswer(question: question.text, answers: Array(selected).sorted())
        }
        if let mood = moodEntries.last(where: { Calendar.current.isDateInToday($0.timestamp) }) {
            payload.moodPercent = mood.batteryPercent
        }
        guard let entry = try? vault.seal(payload, previousEntry: entries.last) else { return }
        modelContext.insert(entry)
        dismiss()
    }
}

// MARK: - Chip-fal (sortörős)

private struct VandaAccentKey: EnvironmentKey {
    static let defaultValue: Color = Theme.Accent.default
}

extension EnvironmentValues {
    var vandaAccent: Color {
        get { self[VandaAccentKey.self] }
        set { self[VandaAccentKey.self] = newValue }
    }
}

struct FlowChips: View {
    let options: [String]
    let selected: Set<String>
    let onTap: (String) -> Void

    @Environment(\.vandaAccent) private var accent

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let isOn = selected.contains(option)
                Button {
                    onTap(option)
                } label: {
                    Text(option)
                        .font(.vandaBodyStrong(13))
                        .foregroundStyle(isOn ? .white : Color.ink)
                        .padding(.vertical, Theme.Spacing.chipVertical)
                        .padding(.horizontal, Theme.Spacing.chipHorizontal)
                        .background(isOn ? accent : Color.surface, in: Capsule())
                        .softShadow()
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Egyszerű balra zárt, sortörős elrendezés a chipekhez.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
