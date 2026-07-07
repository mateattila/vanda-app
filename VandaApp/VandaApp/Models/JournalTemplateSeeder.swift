//
//  JournalTemplateSeeder.swift
//  VandaApp
//
//  Gyári „Hangulatnapló" sablon (design 05): választós kérdések, egy kitöltés
//  fél perc. A sablonok szerkeszthetők, ez csak a kezdőkészlet.
//

import Foundation
import SwiftData

enum JournalTemplateSeeder {

    static func seedFactoryPackIfNeeded(in context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<JournalTemplate>())) ?? 0
        guard count == 0 else { return }

        let template = JournalTemplate()
        template.name = "Hangulatnapló"
        template.questions = [
            TemplateQuestion(
                text: "Milyen a napod egy szóban?",
                kind: .emoji,
                options: ["😞", "🙁", "😐", "🙂", "😄"]
            ),
            TemplateQuestion(
                text: "Mi volt ma jelen?",
                kind: .chips,
                options: ["🐴 lovak", "📚 suli", "🎵 zene", "👯 barátok", "🌧️ szorongás", "👨‍👩‍👧 család", "🎨 alkotás"],
                allowsMultiple: true
            ),
            TemplateQuestion(
                text: "Mi dobott fel?",
                kind: .chips,
                options: ["család", "barátok", "állatok", "alkotás", "zene", "semmi különös"],
                allowsMultiple: true
            ),
            TemplateQuestion(
                text: "Mennyire volt sűrű a nap?",
                kind: .scale,
                options: ["laza", "sűrű"]
            ),
        ]
        context.insert(template)
    }
}
