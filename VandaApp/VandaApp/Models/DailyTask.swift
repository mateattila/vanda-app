//
//  DailyTask.swift
//  VandaApp
//
//  Spec 3. + 4.6: Vanda saját napi teendői a „Mai nap" falhoz.
//  Éjfélkor tiszta lap — nincs streak, nincs múltbeli „elrontott napok" nézet.
//

import Foundation
import SwiftData

enum DailyTaskSource: String, Codable {
    case planned  // előre beírt
    case today    // Vanda aznapi
}

@Model
final class DailyTask {
    var id: UUID = UUID()
    /// A nap, amelyikre a teendő szól
    var date: Date = Date()
    var title: String = ""
    var sourceRaw: String = DailyTaskSource.today.rawValue
    var isDone: Bool = false

    init() {}

    var source: DailyTaskSource {
        get { DailyTaskSource(rawValue: sourceRaw) ?? .today }
        set { sourceRaw = newValue.rawValue }
    }
}
