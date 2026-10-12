import Foundation

public enum Role: String, Codable, Sendable, CaseIterable, Identifiable {
    case goodgirl, goodboy

    public var id: String { rawValue }
    /// Shown as-is in every language.
    public var label: String { rawValue }
    public var opposite: Role { self == .goodgirl ? .goodboy : .goodgirl }
}

/// Which end of a connection a device is. The inviting person owns the CloudKit zone,
/// so the side follows from the database the zone lives in and survives reinstalls.
public enum Side: String, Codable, Sendable {
    case owner, participant

    public var other: Side { self == .owner ? .participant : .owner }
}

/// One tap. Never changed or deleted; a score is the sum of the deltas.
public struct PointEvent: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var from: Side
    public var delta: Int
    public var createdAt: Date
    /// Written locally but not yet confirmed by CloudKit.
    public var unsent: Bool

    public init(id: String = UUID().uuidString, from: Side, delta: Int, createdAt: Date = .now, unsent: Bool = false) {
        self.id = id
        self.from = from
        self.delta = delta
        self.createdAt = createdAt
        self.unsent = unsent
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        from = try container.decode(Side.self, forKey: .from)
        delta = try container.decode(Int.self, forKey: .delta)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        unsent = try container.decodeIfPresent(Bool.self, forKey: .unsent) ?? false
    }
}

/// A connection is the CloudKit zone itself; this is the device's local view of it.
public struct Connection: Codable, Sendable, Hashable, Identifiable {
    public enum Phase: String, Codable, Sendable {
        /// The invitation link exists but nobody has joined yet.
        case inviting
        case active
    }

    /// The zone name. Unique across accounts because it carries a UUID.
    public var id: String
    public var zoneOwner: String
    public var side: Side
    public var phase: Phase
    public var isDemo: Bool
    public var myRole: Role
    public var myName: String
    public var partnerRole: Role?
    public var partnerName: String?
    public var inviteURL: URL?
    public var createdAt: Date
    public var events: [PointEvent]
    /// Encoded system fields of this side's `Profile` record, needed to update it without a conflict.
    public var myProfileSystemFields: Data?
    /// The local profile differs from what CloudKit has.
    public var myProfileUnsent: Bool

    public init(
        id: String,
        zoneOwner: String,
        side: Side,
        phase: Phase,
        isDemo: Bool = false,
        myRole: Role,
        myName: String,
        partnerRole: Role? = nil,
        partnerName: String? = nil,
        inviteURL: URL? = nil,
        createdAt: Date = .now,
        events: [PointEvent] = [],
        myProfileSystemFields: Data? = nil,
        myProfileUnsent: Bool = false
    ) {
        self.id = id
        self.zoneOwner = zoneOwner
        self.side = side
        self.phase = phase
        self.isDemo = isDemo
        self.myRole = myRole
        self.myName = myName
        self.partnerRole = partnerRole
        self.partnerName = partnerName
        self.inviteURL = inviteURL
        self.createdAt = createdAt
        self.events = events
        self.myProfileSystemFields = myProfileSystemFields
        self.myProfileUnsent = myProfileUnsent
    }

    /// Points this device's person received: everything the other side wrote.
    public var myScore: Int { score(givenBy: side.other) }
    /// Points this device's person handed out.
    public var partnerScore: Int { score(givenBy: side) }

    public func score(givenBy giver: Side) -> Int {
        events.reduce(0) { $1.from == giver ? $0 + $1.delta : $0 }
    }

    public var hasUnsentEvents: Bool { events.contains(where: \.unsent) }

    public func containsEvent(_ id: String) -> Bool {
        events.contains { $0.id == id }
    }

    /// Adds the event unless its id is already known. Returns whether anything changed.
    @discardableResult
    public mutating func insert(_ event: PointEvent) -> Bool {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            guard events[index].unsent, !event.unsent else { return false }
            events[index].unsent = false
            return true
        }
        events.append(event)
        return true
    }
}

public struct LocalProfile: Codable, Sendable, Hashable {
    /// The default role, copied into every new connection.
    public var role: Role
    public var displayName: String

    public init(role: Role, displayName: String) {
        self.role = role
        self.displayName = displayName
    }
}

/// A connection the other side ended; shown once, then dropped.
public struct EndedNotice: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var partnerName: String?

    public init(id: String, partnerName: String?) {
        self.id = id
        self.partnerName = partnerName
    }
}

public struct Prefs: Codable, Sendable, Hashable {
    public var pushPromptDismissed = false
    public var pushDeniedHintDismissed = false
    public var privateSubscriptionSaved = false
    public var sharedSubscriptionSaved = false

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pushPromptDismissed = try container.decodeIfPresent(Bool.self, forKey: .pushPromptDismissed) ?? false
        pushDeniedHintDismissed = try container.decodeIfPresent(Bool.self, forKey: .pushDeniedHintDismissed) ?? false
        privateSubscriptionSaved = try container.decodeIfPresent(Bool.self, forKey: .privateSubscriptionSaved) ?? false
        sharedSubscriptionSaved = try container.decodeIfPresent(Bool.self, forKey: .sharedSubscriptionSaved) ?? false
    }
}

/// Everything the app keeps on the device. Only the app writes it.
public struct StoreState: Codable, Sendable, Hashable {
    public var profile: LocalProfile?
    public var connections: [Connection] = []
    /// Last time the app was in the foreground; newer partner points count as unseen.
    public var lastActiveAt: Date?
    public var notices: [EndedNotice] = []
    public var prefs = Prefs()

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try container.decodeIfPresent(LocalProfile.self, forKey: .profile)
        connections = try container.decodeIfPresent([Connection].self, forKey: .connections) ?? []
        lastActiveAt = try container.decodeIfPresent(Date.self, forKey: .lastActiveAt)
        notices = try container.decodeIfPresent([EndedNotice].self, forKey: .notices) ?? []
        prefs = try container.decodeIfPresent(Prefs.self, forKey: .prefs) ?? Prefs()
    }

    public func connection(_ id: String) -> Connection? {
        connections.first { $0.id == id }
    }

    public var hasRealConnection: Bool { connections.contains { !$0.isDemo } }
}

/// What the notification extension fetched for one zone. Only the extension writes it.
public struct ZoneInbox: Codable, Sendable, Hashable {
    public var changeToken: Data?
    public var events: [PointEvent] = []
    public var partnerName: String?
    public var partnerRole: Role?

    public init() {}

    @discardableResult
    public mutating func insert(_ event: PointEvent) -> Bool {
        guard !events.contains(where: { $0.id == event.id }) else { return false }
        events.append(event)
        return true
    }
}

/// What the notification extension did the last time a push arrived. Shown on the diagnostics screen.
public struct PushRun: Codable, Sendable, Hashable {
    public var date: Date
    public var zonesFetched: Int
    public var zonesFailed: Int
    public var newEvents: Int
    public var error: String?

    public init(date: Date = .now, zonesFetched: Int = 0, zonesFailed: Int = 0, newEvents: Int = 0, error: String? = nil) {
        self.date = date
        self.zonesFetched = zonesFetched
        self.zonesFailed = zonesFailed
        self.newEvents = newEvents
        self.error = error
    }
}

/// What the app knows about its own push setup. Shown on the diagnostics screen.
public struct AppDiagnostics: Codable, Sendable, Hashable {
    public var pushTokenAt: Date?
    public var pushTokenError: String?
    public var privateSubscriptionAt: Date?
    public var privateSubscriptionError: String?
    public var sharedSubscriptionAt: Date?
    public var sharedSubscriptionError: String?
    public var lastSyncAt: Date?
    public var lastBackgroundSyncAt: Date?
    public var lastWakeByPushAt: Date?
    public var lastFallbackNotificationAt: Date?

    public init() {}
}

public struct Inbox: Codable, Sendable, Hashable {
    /// Keyed by connection id.
    public var zones: [String: ZoneInbox] = [:]
    public var lastRun: PushRun?

    public init() {}

    /// Drops zones the app no longer knows and events the app already has.
    public mutating func prune(against state: StoreState) {
        for (id, var zone) in zones {
            guard let connection = state.connection(id), !connection.isDemo else {
                zones[id] = nil
                continue
            }
            zone.events.removeAll { connection.containsEvent($0.id) }
            zones[id] = zone
        }
    }
}

extension StoreState {
    /// Merges what the notification extension fetched. Returns whether anything changed.
    @discardableResult
    public mutating func absorb(_ inbox: Inbox) -> Bool {
        var changed = false
        for index in connections.indices {
            guard let zone = inbox.zones[connections[index].id] else { continue }
            for event in zone.events where connections[index].insert(event) {
                changed = true
            }
            if connections[index].partnerName == nil, let name = zone.partnerName {
                connections[index].partnerName = name
                changed = true
            }
            if connections[index].partnerRole == nil, let role = zone.partnerRole {
                connections[index].partnerRole = role
                changed = true
            }
        }
        return changed
    }
}
