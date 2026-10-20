import CloudKit
import Foundation
import MisbehaveKit

/// Runs one `CKSyncEngine` per database: the private one holds the zones this person created
/// (owner side), the shared one the zones they were invited to (participant side).
/// The engines take care of change tokens, retries and the silent sync subscriptions.
@MainActor
final class SyncCoordinator: CKSyncEngineDelegate {
    let container = CKContainer(identifier: AppConfig.cloudContainerID)
    private unowned let model: AppModel
    private var engines: [Side: CKSyncEngine] = [:]
    private var sendTasks: [Side: Task<Void, Never>] = [:]

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        guard engines.isEmpty else { return }
        for side in [Side.owner, .participant] {
            let configuration = CKSyncEngine.Configuration(
                database: database(for: side),
                stateSerialization: loadSerialization(for: side),
                delegate: self
            )
            engines[side] = CKSyncEngine(configuration)
        }
    }

    private func database(for side: Side) -> CKDatabase {
        side == .owner ? container.privateCloudDatabase : container.sharedCloudDatabase
    }

    private func side(of engine: CKSyncEngine) -> Side {
        engine.database.databaseScope == .private ? .owner : .participant
    }

    // MARK: Queueing local changes

    func queuePoint(_ event: PointEvent, in connection: Connection) {
        queueSave(recordName: event.id, in: connection)
    }

    func queueProfile(of connection: Connection) {
        queueSave(recordName: connection.side.rawValue, in: connection)
    }

    func queueStyle(of connection: Connection) {
        queueSave(recordName: CloudSchema.styleRecordName, in: connection)
    }

    private func queueSave(recordName: String, in connection: Connection) {
        guard !connection.isDemo, let engine = engines[connection.side] else { return }
        let recordID = CKRecord.ID(recordName: recordName, zoneID: CloudSchema.zoneID(for: connection))
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        scheduleSend(connection.side)
    }

    /// Puts everything not yet confirmed back in the queue. Adding twice is harmless.
    func requeueUnsent(in state: StoreState) {
        for connection in state.connections where !connection.isDemo {
            if connection.myProfileUnsent { queueProfile(of: connection) }
            if connection.styleUnsent { queueStyle(of: connection) }
            for event in connection.events where event.unsent && event.from == connection.side {
                queuePoint(event, in: connection)
            }
        }
    }

    /// The owner deletes the zone together with its share; the participant leaves by deleting the share.
    func queueRemoval(of connection: Connection) {
        guard !connection.isDemo, let engine = engines[connection.side] else { return }
        let zoneID = CloudSchema.zoneID(for: connection)
        let stale = engine.state.pendingRecordZoneChanges.filter { change in
            switch change {
            case .saveRecord(let id), .deleteRecord(let id): id.zoneID == zoneID
            @unknown default: false
            }
        }
        engine.state.remove(pendingRecordZoneChanges: stale)
        switch connection.side {
        case .owner:
            engine.state.add(pendingDatabaseChanges: [.deleteZone(zoneID)])
        case .participant:
            engine.state.add(pendingRecordZoneChanges: [.deleteRecord(CloudSchema.shareRecordID(in: zoneID))])
        }
        scheduleSend(connection.side)
    }

    /// Zones we are in the middle of leaving; fetched changes for them must not bring the connection back.
    func zonesPendingRemoval(side: Side) -> Set<CKRecordZone.ID> {
        guard let engine = engines[side] else { return [] }
        var zones: Set<CKRecordZone.ID> = []
        for change in engine.state.pendingDatabaseChanges {
            if case .deleteZone(let zoneID) = change { zones.insert(zoneID) }
        }
        for change in engine.state.pendingRecordZoneChanges {
            if case .deleteRecord(let id) = change, id.recordName == CKRecordNameZoneWideShare { zones.insert(id.zoneID) }
        }
        return zones
    }

    // MARK: Triggering syncs

    func fetchNow() {
        for engine in engines.values {
            // Detached: this may run inside a delegate callback, and the engine traps on recursion.
            Task.detached { try? await engine.fetchChanges() }
        }
    }

    /// Fetches both databases and returns when done; used when a push wakes the app.
    func fetchAll() async {
        for engine in engines.values {
            try? await engine.fetchChanges()
        }
    }

    /// Several quick taps go out in one request. Detached because it is also called from delegate
    /// callbacks (retries), and a task inheriting their context makes the engine trap on recursion.
    private func scheduleSend(_ side: Side) {
        guard let engine = engines[side] else { return }
        sendTasks[side]?.cancel()
        sendTasks[side] = Task.detached {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            try? await engine.sendChanges()
        }
    }

    // MARK: CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        let side = side(of: syncEngine)
        switch event {
        case .stateUpdate(let update):
            saveSerialization(update.stateSerialization, for: side)

        case .accountChange(let change):
            switch change.changeType {
            case .signOut, .switchAccounts:
                // Never keep one person's connections around for the next account.
                model.accountSignedOut()
            case .signIn:
                model.quotaExceeded = false
            @unknown default:
                break
            }
            await model.refreshAccountStatus()

        case .fetchedDatabaseChanges(let changes):
            for modification in changes.modifications {
                model.zoneAppeared(modification.zoneID, side: side)
            }
            for deletion in changes.deletions {
                model.zoneDisappeared(deletion.zoneID, side: side)
            }

        case .fetchedRecordZoneChanges(let changes):
            model.applyFetched(changes.modifications.map(\.record), side: side)

        case .didFetchChanges:
            model.didSync()
            // A connection rebuilt from its zone may still lack our profile record.
            guard model.state.profile != nil else { break }
            for connection in model.state.connections
            where !connection.isDemo && connection.side == side && connection.myProfileSystemFields == nil {
                queueProfile(of: connection)
            }

        case .sentRecordZoneChanges(let sent):
            handleSent(sent, side: side, engine: syncEngine)

        case .sentDatabaseChanges, .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges,
             .willSendChanges, .didSendChanges:
            break

        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let side = side(of: syncEngine)
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            let record = await self.model.record(for: recordID, side: side)
            if record == nil {
                // Nothing local stands behind this change any more.
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            }
            return record
        }
    }

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, side: Side, engine: CKSyncEngine) {
        for record in sent.savedRecords {
            if record.recordType == CloudSchema.RecordType.profile {
                if let again = model.profileSettled(record) { queueProfile(of: again) }
            } else if record.recordType == CloudSchema.RecordType.connectionStyle {
                model.noteDiagnostics {
                    $0.lastStyleSavedAt = .now
                    $0.styleError = nil
                }
                if let again = model.styleSettled(record) { queueStyle(of: again) }
            } else {
                model.pointUploaded(record.recordID)
                if CloudSchema.hasComment(record) { model.commentSaved() }
            }
        }
        if !sent.savedRecords.isEmpty { model.quotaExceeded = false }

        for failure in sent.failedRecordSaves {
            let record = failure.record
            let isProfile = record.recordType == CloudSchema.RecordType.profile
            if record.recordType == CloudSchema.RecordType.connectionStyle {
                handleFailedStyle(failure, side: side)
                continue
            }
            switch failure.error.code {
            case .serverRecordChanged:
                if isProfile {
                    if let server = failure.error.serverRecord, let again = model.profileSettled(server) {
                        queueProfile(of: again)
                    }
                } else {
                    // Points never change, so "already there" means it arrived.
                    model.pointUploaded(record.recordID)
                }
            case .unknownItem:
                if isProfile, let again = model.profileNeedsFreshRecord(record.recordID) {
                    queueProfile(of: again)
                }
            case .zoneNotFound, .userDeletedZone:
                model.zoneDisappeared(record.recordID.zoneID, side: side)
            case let code where (code == .serverRejectedRequest || code == .invalidArguments)
                && !isProfile && CloudSchema.hasComment(record):
                // Most likely the Production schema has no comment field yet. The point matters more
                // than its note, so it goes out again without one.
                model.commentRejected(failure.error)
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
                scheduleSend(side)
            case .quotaExceeded:
                // Stays marked unsent and is queued again the next time the app opens.
                model.quotaExceeded = true
            default:
                // Network and availability errors are retried by the engine itself.
                break
            }
        }
    }

    /// Two partners editing at once: the newer look wins. Anything else waits for the next launch.
    private func handleFailedStyle(_ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave, side: Side) {
        switch failure.error.code {
        case .serverRecordChanged:
            if let server = failure.error.serverRecord, let again = model.styleSettled(server) {
                queueStyle(of: again)
            }
        case .unknownItem:
            if let again = model.styleNeedsFreshRecord(failure.record.recordID) { queueStyle(of: again) }
        case .zoneNotFound, .userDeletedZone:
            model.zoneDisappeared(failure.record.recordID.zoneID, side: side)
        case .quotaExceeded:
            model.quotaExceeded = true
        default:
            // Most likely the Production schema has no ConnectionStyle yet; stays unsent until the next launch.
            model.noteDiagnostics { $0.styleError = InboxRefresher.describe(failure.error) }
        }
    }

    // MARK: Engine state on disk

    private func serializationURL(for side: Side) -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent("sync-\(side.rawValue).json")
    }

    private func loadSerialization(for side: Side) -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: serializationURL(for: side)) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveSerialization(_ serialization: CKSyncEngine.State.Serialization, for side: Side) {
        let url = serializationURL(for: side)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(serialization).write(to: url, options: .atomic)
    }
}
