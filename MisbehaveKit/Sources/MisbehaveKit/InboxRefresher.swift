import CloudKit
import Foundation

/// Fetches new partner points with its own change tokens and files them in the inbox.
///
/// Used by the notification extension: a CloudKit push only hints that something changed
/// and does not name the record, so the extension has to look for itself.
public actor InboxRefresher {
    public struct Outcome: Sendable {
        /// Ids of events this run saw for the first time, by connection.
        public var newEventIDs: [String: Set<String>] = [:]
        /// App state merged with the inbox after the run.
        public var snapshot = StoreState()
    }

    private let store: LocalStore
    private let containerID: String
    private var tail: Task<Outcome, Never>?

    public init(store: LocalStore = .shared, containerID: String = AppConfig.cloudContainerID) {
        self.store = store
        self.containerID = containerID
    }

    /// Runs are serialized so two pushes never write the inbox at the same time.
    public func refresh(side: Side?) async -> Outcome {
        let previous = tail
        let task = Task {
            _ = await previous?.value
            return await self.run(side: side)
        }
        tail = task
        return await task.value
    }

    private func run(side: Side?) async -> Outcome {
        let state = store.loadState()
        var inbox = store.loadInbox()
        inbox.prune(against: state)
        var outcome = Outcome()
        var report = PushRun()
        let container = CKContainer(identifier: containerID)

        for connection in state.connections where !connection.isDemo && (side == nil || connection.side == side) {
            if Task.isCancelled { break }
            let database = connection.side == .owner ? container.privateCloudDatabase : container.sharedCloudDatabase
            var zone = inbox.zones[connection.id] ?? ZoneInbox()
            let fetched: (records: [CKRecord], token: Data?)
            do {
                fetched = try await fetch(CloudSchema.zoneID(for: connection), in: database, since: zone.changeToken)
                report.zonesFetched += 1
            } catch {
                report.zonesFailed += 1
                report.error = Self.describe(error)
                continue
            }
            for record in fetched.records {
                if let event = CloudSchema.event(from: record) {
                    guard event.from == connection.side.other, !connection.containsEvent(event.id) else { continue }
                    if zone.insert(event) {
                        outcome.newEventIDs[connection.id, default: []].insert(event.id)
                    }
                } else if let profile = CloudSchema.profile(from: record), profile.side == connection.side.other {
                    zone.partnerName = profile.name
                    zone.partnerRole = profile.role
                }
                if let style = CloudSchema.style(from: record), style.updatedAt > zone.style?.updatedAt ?? .distantPast {
                    zone.style = style
                }
            }
            zone.changeToken = fetched.token
            inbox.zones[connection.id] = zone
        }

        report.newEvents = outcome.newEventIDs.values.reduce(0) { $0 + $1.count }
        inbox.lastRun = report
        try? store.saveInbox(inbox)
        var snapshot = state
        snapshot.absorb(inbox)
        outcome.snapshot = snapshot
        return outcome
    }

    private func fetch(
        _ zoneID: CKRecordZone.ID,
        in database: CKDatabase,
        since tokenData: Data?
    ) async throws -> (records: [CKRecord], token: Data?) {
        var token = CloudSchema.decodeToken(tokenData)
        var records: [CKRecord] = []
        var retriedExpiredToken = false
        while true {
            do {
                let page = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
                for result in page.modificationResultsByID.values {
                    if let modification = try? result.get() {
                        records.append(modification.record)
                    }
                }
                token = page.changeToken
                if !page.moreComing { break }
            } catch let error as CKError where error.code == .changeTokenExpired && !retriedExpiredToken {
                retriedExpiredToken = true
                token = nil
                records = []
            }
        }
        return (records, token.flatMap(CloudSchema.encodeToken))
    }

    public static func describe(_ error: any Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
    }
}
