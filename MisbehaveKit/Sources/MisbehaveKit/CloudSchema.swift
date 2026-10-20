import CloudKit
import Foundation

/// Record types and field names. The production schema can only grow, never change,
/// so nothing in here may be renamed once the schema is deployed.
public enum CloudSchema {
    public static let zonePrefix = "conn-"

    public enum RecordType {
        public static let profile = "Profile"
        public static let pointFromOwner = "PointFromOwner"
        public static let pointFromParticipant = "PointFromParticipant"
        public static let connectionStyle = "ConnectionStyle"
    }

    /// The one `ConnectionStyle` record per zone; both partners write it.
    public static let styleRecordName = "style"

    public enum Field {
        public static let role = "role"
        public static let displayName = "displayName"
        public static let delta = "delta"
        public static let createdAt = "createdAt"
        public static let comment = "comment"
        /// `ConnectionStyle` as JSON, so new options need no schema change.
        public static let payload = "payload"
    }

    public enum SubscriptionID {
        public static let privateDatabase = "points-private"
        public static let sharedDatabase = "points-shared"
    }

    // MARK: Zones

    public static func newZoneID() -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zonePrefix + UUID().uuidString, ownerName: CKCurrentUserDefaultName)
    }

    public static func isConnectionZone(_ zoneID: CKRecordZone.ID) -> Bool {
        zoneID.zoneName.hasPrefix(zonePrefix)
    }

    public static func zoneID(for connection: Connection) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: connection.id, ownerName: connection.zoneOwner)
    }

    public static func shareRecordID(in zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
    }

    public static func side(for scope: CKDatabase.Scope) -> Side? {
        switch scope {
        case .private: .owner
        case .shared: .participant
        default: nil
        }
    }

    // MARK: Points

    public static func pointRecordType(from side: Side) -> String {
        side == .owner ? RecordType.pointFromOwner : RecordType.pointFromParticipant
    }

    /// `includingComment: false` leaves the note out, for when the server's schema does not know the field yet.
    public static func pointRecord(_ event: PointEvent, in zoneID: CKRecordZone.ID, includingComment: Bool = true) -> CKRecord {
        let record = CKRecord(
            recordType: pointRecordType(from: event.from),
            recordID: CKRecord.ID(recordName: event.id, zoneID: zoneID)
        )
        record[Field.delta] = Int64(event.delta)
        record[Field.createdAt] = event.createdAt
        if includingComment && !event.comment.isEmpty {
            record[Field.comment] = event.comment
        }
        return record
    }

    public static func hasComment(_ record: CKRecord) -> Bool {
        record[Field.comment] != nil
    }

    /// Reads a point record. Anything other than a single +1 or −1 is ignored.
    public static func event(from record: CKRecord) -> PointEvent? {
        let side: Side
        switch record.recordType {
        case RecordType.pointFromOwner: side = .owner
        case RecordType.pointFromParticipant: side = .participant
        default: return nil
        }
        guard let delta = record[Field.delta] as? Int, delta == 1 || delta == -1 else { return nil }
        let createdAt = record[Field.createdAt] as? Date ?? record.creationDate ?? .now
        let comment = AppConfig.cleanComment(record[Field.comment] as? String)
        return PointEvent(id: record.recordID.recordName, from: side, delta: delta, comment: comment, createdAt: createdAt)
    }

    // MARK: Profiles

    public struct RemoteProfile: Sendable, Equatable {
        public var side: Side
        public var role: Role?
        public var name: String
    }

    public static func profileRecordID(side: Side, in zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: side.rawValue, zoneID: zoneID)
    }

    public static func profileRecord(
        side: Side,
        role: Role,
        name: String,
        in zoneID: CKRecordZone.ID,
        systemFields: Data? = nil
    ) -> CKRecord {
        let recordID = profileRecordID(side: side, in: zoneID)
        let record = systemFields.flatMap(decodeSystemFields).flatMap { $0.recordID == recordID ? $0 : nil }
            ?? CKRecord(recordType: RecordType.profile, recordID: recordID)
        record[Field.role] = role.rawValue
        record[Field.displayName] = name
        return record
    }

    public static func profile(from record: CKRecord) -> RemoteProfile? {
        guard record.recordType == RecordType.profile, let side = Side(rawValue: record.recordID.recordName) else {
            return nil
        }
        return RemoteProfile(
            side: side,
            role: (record[Field.role] as? String).flatMap(Role.init(rawValue:)),
            name: AppConfig.cleanName(record[Field.displayName] as? String)
        )
    }

    // MARK: Style

    public static func styleRecordID(in zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: styleRecordName, zoneID: zoneID)
    }

    public static func styleRecord(_ style: ConnectionStyle, in zoneID: CKRecordZone.ID, systemFields: Data? = nil) -> CKRecord {
        let recordID = styleRecordID(in: zoneID)
        let record = systemFields.flatMap(decodeSystemFields).flatMap { $0.recordID == recordID ? $0 : nil }
            ?? CKRecord(recordType: RecordType.connectionStyle, recordID: recordID)
        record[Field.payload] = style.payload()
        return record
    }

    public static func style(from record: CKRecord) -> ConnectionStyle? {
        guard record.recordType == RecordType.connectionStyle, let payload = record[Field.payload] as? String else { return nil }
        return ConnectionStyle.decode(payload: payload)
    }

    // MARK: Archiving

    public static func encodeSystemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    public static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    public static func encodeToken(_ token: CKServerChangeToken) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    public static func decodeToken(_ data: Data?) -> CKServerChangeToken? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }
}
