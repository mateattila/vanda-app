//
//  ActivitySeeder.swift
//  VandaApp
//
//  Gyári kezdőcsomag az unatkozó falhoz (spec 4.7) — Vanda humorával.
//  A szövegek szabadon átírhatók/törölhetők az appban.
//

import Foundation
import SwiftData

enum ActivitySeeder {

    /// Egyszer fut le: csak akkor seedel, ha még egyetlen tevékenység sincs.
    /// (CloudKit-szinkronnál elméletben előfordulhat dupla seed, ha két friss
    /// eszköz egyszerre indul a szinkron beérkezte előtt — lásd docs/decisions.md.)
    static func seedFactoryPackIfNeeded(in context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Activity>())) ?? 0
        guard count == 0 else { return }

        for (emoji, title, tags) in factoryPack {
            let activity = Activity()
            activity.emoji = emoji
            activity.title = title
            activity.activityTags = tags
            activity.source = .factory
            context.insert(activity)
        }
    }

    private static let factoryPack: [(String, String, [ActivityTag])] = [
        ("🚶‍♀️", "Sétálj egyet a kedvenc zenéddel", [.outdoor, .solo, .minutes30, .charging]),
        ("🌿", "Touch grass! Mezítláb a fűben", [.outdoor, .solo, .minutes5, .charging, .calming]),
        ("🐑", "Go feed the sheep!", [.outdoor, .minutes5]),
        ("✏️", "Firkálj le egy ötletet", [.indoor, .solo, .minutes5]),
        ("📞", "Írj rá egy barátnőre", [.indoor, .solo, .minutes5]),
        ("🍪", "Süss valami finomat", [.indoor, .withSibling, .hourPlus]),
        ("🧩", "10 perc puzzle", [.indoor, .solo, .minutes30, .calming]),
        ("🎨", "Fess vagy rajzolj egy jót", [.indoor, .solo, .minutes30, .charging]),
        ("📚", "Olvass 10 oldalt", [.indoor, .solo, .minutes30, .calming]),
        ("🎲", "Társasozz a tesóddal", [.indoor, .withSibling, .hourPlus]),
        ("🧘‍♀️", "Nyújtózz egy nagyot, lassan", [.indoor, .solo, .minutes5, .calming]),
        ("🎧", "Hallgasd végig a kedvenc albumod", [.indoor, .solo, .hourPlus, .charging, .calming]),
    ]
}
