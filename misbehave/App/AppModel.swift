import CloudKit
import MisbehaveKit
import Observation
import SwiftUI
import UserNotifications
import WidgetKit

struct AppAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

/// The app's single source of truth: the local state plus everything that changes it.
/// Every change is written to the device first; CloudKit follows.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    nonisolated static let demoNotificationID = "demo"
    /// Collapse id of the CloudKit push and identifier of the fallback notification, so one replaces the other.
    nonisolated static let pointsNotificationID = "points"
    private static let demoID = "demo"

    private(set) var state: StoreState
    var path: [String] = []
    var alert: AppAlert?
    private(set) var accountStatus: CKAccountStatus = .couldNotDetermine
    private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var isAcceptingInvite = false
    var quotaExceeded = false
    private var notificationStatusIsKnown = false
    private var notificationPromptSnoozed = false
    private(set) var diagnostics: AppDiagnostics

    @ObservationIgnored private let store: LocalStore
    @ObservationIgnored private(set) lazy var sync = SyncCoordinator(model: self)
    @ObservationIgnored private var pendingShare: CKShare.Metadata?
    @ObservationIgnored private var demoReply: Task<Void, Never>?
    @ObservationIgnored private var demoPending: [Int] = []
    @ObservationIgnored private var accountObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var subscriptionsSavedThisLaunch = false
    @ObservationIgnored private var unannounced: Set<String> = []
    @ObservationIgnored private var announcement: Task<Void, Never>?

    init(store: LocalStore = .shared) {
        self.store = store
        state = store.snapshot()
        diagnostics = store.loadDiagnostics()
    }

    func start() {
        sync.start()
        accountObserver = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refreshAccountStatus() }
        }
    }

    // MARK: State

    @discardableResult
    func mutate<T>(_ body: (inout StoreState) -> T) -> T {
        var copy = state
        let result = body(&copy)
        guard copy != state else { return result }
        state = copy
        try? store.saveState(copy)
        WidgetCenter.shared.reloadAllTimelines()
        return result
    }

    func connection(_ id: String) -> Connection? {
        state.connection(id)
    }

    var isCloudAvailable: Bool { accountStatus == .available }

    /// Notifications are the point of the app, so the question is never dropped for good:
    /// while iOS has not been asked yet, it comes back on every launch.
    private var notificationQuestionIsOpen: Bool {
        !state.connections.isEmpty && notificationStatusIsKnown && notificationStatus == .notDetermined
    }

    /// The full-screen explanation that leads to the system prompt.
    var showsNotificationPrompt: Bool { notificationQuestionIsOpen && !notificationPromptSnoozed }

    /// The card on the home screen, for whoever chose "Later" this time.
    var showsPushPrompt: Bool { notificationQuestionIsOpen && notificationPromptSnoozed }

    var showsPushDeniedHint: Bool {
        state.hasRealConnection && notificationStatus == .denied && !state.prefs.pushDeniedHintDismissed
    }

    // MARK: Lifecycle

    func sceneBecameActive() {
        isActive = true
        announcement?.cancel()
        unannounced = []
        let inbox = store.loadInbox()
        mutate {
            $0.absorb(inbox)
            $0.lastActiveAt = .now
        }
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        sync.requeueUnsent(in: state)
        sync.fetchNow()
        Task {
            await refreshAccountStatus()
            await refreshNotificationStatus()
            await ensureSubscriptionsIfNeeded()
        }
    }

    func sceneLeftForeground() {
        isActive = false
        mutate { $0.lastActiveAt = .now }
    }

    // MARK: Diagnostics

    func noteDiagnostics(_ body: (inout AppDiagnostics) -> Void) {
        body(&diagnostics)
        store.saveDiagnostics(diagnostics)
    }

    /// What the notification extension did the last time a push reached it.
    func lastPushRun() -> PushRun? {
        store.loadInbox().lastRun
    }

    func didSync() {
        noteDiagnostics {
            $0.lastSyncAt = .now
            if !isActive { $0.lastBackgroundSyncAt = .now }
        }
    }

    /// A CloudKit push woke the app in the background: sync now so the widget is right.
    func wokenByPush() async {
        noteDiagnostics { $0.lastWakeByPushAt = .now }
        await sync.fetchAll()
    }

    func open(connectionID: String) {
        guard connection(connectionID) != nil else { return }
        path = [connectionID]
    }

    func open(url: URL) {
        if let id = AppConfig.connectionID(from: url) { open(connectionID: id) }
    }

    func refreshAccountStatus() async {
        accountStatus = (try? await sync.container.accountStatus()) ?? .couldNotDetermine
    }

    // MARK: Profile

    func completeOnboarding(role: Role, name: String) {
        mutate { $0.profile = LocalProfile(role: role, displayName: AppConfig.cleanName(name)) }
        if let metadata = pendingShare {
            pendingShare = nil
            Task { await accept(metadata) }
        }
    }

    /// The role is only the default for new connections; the name is updated everywhere.
    func updateProfile(role: Role, name: String) {
        let name = AppConfig.cleanName(name)
        guard let profile = state.profile, profile.role != role || profile.displayName != name else { return }
        var renamed: [Connection] = []
        mutate { state in
            state.profile = LocalProfile(role: role, displayName: name)
            for index in state.connections.indices where state.connections[index].myName != name {
                state.connections[index].myName = name
                guard !state.connections[index].isDemo else { continue }
                state.connections[index].myProfileUnsent = true
                renamed.append(state.connections[index])
            }
        }
        for connection in renamed { sync.queueProfile(of: connection) }
    }

    // MARK: Connections

    func addDemoConnection() {
        guard let profile = state.profile, !state.connections.contains(where: \.isDemo) else { return }
        let demo = Connection(
            id: Self.demoID,
            zoneOwner: "",
            side: .owner,
            phase: .active,
            isDemo: true,
            myRole: profile.role,
            myName: profile.displayName,
            partnerRole: profile.role.opposite,
            partnerName: String(localized: "Demo partner"),
            events: [
                PointEvent(from: .participant, delta: 1),
                PointEvent(from: .participant, delta: 1),
                PointEvent(from: .owner, delta: 1),
            ]
        )
        mutate { $0.connections.append(demo) }
        path = [demo.id]
    }

    /// Creates the zone, its share and the one-time link. Needs a network connection.
    func createInvitation() async throws -> Connection {
        guard let profile = state.profile else { throw LinkError.notReady }
        let invitation = try await sync.createInvitation(role: profile.role, name: profile.displayName)
        let connection = mutate { state in
            if let index = state.connections.firstIndex(where: { $0.id == invitation.zoneID.zoneName }) {
                // The sync engine saw the new zone before we got here.
                state.connections[index].inviteURL = invitation.url
                state.connections[index].myRole = profile.role
                state.connections[index].myName = profile.displayName
                state.connections[index].myProfileSystemFields = invitation.profileSystemFields
                return state.connections[index]
            }
            let connection = Connection(
                id: invitation.zoneID.zoneName,
                zoneOwner: invitation.zoneID.ownerName,
                side: .owner,
                phase: .inviting,
                myRole: profile.role,
                myName: profile.displayName,
                inviteURL: invitation.url,
                myProfileSystemFields: invitation.profileSystemFields
            )
            state.connections.append(connection)
            return connection
        }
        Task { await ensureSubscriptionsIfNeeded() }
        return connection
    }

    func handleIncomingShare(_ metadata: CKShare.Metadata) {
        guard state.profile != nil else {
            // Finish onboarding first; the invitation is accepted right after.
            pendingShare = metadata
            return
        }
        Task { await accept(metadata) }
    }

    private func accept(_ metadata: CKShare.Metadata) async {
        guard let profile = state.profile, !isAcceptingInvite else { return }
        isAcceptingInvite = true
        defer { isAcceptingInvite = false }
        do {
            let zoneID = try await sync.accept(metadata)
            let ownerName = metadata.ownerIdentity.nameComponents.map {
                AppConfig.cleanName(PersonNameComponentsFormatter.localizedString(from: $0, style: .short))
            }
            let connection = mutate { state in
                if let existing = state.connection(zoneID.zoneName) { return existing }
                let connection = Connection(
                    id: zoneID.zoneName,
                    zoneOwner: zoneID.ownerName,
                    side: .participant,
                    phase: .active,
                    myRole: profile.role,
                    myName: profile.displayName,
                    partnerName: ownerName.flatMap { $0.isEmpty ? nil : $0 },
                    myProfileUnsent: true
                )
                state.connections.append(connection)
                return connection
            }
            sync.queueProfile(of: connection)
            sync.fetchNow()
            path = [connection.id]
            await ensureSubscriptionsIfNeeded()
        } catch LinkError.ownInvitation {
            alert = AppAlert(
                title: String(localized: "That's your own link"),
                message: String(localized: "Send the invitation link to your partner. It only works on their iPhone.")
            )
        } catch {
            alert = AppAlert(
                title: String(localized: "Couldn't connect"),
                message: String(localized: "The invitation may have been used already, or iCloud isn't reachable. Ask for a new link and try again.")
            )
        }
    }

    /// Ends a connection from this side: the owner deletes the zone, the partner leaves the share.
    func disconnect(_ id: String) {
        guard let connection = connection(id) else { return }
        path.removeAll { $0 == id }
        mutate { $0.connections.removeAll { $0.id == id } }
        if connection.isDemo {
            demoReply?.cancel()
            demoPending = []
        } else {
            sync.queueRemoval(of: connection)
        }
    }

    func dismissNotice(_ notice: EndedNotice) {
        mutate { $0.notices.removeAll { $0.id == notice.id } }
    }

    // MARK: Points

    func givePoint(_ delta: Int, in id: String) {
        guard let connection = connection(id), connection.phase == .active else { return }
        let event = PointEvent(from: connection.side, delta: delta, unsent: !connection.isDemo)
        mutate { state in
            guard let index = state.connections.firstIndex(where: { $0.id == id }) else { return }
            state.connections[index].insert(event)
        }
        if connection.isDemo {
            scheduleDemoReply(mirroring: delta)
        } else {
            sync.queuePoint(event, in: connection)
        }
    }

    /// The demo partner mirrors whatever you do, so both directions and the notification can be tried alone.
    private func scheduleDemoReply(mirroring delta: Int) {
        demoPending.append(delta)
        demoReply?.cancel()
        demoReply = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let demo = connection(Self.demoID) else { return }
            let deltas = demoPending
            demoPending = []
            mutate { state in
                guard let index = state.connections.firstIndex(where: { $0.id == Self.demoID }) else { return }
                for delta in deltas {
                    state.connections[index].insert(PointEvent(from: demo.side.other, delta: delta))
                }
            }
            guard notificationStatus == .authorized || notificationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = demo.partnerDisplayName
            content.body = PushText.phrase(delta: deltas.reduce(0, +), role: demo.myRole)
            content.sound = .default
            content.userInfo = [AppConfig.connectionUserInfoKey: demo.id]
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: Self.demoNotificationID, content: content, trigger: nil)
            )
        }
    }

    // MARK: Notifications

    func refreshNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationStatusIsKnown = true
    }

    func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refreshNotificationStatus()
    }

    /// Hides the full-screen prompt until the next launch.
    func snoozeNotificationPrompt() {
        notificationPromptSnoozed = true
    }

    func dismissPushDeniedHint() {
        mutate { $0.prefs.pushDeniedHintDismissed = true }
    }

    /// Saves the two push subscriptions once per launch. Saving again is harmless and repairs
    /// a subscription that got lost or was created by an older version.
    func ensureSubscriptionsIfNeeded(force: Bool = false) async {
        guard state.hasRealConnection, isCloudAvailable, force || !subscriptionsSavedThisLaunch else { return }
        subscriptionsSavedThisLaunch = true
        let result = await sync.saveSubscriptions()
        noteDiagnostics {
            $0.privateSubscriptionError = result.privateError
            $0.sharedSubscriptionError = result.sharedError
            if result.privateError == nil { $0.privateSubscriptionAt = .now }
            if result.sharedError == nil { $0.sharedSubscriptionAt = .now }
        }
        if result.privateError != nil || result.sharedError != nil {
            subscriptionsSavedThisLaunch = false
        }
    }

    // MARK: Fallback notification

    /// Partner points arrived through a background sync. Normally CloudKit's visible push has
    /// already told the person; if it did not show up, say it ourselves.
    private func partnerPointsArrived(_ connectionIDs: Set<String>) {
        guard !connectionIDs.isEmpty, !isActive else { return }
        unannounced.formUnion(connectionIDs)
        announcement?.cancel()
        announcement = Task { await announceIfNeeded() }
    }

    private func announceIfNeeded() async {
        let background = UIApplication.shared.beginBackgroundTask(withName: "announce")
        defer { UIApplication.shared.endBackgroundTask(background) }
        // Give the push and the notification extension time to get there first.
        try? await Task.sleep(for: .seconds(6))
        guard !Task.isCancelled, !isActive else { return }
        let connectionIDs = unannounced
        unannounced = []
        await refreshNotificationStatus()
        guard notificationStatus == .authorized || notificationStatus == .provisional else { return }
        guard await !Self.remoteNotificationWasJustDelivered() else { return }
        // Only points newer than the last look at the app; a restored history stays quiet.
        let summaries = state.unseenSummaries().filter { connectionIDs.contains($0.connectionID) }
        guard let text = PushText.content(for: summaries) else { return }
        let content = UNMutableNotificationContent()
        if let title = text.title { content.title = title }
        content.body = text.body
        content.sound = .default
        content.threadIdentifier = Self.pointsNotificationID
        if summaries.count == 1 {
            content.userInfo = [AppConfig.connectionUserInfoKey: summaries[0].connectionID]
        }
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: Self.pointsNotificationID, content: content, trigger: nil)
        )
        noteDiagnostics { $0.lastFallbackNotificationAt = .now }
    }

    nonisolated private static func remoteNotificationWasJustDelivered() async -> Bool {
        let cutoff = Date.now.addingTimeInterval(-90)
        return await UNUserNotificationCenter.current().deliveredNotifications().contains {
            $0.request.trigger is UNPushNotificationTrigger && $0.date > cutoff
        }
    }

    // MARK: Deleting

    func deleteAllData() async {
        demoReply?.cancel()
        demoPending = []
        let real = state.connections.filter { !$0.isDemo }
        for connection in real { sync.queueRemoval(of: connection) }
        let purged = await sync.purgeCloudData()
        path = []
        state = StoreState()
        store.deleteAll()
        diagnostics = AppDiagnostics()
        subscriptionsSavedThisLaunch = false
        WidgetCenter.shared.reloadAllTimelines()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        if !purged && !real.isEmpty {
            alert = AppAlert(
                title: String(localized: "Deleted on this iPhone"),
                message: String(localized: "iCloud isn't reachable right now. The data in iCloud is removed as soon as the app is open and online again.")
            )
        }
    }

    // MARK: Changes coming from CloudKit

    /// Applies fetched records. Connections are found by zone, never by name.
    func applyFetched(_ records: [CKRecord], side: Side) {
        guard !records.isEmpty else { return }
        let skipped = sync.zonesPendingRemoval(side: side)
        var partnerLeft: [String] = []
        var receivedIn: Set<String> = []
        mutate { state in
            for record in records {
                let zoneID = record.recordID.zoneID
                guard !skipped.contains(zoneID),
                      let index = Self.ensureConnection(for: zoneID, side: side, in: &state) else { continue }

                if let event = CloudSchema.event(from: record) {
                    if state.connections[index].insert(event), event.from == side.other {
                        receivedIn.insert(state.connections[index].id)
                    }
                } else if let profile = CloudSchema.profile(from: record) {
                    if profile.side == side {
                        // Our own profile, written by this or another of our devices.
                        state.connections[index].myProfileSystemFields = CloudSchema.encodeSystemFields(of: record)
                        guard !state.connections[index].myProfileUnsent else { continue }
                        if let role = profile.role { state.connections[index].myRole = role }
                        state.connections[index].myName = profile.name
                        if state.profile == nil, let role = profile.role {
                            // Fresh install with existing connections: no need to ask again.
                            state.profile = LocalProfile(role: role, displayName: profile.name)
                        }
                    } else {
                        state.connections[index].partnerRole = profile.role
                        state.connections[index].partnerName = profile.name.isEmpty ? nil : profile.name
                        state.connections[index].phase = .active
                        state.connections[index].inviteURL = nil
                    }
                } else if let share = record as? CKShare, side == .owner {
                    let others = share.participants.filter { $0.role != .owner }
                    if others.contains(where: { $0.acceptanceStatus == .accepted }) {
                        state.connections[index].phase = .active
                        state.connections[index].inviteURL = nil
                    } else if state.connections[index].partnerRole != nil,
                              others.allSatisfy({ $0.acceptanceStatus == .removed }) {
                        // The partner had joined and is gone again.
                        partnerLeft.append(state.connections[index].id)
                    }
                }
            }
        }
        for id in partnerLeft { endedByPartner(id, deleteZone: true) }
        partnerPointsArrived(receivedIn)
    }

    func zoneAppeared(_ zoneID: CKRecordZone.ID, side: Side) {
        guard !sync.zonesPendingRemoval(side: side).contains(zoneID) else { return }
        mutate { _ = Self.ensureConnection(for: zoneID, side: side, in: &$0) }
    }

    /// The zone is gone on the server: deleted by the owner, or we were removed from the share.
    func zoneDisappeared(_ zoneID: CKRecordZone.ID, side: Side) {
        guard let connection = connection(zoneID.zoneName), connection.side == side, !connection.isDemo else { return }
        if side == .participant {
            endedByPartner(connection.id, deleteZone: false)
        } else {
            path.removeAll { $0 == connection.id }
            mutate { $0.connections.removeAll { $0.id == connection.id } }
        }
    }

    private func endedByPartner(_ id: String, deleteZone: Bool) {
        guard let connection = connection(id) else { return }
        path.removeAll { $0 == id }
        mutate { state in
            state.connections.removeAll { $0.id == id }
            if connection.phase == .active {
                state.notices.append(EndedNotice(id: id, partnerName: connection.partnerName))
            }
        }
        if deleteZone { sync.queueRemoval(of: connection) }
    }

    /// Finds the connection for a zone or rebuilds it, e.g. after a reinstall or on a second device.
    private static func ensureConnection(for zoneID: CKRecordZone.ID, side: Side, in state: inout StoreState) -> Int? {
        guard CloudSchema.isConnectionZone(zoneID) else { return nil }
        if let index = state.connections.firstIndex(where: { $0.id == zoneID.zoneName }) {
            return state.connections[index].side == side ? index : nil
        }
        state.connections.append(Connection(
            id: zoneID.zoneName,
            zoneOwner: zoneID.ownerName,
            side: side,
            phase: side == .owner ? .inviting : .active,
            myRole: state.profile?.role ?? .goodgirl,
            myName: state.profile?.displayName ?? ""
        ))
        return state.connections.count - 1
    }

    func accountSignedOut() {
        path = []
        mutate { state in
            state.connections.removeAll { !$0.isDemo }
            state.notices = []
            state.prefs.privateSubscriptionSaved = false
            state.prefs.sharedSubscriptionSaved = false
        }
        subscriptionsSavedThisLaunch = false
    }

    // MARK: Results of uploads

    func pointUploaded(_ recordID: CKRecord.ID) {
        mutate { state in
            guard let c = state.connections.firstIndex(where: { $0.id == recordID.zoneID.zoneName }),
                  let e = state.connections[c].events.firstIndex(where: { $0.id == recordID.recordName }) else { return }
            state.connections[c].events[e].unsent = false
        }
    }

    /// Our profile reached CloudKit, or CloudKit told us what it has instead (`server`).
    /// Returns the connection if it has to be sent again.
    func profileSettled(_ record: CKRecord) -> Connection? {
        mutate { state in
            guard let index = state.connections.firstIndex(where: { $0.id == record.recordID.zoneID.zoneName }),
                  let profile = CloudSchema.profile(from: record), profile.side == state.connections[index].side else { return nil }
            state.connections[index].myProfileSystemFields = CloudSchema.encodeSystemFields(of: record)
            let connection = state.connections[index]
            if profile.role == connection.myRole && profile.name == connection.myName {
                state.connections[index].myProfileUnsent = false
                return nil
            }
            if connection.myProfileUnsent { return state.connections[index] }
            // We had nothing new to say, so CloudKit's version wins.
            if let role = profile.role { state.connections[index].myRole = role }
            state.connections[index].myName = profile.name
            return nil
        }
    }

    /// The stored system fields no longer match a record on the server.
    func profileNeedsFreshRecord(_ recordID: CKRecord.ID) -> Connection? {
        mutate { state in
            guard let index = state.connections.firstIndex(where: { $0.id == recordID.zoneID.zoneName }) else { return nil }
            state.connections[index].myProfileSystemFields = nil
            state.connections[index].myProfileUnsent = true
            return state.connections[index]
        }
    }

    /// The record to upload for a pending change, built from the local state.
    func record(for recordID: CKRecord.ID, side: Side) -> CKRecord? {
        guard let connection = connection(recordID.zoneID.zoneName), connection.side == side, !connection.isDemo else { return nil }
        if recordID.recordName == side.rawValue {
            return CloudSchema.profileRecord(
                side: side,
                role: connection.myRole,
                name: connection.myName,
                in: recordID.zoneID,
                systemFields: connection.myProfileSystemFields
            )
        }
        guard let event = connection.events.first(where: { $0.id == recordID.recordName && $0.from == side }) else { return nil }
        return CloudSchema.pointRecord(event, in: recordID.zoneID)
    }
}

enum LinkError: Error {
    case notReady
    case ownInvitation
    case wrongContainer
    case noLink
}
