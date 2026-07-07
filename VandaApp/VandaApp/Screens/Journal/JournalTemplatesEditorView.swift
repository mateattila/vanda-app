//
//  JournalTemplatesEditorView.swift
//  VandaApp
//
//  Sablonok kezelése (spec 4.5: „a sablonok szerkeszthetők") — lista +
//  egyszerű kérdés-szerkesztő.
//

import SwiftUI
import SwiftData

struct JournalTemplatesEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \JournalTemplate.name) private var templates: [JournalTemplate]
    @Query private var themeSettings: [ThemeSettings]

    @State private var editorTemplate: JournalTemplate?

    private var theme: ThemeSettings? { themeSettings.first }
    private var accent: Color { theme?.accentColor ?? Theme.Accent.default }

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground(settings: theme)

                ScrollView {
                    VStack(spacing: Theme.Spacing.cardGap) {
                        ForEach(templates) { template in
                            templateRow(template)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                    .padding(.vertical, Theme.Spacing.cardGap)
                }
            }
            .navigationTitle("Sablonok")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kész") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        let template = JournalTemplate()
                        template.name = "Új sablon"
                        template.questions = [TemplateQuestion(text: "", kind: .chips, options: [])]
                        modelContext.insert(template)
                        editorTemplate = template
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editorTemplate) { template in
                TemplateQuestionsEditor(template: template, accent: accent)
            }
        }
    }

    private func templateRow(_ template: JournalTemplate) -> some View {
        HStack(spacing: Theme.Spacing.cardPadding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.vandaBodyStrong())
                    .foregroundStyle(Color.ink)
                Text("\(template.questions.count) kérdés")
                    .font(.vandaCaption())
                    .foregroundStyle(Color.inkMuted)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { template.isActive },
                set: { template.isActive = $0 }
            ))
            .labelsHidden()
            .tint(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vandaCard(surface: theme?.cardSurface ?? .surface)
        .contentShape(Rectangle())
        .onTapGesture { editorTemplate = template }
        .contextMenu {
            Button(role: .destructive) {
                modelContext.delete(template)
            } label: {
                Label("Törlés", systemImage: "trash")
            }
        }
    }
}

// MARK: - Kérdések szerkesztése

private struct TemplateQuestionsEditor: View {
    let template: JournalTemplate
    let accent: Color

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var questions: [TemplateQuestion] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.BackgroundGradient.default.gradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
                        TextField("A sablon neve", text: $name)
                            .font(.vandaBodyStrong(15))
                            .foregroundStyle(Color.ink)
                            .padding(14)
                            .background(Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous))

                        ForEach(questions.indices, id: \.self) { index in
                            questionCard(index)
                        }

                        Button {
                            questions.append(TemplateQuestion(text: "", kind: .chips, options: []))
                        } label: {
                            Label("Kérdés hozzáadása", systemImage: "plus")
                                .font(.vandaBodyStrong(13))
                                .foregroundStyle(accent)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                    .padding(.vertical, Theme.Spacing.cardGap)
                }
            }
            .navigationTitle("Sablon szerkesztése")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Mégse") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mentés") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = template.name
                questions = template.questions
            }
        }
    }

    private func questionCard(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Kérdés szövege", text: $questions[index].text)
                    .font(.vandaBody(15))
                    .foregroundStyle(Color.ink)
                if questions.count > 1 {
                    Button {
                        questions.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(Color.zoneRedStrong)
                    }
                    .buttonStyle(.plain)
                }
            }

            Picker("Típus", selection: $questions[index].kind) {
                Text("Chipek").tag(TemplateQuestion.Kind.chips)
                Text("Skála").tag(TemplateQuestion.Kind.scale)
                Text("Emoji").tag(TemplateQuestion.Kind.emoji)
            }
            .pickerStyle(.segmented)

            TextField(
                optionsPlaceholder(questions[index].kind),
                text: Binding(
                    get: { questions[index].options.joined(separator: ", ") },
                    set: { questions[index].options = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                )
            )
            .font(.vandaBody(13))
            .foregroundStyle(Color.inkMuted)

            if questions[index].kind == .chips {
                Toggle(isOn: $questions[index].allowsMultiple) {
                    Text("Több is választható")
                        .font(.vandaCaption())
                        .foregroundStyle(Color.inkMuted)
                }
                .tint(accent)
            }
        }
        .padding(14)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous))
        .softShadow()
    }

    private func optionsPlaceholder(_ kind: TemplateQuestion.Kind) -> String {
        switch kind {
        case .chips: "Opciók vesszővel: család, barátok, állatok"
        case .scale: "Végpontok vesszővel: laza, sűrű"
        case .emoji: "Emojik vesszővel: 😞, 🙁, 😐, 🙂, 😄"
        }
    }

    private func save() {
        template.name = name.trimmingCharacters(in: .whitespaces)
        template.questions = questions.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        dismiss()
    }
}
