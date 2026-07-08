//
//  CalmActivitiesView.swift
//  VandaApp
//
//  A tevékenység-katalógus NYUGI-címkés elemei a panik-képernyőről
//  (spec 3. és 4.4: közös katalógus, a panikgomb a nyugi-eszközöket ajánlja).
//

import SwiftData
import SwiftUI

struct CalmActivitiesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var activities: [Activity]

    @State private var addedIDs: Set<UUID> = []

    private var calmActivities: [Activity] {
        activities.filter { $0.activityTags.contains(.calming) }
    }

    var body: some View {
        ZStack {
            Theme.Gradients.panic
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.cardGap) {
                ScrollView {
                    if calmActivities.isEmpty {
                        VStack(spacing: Theme.Spacing.cardGap) {
                            Text("🌿")
                                .font(.system(size: 52))
                                .padding(.top, 80)
                            Text("Még nincs nyugi-tevékenység")
                                .font(.vandaDisplay())
                                .foregroundStyle(.white)
                            Text("Az Unatkozom falon jelölj meg pár tevékenységet Nyugi címkével, és itt fognak várni.")
                                .font(.vandaBody())
                                .foregroundStyle(.white.opacity(0.75))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Theme.Spacing.screenMargin)
                        }
                    } else {
                        VStack(spacing: Theme.Spacing.cardGap) {
                            ForEach(calmActivities) { activity in
                                Button {
                                    accept(activity)
                                } label: {
                                    HStack(spacing: Theme.Spacing.cardPadding) {
                                        Text(activity.emoji)
                                            .font(.system(size: 28))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(activity.title)
                                                .font(.vandaBodyStrong())
                                                .foregroundStyle(.white)
                                            if !activity.metaLine.isEmpty {
                                                Text(activity.metaLine)
                                                    .font(.vandaCaption())
                                                    .foregroundStyle(.white.opacity(0.7))
                                            }
                                        }
                                        Spacer()
                                        Text(addedIDs.contains(activity.id) ? "Ma-listán ✓" : "Kipróbálom")
                                            .font(.vandaCaption())
                                            .foregroundStyle(.white.opacity(0.85))
                                    }
                                    .padding(Theme.Spacing.cardPadding)
                                    .background(
                                        Color.white.opacity(0.15),
                                        in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.screenMargin)
                        .padding(.top, Theme.Spacing.cardGap)
                    }
                }

                Button {
                    dismiss()
                } label: {
                    Text("Vissza")
                        .font(.vandaBodyStrong())
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Color.white,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.bottom, Theme.Spacing.screenMargin)
            }
        }
    }

    private func accept(_ activity: Activity) {
        guard !addedIDs.contains(activity.id) else { return }
        let task = DailyTask()
        task.title = "\(activity.emoji) \(activity.title)"
        task.source = .today
        modelContext.insert(task)
        withAnimation(.snappy) { _ = addedIDs.insert(activity.id) }
    }
}

#Preview {
    CalmActivitiesView()
        .modelContainer(for: Activity.self, inMemory: true)
}
