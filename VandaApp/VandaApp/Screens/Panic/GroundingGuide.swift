//
//  GroundingGuide.swift
//  VandaApp
//
//  5-4-3-2-1 grounding gyakorlat lépései (spec 4.4), lépésenként vezetve.
//

import Foundation

struct GroundingStep: Equatable {
    let count: Int
    let emoji: String
    let title: String
    let hint: String
}

enum GroundingGuide {
    static let steps: [GroundingStep] = [
        GroundingStep(
            count: 5, emoji: "👀",
            title: "5 dolog, amit látsz",
            hint: "Nézz körül lassan… bármi jó: egy szín, egy tárgy, egy árnyék."
        ),
        GroundingStep(
            count: 4, emoji: "✋",
            title: "4 dolog, amit megérinthetsz",
            hint: "A pulcsid, a szék, a hajad, a saját tenyered…"
        ),
        GroundingStep(
            count: 3, emoji: "👂",
            title: "3 hang, amit hallasz",
            hint: "Figyelj egy kicsit… a halk hangok is számítanak."
        ),
        GroundingStep(
            count: 2, emoji: "👃",
            title: "2 illat, amit érzel",
            hint: "Ha nem találsz, csak szívd be kétszer mélyen a levegőt — az is ér."
        ),
        GroundingStep(
            count: 1, emoji: "👅",
            title: "1 íz, amit érzel",
            hint: "Egy korty víz is tökéletes."
        ),
    ]
}
