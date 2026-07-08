//
//  BreathingPattern.swift
//  VandaApp
//
//  Vezetett légzés (spec 4.4): box breathing és 4-7-8. UI-mentes motor,
//  a BreathingView TimelineView-ból hívja az eltelt idővel.
//

import Foundation

enum BreathingPhaseKind: Equatable {
    case inhale
    case hold
    case exhale
}

struct BreathingPhase: Equatable {
    let kind: BreathingPhaseKind
    let label: String
    let duration: TimeInterval
}

enum BreathingPattern: String, CaseIterable, Identifiable {
    case box
    case fourSevenEight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .box: "Négyzet"
        case .fourSevenEight: "4·7·8"
        }
    }

    var phases: [BreathingPhase] {
        switch self {
        case .box:
            [
                BreathingPhase(kind: .inhale, label: "Szívd be…", duration: 4),
                BreathingPhase(kind: .hold, label: "Tartsd bent…", duration: 4),
                BreathingPhase(kind: .exhale, label: "Fújd ki…", duration: 4),
                BreathingPhase(kind: .hold, label: "Maradj így…", duration: 4),
            ]
        case .fourSevenEight:
            [
                BreathingPhase(kind: .inhale, label: "Szívd be…", duration: 4),
                BreathingPhase(kind: .hold, label: "Tartsd bent…", duration: 7),
                BreathingPhase(kind: .exhale, label: "Fújd ki lassan…", duration: 8),
            ]
        }
    }

    var cycleDuration: TimeInterval {
        phases.reduce(0) { $0 + $1.duration }
    }

    /// A ciklusbeli pillanathoz tartozó fázis és a fázison belüli 0…1 haladás.
    func phase(at elapsed: TimeInterval) -> (phase: BreathingPhase, progress: Double) {
        let t = normalized(elapsed)
        var start: TimeInterval = 0
        for phase in phases {
            if t < start + phase.duration {
                return (phase, (t - start) / phase.duration)
            }
            start += phase.duration
        }
        return (phases[0], 0)
    }

    /// A lélegző kör skálája (0.62 összehúzva … 1.0 kitágulva); hold közben
    /// az előző fázis végállapotában marad.
    func circleScale(at elapsed: TimeInterval) -> Double {
        let minScale = 0.62
        let t = normalized(elapsed)
        var start: TimeInterval = 0
        for (index, phase) in phases.enumerated() {
            if t < start + phase.duration {
                let progress = (t - start) / phase.duration
                switch phase.kind {
                case .inhale: return minScale + (1 - minScale) * progress
                case .exhale: return 1 - (1 - minScale) * progress
                case .hold:
                    let previous = phases[(index + phases.count - 1) % phases.count]
                    return previous.kind == .inhale ? 1.0 : minScale
                }
            }
            start += phase.duration
        }
        return minScale
    }

    private func normalized(_ elapsed: TimeInterval) -> TimeInterval {
        let t = elapsed.truncatingRemainder(dividingBy: cycleDuration)
        return t < 0 ? t + cycleDuration : t
    }
}
