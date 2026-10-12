import Foundation

/// How a score feels. Only decoration: it picks the mascot's face and a short line under the score.
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
    /// The mascot's face for a score. Only cats come with moods in emoji; the dog shows it with its badge.
    public func face(_ mood: Mood) -> String {
        guard self == .goodgirl else { return emoji }
        return switch mood {
        case .naughty: "😿"
        case .fresh: "🐱"
        case .good: "😺"
        case .great: "😸"
        case .best: "😻"
        }
    }

    /// E.g. "Purring loudly" or "In the doghouse".
    public func moodLine(_ mood: Mood) -> String {
        PushText.string("mood.\(rawValue).\(mood.rawValue)")
    }

    /// The mascot's face right after it got or lost points.
    public func face(afterDelta delta: Int) -> String {
        guard self == .goodgirl else { return emoji }
        return delta > 0 ? "😻" : delta < 0 ? "😿" : emoji
    }

    /// What the dog's face cannot say itself: a bone for a point, a broken heart for a lost one.
    public func accent(afterDelta delta: Int) -> String? {
        guard self == .goodboy, delta != 0 else { return nil }
        return delta > 0 ? "🦴" : "💔"
    }

    /// Closes the notification text, e.g. "😻" or "🐶🦴".
    public func reaction(toDelta delta: Int) -> String {
        face(afterDelta: delta) + (accent(afterDelta: delta) ?? "")
    }
}
