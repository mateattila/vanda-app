//
//  MoodSettings.swift
//  VandaApp
//
//  A hangulatbarométer beállításai (spec 4.3): zónahatárok, napi rákérdezések
//  idősávja, kérdésbank-szint, megosztás-kapcsolók. CloudKit-szinkronizált.
//

import Foundation
import SwiftData

@Model
final class MoodSettings {
    /// E fölött zöld zóna („bírom")
    var greenMinPercent: Int = 60
    /// E fölött narancs zóna („fárad"); alatta piros („kimerül")
    var orangeMinPercent: Int = 30

    /// Napi véletlenszerű rákérdezések száma (0 = kikapcsolva)
    var promptsPerDay: Int = 1
    /// A rákérdezések idősávja (órában)
    var promptWindowStartHour: Int = 15
    var promptWindowEndHour: Int = 19

    /// Az aksi% után felajánlott kérdés a forgó bankból
    var questionsEnabled: Bool = true
    /// Legmélyebb megengedett szint (1 = könnyű … 3 = mély)
    var questionMaxLevel: Int = 3

    /// Szülői megosztás — a 2. fázisban még csak UI-elem, élesben a 4. fázis
    /// backendje kapcsolja be (spec 7. fejezet).
    var shareMoodWithParents: Bool = false
    var shareProgressWithParents: Bool = false

    init() {}
}

extension MoodSettings {
    func zone(for percent: Int) -> MoodZone {
        if percent >= greenMinPercent { return .green }
        if percent >= orangeMinPercent { return .orange }
        return .red
    }

    static func ensureCurrent(in context: ModelContext) -> MoodSettings {
        var descriptor = FetchDescriptor<MoodSettings>(sortBy: [SortDescriptor(\.greenMinPercent)])
        descriptor.fetchLimit = 1
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        let settings = MoodSettings()
        context.insert(settings)
        return settings
    }
}
