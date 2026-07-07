//
//  WakePuzzleView.swift
//  VandaApp
//
//  A lánc-ébresztő kikapcsoló feladványa (spec 4.1): amíg Vanda meg nem oldja,
//  a hátralévő alarmok élnek. Feladvány nélküli profilnál egy megerősítő gomb
//  zárja a láncot.
//

import SwiftUI

struct WakePuzzleView: View {
    let profile: AlarmProfile
    let onSolved: () -> Void

    @State private var puzzle: AlarmPuzzle?
    @State private var answer = ""
    @State private var correctCount = 0
    @State private var isWrong = false
    @FocusState private var isAnswerFocused: Bool

    private var requiredCount: Int {
        profile.puzzleGenerator == nil ? 0 : max(1, profile.puzzleRequiredCorrect)
    }

    var body: some View {
        ZStack {
            Theme.BackgroundGradient.default.gradient.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.cardGap) {
                Spacer()

                Text("🌞")
                    .font(.system(size: 56))
                Text("Jó reggelt, Vanda!")
                    .font(.vandaDisplay())
                    .foregroundStyle(Color.ink)

                if let puzzle {
                    Text("Oldd meg, és elhallgat a csörgés-lánc:")
                        .font(.vandaBody())
                        .foregroundStyle(Color.inkMuted)

                    VStack(spacing: 12) {
                        Text(puzzle.prompt)
                            .font(.vandaBigNumber(40))
                            .foregroundStyle(Color.ink)

                        TextField("?", text: $answer)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .font(.vandaBigNumber(34))
                            .foregroundStyle(Color.ink)
                            .frame(width: 140)
                            .padding(.vertical, 8)
                            .background(
                                Color.surfaceTint,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous)
                            )
                            .focused($isAnswerFocused)
                            .onSubmit(check)

                        if requiredCount > 1 {
                            Text("\(correctCount)/\(requiredCount) jó válasz")
                                .font(.vandaCaption())
                                .foregroundStyle(Color.inkFaint)
                        }

                        if isWrong {
                            Text("Hoppá, nem az — próbáld újra! 💪")
                                .font(.vandaBodyStrong(13))
                                .foregroundStyle(Color.zoneRedStrong)
                        }

                        Button(action: check) {
                            Text("Megvan!")
                                .font(.vandaBodyStrong(15))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    Color.ink,
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .vandaCard()
                } else {
                    Button {
                        onSolved()
                    } label: {
                        Text("Ébren vagyok! ☀️")
                            .font(.vandaBodyStrong(15))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                Color.ink,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
        }
        .onAppear {
            puzzle = profile.puzzleGenerator?.makePuzzle()
            isAnswerFocused = true
        }
        .interactiveDismissDisabled()
    }

    private func check() {
        guard let current = puzzle else { return }
        if current.isCorrect(answer) {
            correctCount += 1
            isWrong = false
            answer = ""
            if correctCount >= requiredCount {
                onSolved()
            } else {
                puzzle = profile.puzzleGenerator?.makePuzzle()
            }
        } else {
            isWrong = true
            answer = ""
        }
    }
}

#Preview {
    WakePuzzleView(profile: AlarmProfile(), onSolved: {})
}
