//
//  GroundingView.swift
//  VandaApp
//
//  Lépésenként vezetett 5-4-3-2-1: minden lépésben annyi pötty, ahány
//  dolgot keresünk; koppintásra telnek, a lépés a Tovább gombbal zárul.
//

import SwiftUI

struct GroundingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var stepIndex = 0
    @State private var foundCount = 0

    private var isDone: Bool { stepIndex >= GroundingGuide.steps.count }

    var body: some View {
        ZStack {
            Theme.Gradients.panic
                .ignoresSafeArea()

            if isDone {
                VStack(spacing: Theme.Spacing.cardGap) {
                    Spacer()
                    Text("🫶")
                        .font(.system(size: 52))
                    Text("Ügyes vagy. Itt vagy, most vagy.")
                        .font(.vandaDisplay())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.screenMargin)
                    Spacer()
                    closeButton(title: "Vissza az eszközökhöz")
                }
            } else {
                let step = GroundingGuide.steps[stepIndex]
                VStack(spacing: Theme.Spacing.cardGap) {
                    progressDots
                        .padding(.top, Theme.Spacing.cardGap)

                    Spacer()

                    Text(step.emoji)
                        .font(.system(size: 52))
                    Text(step.title)
                        .font(.vandaDisplay())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(step.hint)
                        .font(.vandaBody())
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.screenMargin)

                    HStack(spacing: Theme.Spacing.chipHorizontal) {
                        ForEach(0..<step.count, id: \.self) { index in
                            Circle()
                                .fill(index < foundCount ? Color.white : Color.white.opacity(0.2))
                                .frame(width: 34, height: 34)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard foundCount < step.count else { return }
                        withAnimation(.snappy) { foundCount += 1 }
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: foundCount)
                    .padding(.top, Theme.Spacing.cardGap)
                    .accessibilityLabel("Megtaláltam még egyet")
                    .accessibilityAddTraits(.isButton)

                    Spacer()

                    Button {
                        withAnimation(.snappy) {
                            stepIndex += 1
                            foundCount = 0
                        }
                    } label: {
                        Text(foundCount >= step.count ? "Tovább →" : "Ugorjunk tovább")
                            .font(.vandaBodyStrong())
                            .foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                Color.white.opacity(foundCount >= step.count ? 1 : 0.7),
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

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<GroundingGuide.steps.count, id: \.self) { index in
                Circle()
                    .fill(index <= stepIndex ? Color.white : Color.white.opacity(0.25))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func closeButton(title: String) -> some View {
        Button {
            dismiss()
        } label: {
            Text(title)
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

#Preview {
    GroundingView()
}
