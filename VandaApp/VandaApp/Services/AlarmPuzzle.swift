//
//  AlarmPuzzle.swift
//  VandaApp
//
//  Kikapcsoló feladvány (spec 4.1) — cserélhető interfész mögött, mert később
//  iterálunk rajta (gépelés, rázás stb.). V1: szorzótábla-szintű matekpélda.
//

import Foundation

/// Egy darab feladvány (kérdés + válasz-ellenőrzés).
protocol AlarmPuzzle {
    var prompt: String { get }
    func isCorrect(_ answer: String) -> Bool
}

/// Feladvány-gyártó — az ébresztő-profil beállításaiból jön létre.
protocol AlarmPuzzleGenerator {
    func makePuzzle() -> AlarmPuzzle
}

// MARK: - Matek (v1)

struct MathPuzzle: AlarmPuzzle {
    let a: Int
    let b: Int

    var prompt: String { "\(a) × \(b) = ?" }

    func isCorrect(_ answer: String) -> Bool {
        Int(answer.trimmingCharacters(in: .whitespaces)) == a * b
    }
}

struct MathPuzzleGenerator: AlarmPuzzleGenerator {
    /// 1 = könnyű (szorzótábla), 2 = kemény (nagyobb számok)
    let difficulty: Int

    func makePuzzle() -> AlarmPuzzle {
        if difficulty >= 2 {
            return MathPuzzle(a: Int.random(in: 11...19), b: Int.random(in: 3...9))
        }
        return MathPuzzle(a: Int.random(in: 3...9), b: Int.random(in: 3...9))
    }
}

extension AlarmProfile {
    /// A profilhoz tartozó feladvány-gyártó; nil, ha nincs feladvány
    /// (ilyenkor egy sima „Ébren vagyok!" megerősítés zárja a láncot).
    var puzzleGenerator: AlarmPuzzleGenerator? {
        switch puzzleKind {
        case .none: nil
        case .math: MathPuzzleGenerator(difficulty: puzzleDifficulty)
        }
    }
}
