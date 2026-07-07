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

extension ActivityTag {
    var displayName: String {
        switch self {
        case .indoor: "Bent"
        case .outdoor: "Kint"
        case .solo: "Egyedül"
        case .withSibling: "Tesóval"
        case .minutes5: "5 perc"
        case .minutes30: "Fél óra"
        case .hourPlus: "1 óra+"
        case .charging: "Töltő"
        case .calming: "Nyugi"
        }
    }

    // A szűrő három objektív dimenziója (spec 4.7); a Töltő/Nyugi címkéket
    // a barométer (2. fázis) és a panikgomb (4. fázis) ajánlói használják.
    static let placeTags: [ActivityTag] = [.indoor, .outdoor]
    static let companyTags: [ActivityTag] = [.solo, .withSibling]
    static let timeTags: [ActivityTag] = [.minutes5, .minutes30, .hourPlus]
    static let filterGroups: [[ActivityTag]] = [placeTags, companyTags, timeTags]
    static let moodTags: [ActivityTag] = [.charging, .calming]
}

@Model
final class Activity {
    var id: UUID = UUID()
    var title: String = ""
    var emoji: String = "✨"
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

    /// Illeszkedik-e a szűrésre: kategórián belül VAGY, kategóriák közt ÉS
    /// (pl. „Kint + 5 perc" = kinti ÉS rövid; „Bent + Kint" = bármelyik).
    func matches(filter selected: Set<ActivityTag>) -> Bool {
        let own = Set(activityTags)
        for group in ActivityTag.filterGroups {
            let selectedInGroup = selected.intersection(group)
            if !selectedInGroup.isEmpty, selectedInGroup.isDisjoint(with: own) {
                return false
            }
        }
        return true
    }

    /// Rövid meta-sor a kártyákra: „~5 perc · kint · egyedül"
    var metaLine: String {
        var parts: [String] = []
        if let time = activityTags.first(where: { ActivityTag.timeTags.contains($0) }) {
            parts.append("~" + time.displayName.lowercased())
        }
        for tag in activityTags where ActivityTag.placeTags.contains(tag) || ActivityTag.companyTags.contains(tag) {
            parts.append(tag.displayName.lowercased())
        }
        return parts.joined(separator: " · ")
    }
}
