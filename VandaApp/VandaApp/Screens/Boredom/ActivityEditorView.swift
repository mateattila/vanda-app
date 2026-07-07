//
//  ActivityEditorView.swift
//  VandaApp
//
//  Tevékenység-kártya felvétele / szerkesztése (spec 4.7): cím, emoji, címkék.
//  A Töltő/Nyugi címkék is itt állíthatók — ezeket a barométer- és
//  panik-ajánlók használják majd.
//

import SwiftUI
import SwiftData

struct ActivityEditorView: View {
    /// nil = új kártya készül
    let activity: Activity?
    let accent: Color

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var emoji: String = "✨"
    @State private var tags: Set<ActivityTag> = []

    private var isNew: Bool { activity == nil }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.BackgroundGradient.default.gradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
                        sectionLabel("Mi legyen?")
                        HStack(spacing: 10) {
                            TextField("✨", text: $emoji)
                                .font(.system(size: 24))
                                .multilineTextAlignment(.center)
                                .frame(width: 54, height: 54)
                                .background(
                                    Color.surface,
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.iconContainer, style: .continuous)
                                )
                                .onChange(of: emoji) { _, newValue in
                                    // csak az első karakter (emoji) marad
                                    if let first = newValue.first { emoji = String(first) }
                                }

                            TextField("pl. Építs párnavárat", text: $title, axis: .vertical)
                                .font(.vandaBody(15))
                                .foregroundStyle(Color.ink)
                                .padding(14)
                                .background(
                                    Color.surface,
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous)
                                )
                        }

                        sectionLabel("Címkék")
                        tagSection("Hol?", tags: ActivityTag.placeTags)
                        tagSection("Kivel?", tags: ActivityTag.companyTags)
                        tagSection("Mennyi idő?", tags: ActivityTag.timeTags)
                        tagSection("Milyen fajta?", tags: ActivityTag.moodTags)
                    }
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                    .padding(.vertical, Theme.Spacing.cardGap)
                }
            }
            .navigationTitle(isNew ? "Új ötlet" : "Szerkesztés")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Mégse") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mentés") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.medium, .large])
    }

    private func load() {
        guard let activity else { return }
        title = activity.title
        emoji = activity.emoji
        tags = Set(activity.activityTags)
    }

    private func save() {
        let target = activity ?? Activity()
        target.title = title.trimmingCharacters(in: .whitespaces)
        target.emoji = emoji.isEmpty ? "✨" : emoji
        target.activityTags = Array(tags)
        if isNew {
            target.source = .custom
            modelContext.insert(target)
        }
        dismiss()
    }

    private func tagSection(_ label: String, tags groupTags: [ActivityTag]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.vandaCaption())
                .foregroundStyle(Color.inkMuted)
            HStack(spacing: 8) {
                ForEach(groupTags, id: \.rawValue) { tag in
                    let isOn = tags.contains(tag)
                    Button {
                        if isOn { tags.remove(tag) } else { tags.insert(tag) }
                    } label: {
                        Text(tag.displayName)
                            .font(.vandaBodyStrong(13))
                            .foregroundStyle(isOn ? .white : Color.inkMuted)
                            .padding(.vertical, Theme.Spacing.chipVertical)
                            .padding(.horizontal, Theme.Spacing.chipHorizontal)
                            .background(isOn ? accent : Color.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .vandaLabelStyle()
            .foregroundStyle(Color.inkFaint)
    }
}

#Preview {
    ActivityEditorView(activity: nil, accent: Theme.Accent.default)
        .modelContainer(VandaStore.makeContainer())
}
