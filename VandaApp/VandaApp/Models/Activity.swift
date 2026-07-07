//
//  Activity.swift
//  VandaApp
//
//  Spec 3. fejezet: a tevékenység-katalógus három nézet közös háttere —
//  unatkozó fal, töltő tevékenységek (barométer ajánlja), nyugi-eszközök
//  (panikgomb ajánlja). Egy elem több címkét is kaphat.
//

import Foundation
import SwiftData

enum ActivityTag: String, Codable, CaseIterable {
    case indoor = "bent"
    case outdoor = "kint"
    case solo = "egyedul"
    case withSibling = "tesoval"
    case minutes5 = "5perc"
    case minutes30 = "felora"
    case hourPlus = "1ora+"
    case charging = "tolto"   // TÖLTŐ — a barométer ajánlja
    case calming = "nyugi"    // NYUGI — a panikgomb ajánlja
}

@Model
final class Activity {
    var id: UUID = UUID()
    var title: String = ""
    /// `ActivityTag` rawValue-k
    var tags: [String] = []
    var sourceRaw: String = ContentSource.factory.rawValue
    var createdAt: Date = Date()

    init() {}

    var source: ContentSource {
        get { ContentSource(rawValue: sourceRaw) ?? .factory }
        set { sourceRaw = newValue.rawValue }
    }

    var activityTags: [ActivityTag] {
        get { tags.compactMap(ActivityTag.init(rawValue:)) }
        set { tags = newValue.map(\.rawValue) }
    }
}
