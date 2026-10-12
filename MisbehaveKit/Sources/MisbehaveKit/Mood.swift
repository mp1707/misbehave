import Foundation

/// How a score feels. Only decoration: it picks the mascot's badge and a short line under the score.
/// The mascot itself always keeps its one face, 🐱 or 🐶.
public enum Mood: String, Sendable, CaseIterable {
    case naughty, fresh, good, great, best

    public init(score: Int) {
        self = switch score {
        case ..<0: .naughty
        case 0: .fresh
        case 1...4: .good
        case 5...14: .great
        default: .best
        }
    }

    /// A small sticker on the mascot's shoulder.
    public var badge: String? {
        switch self {
        case .naughty: "💔"
        case .fresh: nil
        case .good: "💗"
        case .great: "💖"
        case .best: "👑"
        }
    }
}

extension Role {
    /// E.g. "Purring loudly" or "In the doghouse".
    public func moodLine(_ mood: Mood) -> String {
        PushText.string("mood.\(rawValue).\(mood.rawValue)")
    }

    /// Sits next to the mascot in the notification picture: a treat for a point, a broken heart for a lost one.
    public func accent(afterDelta delta: Int) -> String? {
        guard delta != 0 else { return nil }
        if delta < 0 { return "💔" }
        return self == .goodgirl ? "🐟" : "🦴"
    }

    /// Closes the notification text, e.g. "😻" or "🐶🦴". The only place the cat changes its face.
    public func reaction(toDelta delta: Int) -> String {
        switch self {
        case .goodgirl: delta > 0 ? "😻" : delta < 0 ? "😿" : emoji
        case .goodboy: emoji + (accent(afterDelta: delta) ?? "")
        }
    }
}
