//
//  ThemedBackground.swift
//  VandaApp
//
//  A képernyők háttere a ThemeSettings alapján: választott gradiens, vagy
//  saját fotó olvashatósági overlay-jel (design-tokens 2. fejezet).
//

import SwiftUI

struct ThemedBackground: View {
    let settings: ThemeSettings?

    var body: some View {
        Group {
            if let settings, settings.usesPhotoBackground,
               let data = settings.photoData, let image = UIImage(data: data) {
                Color.clear
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    .overlay(Theme.Gradients.photoOverlay)
                    .clipped()
            } else {
                (settings?.gradient ?? .default).gradient
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Kártya

extension View {
    /// Standard Soft Dusk kártya: padding + lekerekített felület + lágy lila árnyék.
    /// Fotó-háttérnél a hívó a `ThemeSettings.cardSurface`-t adja át (0.9-es opacitás).
    func vandaCard(surface: Color = .surface) -> some View {
        padding(Theme.Spacing.cardPadding)
            .background(
                surface,
                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            )
            .softShadow()
    }
}
