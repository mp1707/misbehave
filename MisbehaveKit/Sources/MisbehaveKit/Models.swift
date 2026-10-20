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
    /// Why the point was given. Required for new points; empty for points from before notes existed.
    public var comment: String
    public var createdAt: Date
    /// Written locally but not yet confirmed by CloudKit.
    public var unsent: Bool

    public init(
        id: String = UUID().uuidString,
        from: Side,
        delta: Int,
        comment: String = "",
        createdAt: Date = .now,
        unsent: Bool = false
    ) {
        self.id = id
        self.from = from
        self.delta = delta
        self.comment = comment
        self.createdAt = createdAt
        self.unsent = unsent
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        from = try container.decode(Side.self, forKey: .from)
        delta = try container.decode(Int.self, forKey: .delta)
        comment = try container.decodeIfPresent(String.self, forKey: .comment) ?? ""
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
    /// What this person calls the partner here. Stays on this iPhone; the partner never sees it.
    public var partnerNickname: String?
    public var inviteURL: URL?
    public var createdAt: Date
    public var events: [PointEvent]
    /// Encoded system fields of this side's `Profile` record, needed to update it without a conflict.
    public var myProfileSystemFields: Data?
    /// The local profile differs from what CloudKit has.
    public var myProfileUnsent: Bool
    /// The look both partners share; nil until one of them customizes it.
    public var style: ConnectionStyle?
    /// Encoded system fields of the zone's `ConnectionStyle` record.
    public var styleSystemFields: Data?
    /// The local style differs from what CloudKit has.
    public var styleUnsent: Bool = false

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
        partnerNickname: String? = nil,
        inviteURL: URL? = nil,
        createdAt: Date = .now,
        events: [PointEvent] = [],
        myProfileSystemFields: Data? = nil,
        myProfileUnsent: Bool = false,
        style: ConnectionStyle? = nil
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
        self.partnerNickname = partnerNickname
        self.inviteURL = inviteURL
        self.createdAt = createdAt
        self.events = events
        self.myProfileSystemFields = myProfileSystemFields
        self.myProfileUnsent = myProfileUnsent
        self.style = style
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        zoneOwner = try container.decode(String.self, forKey: .zoneOwner)
        side = try container.decode(Side.self, forKey: .side)
        phase = try container.decode(Phase.self, forKey: .phase)
        isDemo = try container.decode(Bool.self, forKey: .isDemo)
        myRole = try container.decode(Role.self, forKey: .myRole)
        myName = try container.decode(String.self, forKey: .myName)
        partnerRole = try container.decodeIfPresent(Role.self, forKey: .partnerRole)
        partnerName = try container.decodeIfPresent(String.self, forKey: .partnerName)
        partnerNickname = try container.decodeIfPresent(String.self, forKey: .partnerNickname)
        inviteURL = try container.decodeIfPresent(URL.self, forKey: .inviteURL)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        events = try container.decode([PointEvent].self, forKey: .events)
        myProfileSystemFields = try container.decodeIfPresent(Data.self, forKey: .myProfileSystemFields)
        myProfileUnsent = try container.decode(Bool.self, forKey: .myProfileUnsent)
        style = try container.decodeIfPresent(ConnectionStyle.self, forKey: .style)
        styleSystemFields = try container.decodeIfPresent(Data.self, forKey: .styleSystemFields)
        styleUnsent = try container.decodeIfPresent(Bool.self, forKey: .styleUnsent) ?? false
    }

    public var look: Look { style?.look ?? Look() }

    public var resolvedPartnerRole: Role { partnerRole ?? myRole.opposite }

    /// The emoji this person wears here: chosen in the connection's style, else the role's cat or dog.
    public var myMascot: String { style?.mascot(of: side) ?? myRole.emoji }

    public var partnerMascot: String { style?.mascot(of: side.other) ?? resolvedPartnerRole.emoji }

    /// Points this device's person received: everything the other side wrote.
    public var myScore: Int { score(givenBy: side.other) }
    /// Points this device's person handed out.
    public var partnerScore: Int { score(givenBy: side) }

    public func score(givenBy giver: Side) -> Int {
        events.reduce(0) { $1.from == giver ? $0 + $1.delta : $0 }
    }

    public var hasUnsentEvents: Bool { events.contains(where: \.unsent) }

    /// The newest point the partner gave that came with a note; the widget shows it.
    public var latestReceivedNote: PointEvent? {
        events.filter { $0.from == side.other && !$0.comment.isEmpty }.max { $0.createdAt < $1.createdAt }
    }

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
    /// The app's own look, for everything outside a connection. Stays on this iPhone.
    public var look = Look()

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try container.decodeIfPresent(LocalProfile.self, forKey: .profile)
        connections = try container.decodeIfPresent([Connection].self, forKey: .connections) ?? []
        lastActiveAt = try container.decodeIfPresent(Date.self, forKey: .lastActiveAt)
        notices = try container.decodeIfPresent([EndedNotice].self, forKey: .notices) ?? []
        prefs = try container.decodeIfPresent(Prefs.self, forKey: .prefs) ?? Prefs()
        look = (try? container.decodeIfPresent(Look.self, forKey: .look)) ?? Look()
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
    public var style: ConnectionStyle?

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
    /// Last time a point went to iCloud together with its note.
    public var lastCommentSavedAt: Date?
    /// Set when iCloud refused the note, e.g. because the schema in Production lacks the field.
    public var commentError: String?
    /// Last time a connection's look reached iCloud.
    public var lastStyleSavedAt: Date?
    /// Set when iCloud refused a look, e.g. because the Production schema lacks `ConnectionStyle`.
    public var styleError: String?

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
            if let style = zone.style, !connections[index].styleUnsent,
               style.updatedAt > connections[index].style?.updatedAt ?? .distantPast {
                connections[index].style = style
                changed = true
            }
        }
        return changed
    }
}
