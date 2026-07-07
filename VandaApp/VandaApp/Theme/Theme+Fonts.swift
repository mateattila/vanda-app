//
//  Theme+Fonts.swift
//  VandaApp
//
//  Tipográfia-tokenek — forrás: docs/design/design-tokens.md, 3. fejezet.
//  Custom fontok: Quicksand + Nunito (Resources/Fonts, Info.plist UIAppFonts).
//  Dynamic Type: a `relativeTo:` horgonyzás miatt minden szerep a rendszer
//  szövegméret-beállításával együtt skálázódik; view-beli méretekhez
//  (ikon, mérőcsík stb.) `@ScaledMetric`-et használj.
//

import SwiftUI

extension Font {
    /// Display / képernyőcím — Quicksand Bold, 20–25 pt
    static func vandaDisplay(_ size: CGFloat = 22) -> Font {
        .custom("Quicksand-Bold", size: size, relativeTo: .title2)
    }

    /// Nagy szám (aksi %, óra) — Quicksand Bold, 34–52 pt
    static func vandaBigNumber(_ size: CGFloat = 44) -> Font {
        .custom("Quicksand-Bold", size: size, relativeTo: .largeTitle)
    }

    /// Törzsszöveg — Nunito SemiBold, 13–14 pt
    static func vandaBody(_ size: CGFloat = 14) -> Font {
        .custom("Nunito-SemiBold", size: size, relativeTo: .body)
    }

    /// Hangsúlyos törzsszöveg — Nunito Bold
    static func vandaBodyStrong(_ size: CGFloat = 14) -> Font {
        .custom("Nunito-Bold", size: size, relativeTo: .body)
    }

    /// Címke / uppercase felirat — Nunito ExtraBold, 11 pt.
    /// Teljes stílushoz (uppercase + ritkítás) a `.vandaLabelStyle()` modifier való.
    static func vandaLabel(_ size: CGFloat = 11) -> Font {
        .custom("Nunito-ExtraBold", size: size, relativeTo: .caption)
    }

    /// Segéd / halvány — Nunito SemiBold, 11–12 pt
    static func vandaCaption(_ size: CGFloat = 12) -> Font {
        .custom("Nunito-SemiBold", size: size, relativeTo: .caption)
    }
}

extension View {
    /// Uppercase címke-stílus: Nunito ExtraBold 11 pt, ~0.05em ritkítás.
    /// Jellemzően `.foregroundStyle(Color.inkFaint)`-tel párosul.
    func vandaLabelStyle() -> some View {
        font(.vandaLabel())
            .textCase(.uppercase)
            .tracking(0.55)
    }
}
