//
//  BreathingView.swift
//  VandaApp
//
//  Táguló-szűkülő körrel vezetett légzés. A kör animációja itt funkció,
//  nem dísz — Reduce Motion mellett is fut, mert maga a gyakorlat.
//

import SwiftUI

struct BreathingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pattern: BreathingPattern = .box
    @State private var startDate = Date()

    var body: some View {
        ZStack {
            Theme.Gradients.panic
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.cardGap) {
                HStack(spacing: Theme.Spacing.chipHorizontal / 2) {
                    ForEach(BreathingPattern.allCases) { candidate in
                        Button {
                            pattern = candidate
                            startDate = Date()
                        } label: {
                            Text(candidate.displayName)
                                .font(.vandaBodyStrong())
                                .foregroundStyle(pattern == candidate ? Color.ink : .white)
                                .padding(.vertical, Theme.Spacing.chipVertical)
                                .padding(.horizontal, Theme.Spacing.chipHorizontal)
                                .background(
                                    pattern == candidate ? Color.white : Color.white.opacity(0.15),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, Theme.Spacing.cardGap)

                Spacer()

                TimelineView(.animation) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(startDate)
                    let current = pattern.phase(at: elapsed)

                    VStack(spacing: 30) {
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.15))
                                .frame(width: 250, height: 250)
                            Circle()
                                .fill(.white.opacity(0.9))
                                .frame(width: 210, height: 210)
                                .scaleEffect(pattern.circleScale(at: elapsed))
                        }

                        Text(current.phase.label)
                            .font(.vandaDisplay())
                            .foregroundStyle(.white)
                            .sensoryFeedback(.impact(weight: .light), trigger: current.phase.label)
                    }
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Kész vagyok")
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
}

#Preview {
    BreathingView()
}
