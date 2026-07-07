//
//  BoredomView.swift
//  VandaApp
//
//  Unatkozó lista (spec 4.7): kártyafal a tevékenység-katalógusból + „Pörgess
//  egyet!", mert unatkozva a választás maga is teher. Szűrés címkékre; elfogadott
//  ötlet felkerülhet a napi falra (DailyTask).
//

import SwiftUI
import SwiftData

struct BoredomView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Activity.createdAt) private var activities: [Activity]
    @Query private var themeSettings: [ThemeSettings]

    @State private var selectedTags: Set<ActivityTag> = []
    @State private var featuredID: UUID?
    @State private var editorActivity: Activity?
    @State private var isCreatingNew = false
    @State private var spinCount = 0
    @State private var addedToastVisible = false

    private var theme: ThemeSettings? { themeSettings.first }
    private var accent: Color { theme?.accentColor ?? Theme.Accent.default }
    private var cardSurface: Color { theme?.cardSurface ?? .surface }

    private var filtered: [Activity] {
        activities.filter { $0.matches(filter: selectedTags) }
    }

    private var featured: Activity? {
        filtered.first { $0.id == featuredID } ?? filtered.first
    }

    private var wallActivities: [Activity] {
        filtered.filter { $0.id != featured?.id }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground(settings: theme)

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
                        header
                        filterChips
                        if let featured {
                            FeaturedActivityCard(
                                activity: featured,
                                accent: accent,
                                onAccept: { addToDailyWall(featured) }
                            )
                            .id(featured.id)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
                        } else {
                            emptyState
                        }
                        cardWall
                    }
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                    .padding(.bottom, 90)
                }

                spinButton
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editorActivity) { activity in
                ActivityEditorView(activity: activity, accent: accent)
            }
            .sheet(isPresented: $isCreatingNew) {
                ActivityEditorView(activity: nil, accent: accent)
            }
            .overlay(alignment: .bottom) {
                if addedToastVisible {
                    toast
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: spinCount)
            .task {
                ActivitySeeder.seedFactoryPackIfNeeded(in: modelContext)
            }
        }
    }

    // MARK: - Fejléc + szűrők

    private var header: some View {
        HStack(alignment: .center) {
            Text("Unatkozol? 🎲")
                .font(.vandaDisplay(25))
                .foregroundStyle(Color.ink)

            Spacer()

            Button {
                isCreatingNew = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 38, height: 38)
                    .background(cardSurface, in: Circle())
                    .softShadow()
            }
            .accessibilityLabel("Új ötlet felvétele")
        }
        .padding(.top, 8)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActivityTag.filterGroups, id: \.first?.rawValue) { group in
                    ForEach(group, id: \.rawValue) { tag in
                        filterChip(tag)
                    }
                    if group.first != ActivityTag.filterGroups.last?.first {
                        Rectangle()
                            .fill(Color.hairline)
                            .frame(width: 1, height: 18)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
    }

    private func filterChip(_ tag: ActivityTag) -> some View {
        let isOn = selectedTags.contains(tag)
        return Button {
            withAnimation(.snappy) {
                if isOn { selectedTags.remove(tag) } else { selectedTags.insert(tag) }
            }
        } label: {
            Text(tag.displayName)
                .font(.vandaBodyStrong(13))
                .foregroundStyle(isOn ? .white : Color.inkMuted)
                .padding(.vertical, Theme.Spacing.chipVertical)
                .padding(.horizontal, Theme.Spacing.chipHorizontal)
                .background(isOn ? accent : Color.surfaceTint, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Kártyafal

    private var cardWall: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Theme.Spacing.cardGap), GridItem(.flexible())],
            spacing: Theme.Spacing.cardGap
        ) {
            ForEach(wallActivities) { activity in
                ActivityWallCard(activity: activity, surface: cardSurface)
                    .onTapGesture {
                        withAnimation(.snappy) { featuredID = activity.id }
                    }
                    .contextMenu {
                        Button {
                            editorActivity = activity
                        } label: {
                            Label("Szerkesztés", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            withAnimation(.snappy) { modelContext.delete(activity) }
                        } label: {
                            Label("Törlés", systemImage: "trash")
                        }
                    }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("🫥")
                .font(.system(size: 40))
            Text("Erre a szűrésre most nincs ötlet")
                .font(.vandaBodyStrong())
                .foregroundStyle(Color.ink)
            Text("Kapcsolj ki egy-két szűrőt, vagy vegyél fel újat a + gombbal!")
                .font(.vandaBody(13))
                .foregroundStyle(Color.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .vandaCard(surface: cardSurface)
    }

    // MARK: - Pörgetés

    private var spinButton: some View {
        VStack {
            Spacer()
            Button(action: spin) {
                Text("🎲 Pörgess egyet!")
                    .font(.vandaBodyStrong(15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        Color.ink,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    )
                    .softShadow()
            }
            .buttonStyle(.plain)
            .disabled(filtered.count < 2)
            .opacity(filtered.count < 2 ? 0.5 : 1)
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.bottom, 8)
        }
    }

    private func spin() {
        let candidates = filtered.filter { $0.id != featured?.id }
        guard let next = candidates.randomElement() else { return }
        spinCount += 1
        withAnimation(reduceMotion ? .none : .spring(duration: 0.45, bounce: 0.35)) {
            featuredID = next.id
        }
    }

    // MARK: - Napi falra

    private func addToDailyWall(_ activity: Activity) {
        let task = DailyTask()
        task.title = "\(activity.emoji) \(activity.title)"
        task.source = .today
        modelContext.insert(task)

        withAnimation(.snappy) { addedToastVisible = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.snappy) { addedToastVisible = false }
        }
    }

    private var toast: some View {
        Text("Felkerült a mai listádra! 🎉")
            .font(.vandaBodyStrong(13))
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 18)
            .background(Color.ink, in: Capsule())
            .softShadow()
            .padding(.bottom, 70)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Kiemelt kártya („Neked most")

private struct FeaturedActivityCard: View {
    let activity: Activity
    let accent: Color
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Neked most")
                .vandaLabelStyle()
                .foregroundStyle(.white.opacity(0.8))

            Text("\(activity.emoji) \(activity.title)")
                .font(.vandaDisplay(21))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)

            if !activity.metaLine.isEmpty {
                Text(activity.metaLine)
                    .font(.vandaBodyStrong(12))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Button(action: onAccept) {
                Text("Ma megcsinálom ✓")
                    .font(.vandaBodyStrong(13))
                    .foregroundStyle(Color.ink)
                    .padding(.vertical, Theme.Spacing.chipVertical)
                    .padding(.horizontal, Theme.Spacing.chipHorizontal)
                    .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.cardPadding)
        .background(accent, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .softShadow()
    }
}

// MARK: - Fal-kártya

private struct ActivityWallCard: View {
    let activity: Activity
    let surface: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(activity.emoji)
                .font(.system(size: 26))
            Text(activity.title)
                .font(.vandaBodyStrong())
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
            if !activity.metaLine.isEmpty {
                Text(activity.metaLine)
                    .font(.vandaCaption(11))
                    .foregroundStyle(Color.inkFaint)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .padding(Theme.Spacing.cardPadding)
        .background(surface, in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous))
        .softShadow()
    }
}

#Preview {
    BoredomView()
        .modelContainer(VandaStore.makeContainer())
}
