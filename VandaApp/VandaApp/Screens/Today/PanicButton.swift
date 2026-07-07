//
//  PanicButton.swift
//  VandaApp
//
//  A kiemelt Panik gomb a Ma fejlécében. Lüktetése visszafogott
//  (scale 1↔1.06, ~3 s ciklus — design-tokens 6. fejezet); Reduce Motion
//  beállításnál nem lüktet.
//

import SwiftUI

struct PanicButton: View {
    let accent: Color
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(
                        accent,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    )
                    .softShadow()

                Text("Panik")
                    .font(.vandaLabel(9))
                    .textCase(.uppercase)
                    .tracking(0.45)
                    .foregroundStyle(.white)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 8)
                    .background(Color.ink, in: Capsule())
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPulsing ? Theme.Motion.pulseScale : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: Theme.Motion.pulsePeriod / 2)
                .repeatForever(autoreverses: true)
            ) {
                isPulsing = true
            }
        }
        .accessibilityLabel("Panik gomb")
    }
}

#Preview {
    ZStack {
        Theme.BackgroundGradient.default.gradient.ignoresSafeArea()
        PanicButton(accent: Theme.Accent.default) {}
    }
}
