//
//  QuestionSeeder.swift
//  VandaApp
//
//  Gyári kérdésbank a barométerhez (spec 4.3) — többszintű, mindig átugorható.
//  1 = könnyű, 2 = közepes, 3 = mély.
//

import Foundation
import SwiftData

enum QuestionSeeder {

    static func seedFactoryPackIfNeeded(in context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Question>())) ?? 0
        guard count == 0 else { return }

        for (level, text) in factoryPack {
            let question = Question()
            question.text = text
            question.level = level
            question.source = .factory
            context.insert(question)
        }
    }

    private static let factoryPack: [(Int, String)] = [
        (1, "Mire gondoltál az elmúlt 5 percben?"),
        (1, "Mi volt ma a legfinomabb falat?"),
        (1, "Milyen szín a mai napod?"),
        (2, "Minek örültél ma egy kicsit?"),
        (2, "Mi fárasztott ma a legjobban?"),
        (2, "Mi az, ami ma meglepett?"),
        (3, "Mit szeretnél, úgy igazán?"),
        (3, "Mi az, amit most jólesne hallanod valakitől?"),
        (3, "Ha holnap bármi lehetne, mi lenne?"),
    ]
}
