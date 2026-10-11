import CloudKit
import Foundation
import MisbehaveKit

struct Invitation {
    var zoneID: CKRecordZone.ID
    var url: URL
    var profileSystemFields: Data?
}

/// The steps that need the network right now and therefore talk to CloudKit directly:
/// creating an invitation, accepting one, saving the push subscriptions, deleting everything.
extension SyncCoordinator {
    /// A new zone with a closed, zone-wide share and exactly one one-time participant.
    /// Whoever opens the link first owns it; nobody else can join with it afterwards.
    func createInvitation(role: Role, name: String) async throws -> Invitation {
        let database = container.privateCloudDatabase
        let zoneID = CloudSchema.newZoneID()
        let zoneResults = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        _ = try zoneResults.saveResults[zoneID]?.get()

        do {
            let share = CKShare(recordZoneID: zoneID)
            share[CKShare.SystemFieldKey.title] = "misbehave"
            share.publicPermission = .none
            let guest = CKShare.Participant.oneTimeURLParticipant()
            guest.permission = .readWrite
            share.addParticipant(guest)
            let profile = CloudSchema.profileRecord(side: .owner, role: role, name: name, in: zoneID)

            let results = try await database.modifyRecords(saving: [share, profile], deleting: [])
            guard let savedShare = try results.saveResults[share.recordID]?.get() as? CKShare else {
                throw LinkError.noLink
            }
            let savedProfile = try? results.saveResults[profile.recordID]?.get()
            // The Swift spelling `oneTimeURL(for:)` is marked iOS 26; the method behind it exists since iOS 18.
            let guestIDs = [guest.participantID] + savedShare.participants.filter { $0.role != .owner }.map(\.participantID)
            guard let url = guestIDs.lazy.compactMap({ savedShare.__oneTimeURL(forParticipantID: $0) }).first else {
                throw LinkError.noLink
            }
            return Invitation(
                zoneID: zoneID,
                url: url,
                profileSystemFields: savedProfile.map(CloudSchema.encodeSystemFields)
            )
        } catch {
            // Don't leave a zone behind that nobody can be invited to.
            _ = try? await database.modifyRecordZones(saving: [], deleting: [zoneID])
            throw error
        }
    }

    /// Joins the share behind an invitation link and returns the zone it gives access to.
    func accept(_ metadata: CKShare.Metadata) async throws -> CKRecordZone.ID {
        guard metadata.containerIdentifier == AppConfig.cloudContainerID else { throw LinkError.wrongContainer }
        guard metadata.participantRole != .owner else { throw LinkError.ownInvitation }
        let zoneID = metadata.share.recordID.zoneID
        guard CloudSchema.isConnectionZone(zoneID) else { throw LinkError.wrongContainer }
        if metadata.participantStatus != .accepted {
            _ = try await container.accept(metadata)
        }
        return zoneID
    }

    /// One visible push per database, filtered by record type so that only the partner's points
    /// trigger it: the owner hears about `PointFromParticipant`, the participant about `PointFromOwner`.
    func saveSubscriptions(private savePrivate: Bool, shared saveShared: Bool) async -> (private: Bool, shared: Bool) {
        func save(_ id: String, recordType: String, in database: CKDatabase) async -> Bool {
            let subscription = CKDatabaseSubscription(subscriptionID: id)
            subscription.recordType = recordType
            let info = CKSubscription.NotificationInfo()
            info.alertLocalizationKey = PushText.neutralBodyKey
            info.shouldSendMutableContent = true
            info.soundName = "default"
            info.collapseIDKey = "points"
            subscription.notificationInfo = info
            let results = try? await database.modifySubscriptions(saving: [subscription], deleting: [])
            return (try? results?.saveResults[id]?.get()) != nil
        }
        var saved = (private: false, shared: false)
        if savePrivate {
            saved.private = await save(
                CloudSchema.SubscriptionID.privateDatabase,
                recordType: CloudSchema.RecordType.pointFromParticipant,
                in: container.privateCloudDatabase
            )
        }
        if saveShared {
            saved.shared = await save(
                CloudSchema.SubscriptionID.sharedDatabase,
                recordType: CloudSchema.RecordType.pointFromOwner,
                in: container.sharedCloudDatabase
            )
        }
        return saved
    }

    /// "Delete all data": removes every connection zone of this account, leaves every shared one
    /// and drops the push subscriptions. Returns false if CloudKit could not be reached.
    func purgeCloudData() async -> Bool {
        let privateDatabase = container.privateCloudDatabase
        let sharedDatabase = container.sharedCloudDatabase
        do {
            let own = try await privateDatabase.allRecordZones().map(\.zoneID).filter(CloudSchema.isConnectionZone)
            if !own.isEmpty {
                _ = try await privateDatabase.modifyRecordZones(saving: [], deleting: own)
            }
            let joined = try await sharedDatabase.allRecordZones().map(\.zoneID).filter(CloudSchema.isConnectionZone)
            if !joined.isEmpty {
                _ = try await sharedDatabase.modifyRecords(
                    saving: [],
                    deleting: joined.map(CloudSchema.shareRecordID),
                    atomically: false
                )
            }
            _ = try? await privateDatabase.modifySubscriptions(saving: [], deleting: [CloudSchema.SubscriptionID.privateDatabase])
            _ = try? await sharedDatabase.modifySubscriptions(saving: [], deleting: [CloudSchema.SubscriptionID.sharedDatabase])
            return true
        } catch {
            return false
        }
    }
}
