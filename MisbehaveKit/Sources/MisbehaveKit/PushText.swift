import Foundation

/// Points one partner gave that the person has not looked at yet.
public struct PointSummary: Sendable, Equatable {
    public var connectionID: String
    public var partnerName: String?
    /// The receiving person's role in this connection.
    public var role: Role
    public var delta: Int
    /// The notes of these points, oldest first.
    public var comments: [String]
    /// What the receiving person looks like here, for the notification picture.
    public var mascot: String
    public var look: Look

    public init(
        connectionID: String,
        partnerName: String?,
        role: Role,
        delta: Int,
        comments: [String] = [],
        mascot: String? = nil,
        look: Look = Look()
    ) {
        self.connectionID = connectionID
        self.partnerName = partnerName
        self.role = role
        self.delta = delta
        self.comments = comments
        self.mascot = mascot ?? role.emoji
        self.look = look
    }
}

extension StoreState {
    /// Partner points per connection that arrived since the app was last open, plus the
    /// events in `alsoCounting` (just fetched; their timestamps come from the partner's clock).
    public func unseenSummaries(side: Side? = nil, alsoCounting newIDs: [String: Set<String>] = [:]) -> [PointSummary] {
        let seenUntil = lastActiveAt ?? .distantPast
        return connections.compactMap { connection in
            guard !connection.isDemo, side == nil || connection.side == side else { return nil }
            let fresh = newIDs[connection.id] ?? []
            let unseen = connection.events.filter {
                $0.from == connection.side.other && ($0.createdAt > seenUntil || fresh.contains($0.id))
            }
            guard !unseen.isEmpty else { return nil }
            return PointSummary(
                connectionID: connection.id,
                partnerName: connection.partnerShownName,
                role: connection.myRole,
                delta: unseen.reduce(0) { $0 + $1.delta },
                comments: unseen.sorted { $0.createdAt < $1.createdAt }.map(\.comment).filter { !$0.isEmpty },
                mascot: connection.myMascot,
                look: connection.look
            )
        }
    }
}

extension Connection {
    /// The nickname this person gave the partner, else the partner's own name; nil if neither is known.
    public var partnerShownName: String? {
        if let partnerNickname, !partnerNickname.isEmpty { return partnerNickname }
        if let partnerName, !partnerName.isEmpty { return partnerName }
        return nil
    }

    public var partnerDisplayName: String {
        partnerShownName ?? PushText.partnerFallback
    }
}

/// The wording of the notification, e.g. "+1 goodgirl point" with the note below it.
public enum PushText {
    /// Looked up in the app's string catalog by the receiving device when CloudKit sends the push.
    public static let neutralBodyKey = "push.neutral.body"

    public static var partnerFallback: String { string("partner.fallback") }

    public static func signed(_ value: Int) -> String {
        value < 0 ? "\u{2212}\(-value)" : "+\(value)"
    }

    /// "+1 goodgirl point". No emoji of its own: the notes carry whatever the partner wrote.
    public static func phrase(delta: Int, role: Role) -> String {
        if delta == 0 { return format("push.changed", role.label) }
        return points(signed(delta), count: delta, role: role)
    }

    public static func line(name: String, delta: Int, role: Role) -> String {
        if delta == 0 { return format("push.line.changed", name, role.label) }
        return name + ": " + points(signed(delta), count: delta, role: role)
    }

    /// "12 goodgirl points" or "1 goodgirl point".
    public static func points(_ score: Int, role: Role) -> String {
        points(String(score), count: score, role: role)
    }

    /// "goodgirl points" or "goodgirl point", for under a big number.
    public static func pointsLabel(count: Int, role: Role) -> String {
        format(abs(count) == 1 ? "points.label.one" : "points.label.other", role.label)
    }

    private static func points(_ number: String, count: Int, role: Role) -> String {
        number + " " + pointsLabel(count: count, role: role)
    }

    /// A note as it appears under the points: “made me coffee”.
    public static func quoted(_ comment: String) -> String {
        "\u{201C}\(comment)\u{201D}"
    }

    /// Title and body for a notification covering the given connections; nil when there is nothing to say.
    /// The notes follow the points, so the person knows right away what they were for.
    public static func content(for summaries: [PointSummary]) -> (title: String?, body: String)? {
        guard let first = summaries.first else { return nil }
        if summaries.count == 1 {
            let name = first.partnerName.flatMap { $0.isEmpty ? nil : $0 }
            let lines = [phrase(delta: first.delta, role: first.role)] + first.comments.map(quoted)
            return (name, lines.joined(separator: "\n"))
        }
        let lines = summaries.map {
            var text = line(name: $0.partnerName.flatMap { $0.isEmpty ? nil : $0 } ?? partnerFallback, delta: $0.delta, role: $0.role)
            if $0.comments.count == 1 { text += " " + quoted($0.comments[0]) }
            return text
        }
        return (nil, lines.joined(separator: "\n"))
    }

    static func string(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: .module)
    }

    private static func format(_ key: String, _ arguments: String...) -> String {
        String(format: string(key), arguments: arguments)
    }
}
