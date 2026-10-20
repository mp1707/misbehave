import CloudKit
import Foundation
import Testing
@testable import MisbehaveKit

private func makeConnection(id: String = "conn-1", side: Side = .owner, events: [PointEvent] = []) -> Connection {
    Connection(
        id: id,
        zoneOwner: CKCurrentUserDefaultName,
        side: side,
        phase: .active,
        myRole: .goodboy,
        myName: "Me",
        partnerRole: .goodgirl,
        partnerName: "Anna",
        events: events
    )
}

@Suite struct ScoreTests {
    @Test func scoreIsTheSumOfTheOtherSidesDeltas() {
        let connection = makeConnection(side: .owner, events: [
            PointEvent(from: .participant, delta: 1),
            PointEvent(from: .participant, delta: 1),
            PointEvent(from: .participant, delta: -1),
            PointEvent(from: .owner, delta: 1),
        ])
        #expect(connection.myScore == 1)
        #expect(connection.partnerScore == 1)
    }

    @Test func theSameConnectionReadsMirroredFromTheOtherSide() {
        let events = [PointEvent(from: .owner, delta: 1), PointEvent(from: .owner, delta: 1), PointEvent(from: .participant, delta: -1)]
        let owner = makeConnection(side: .owner, events: events)
        let participant = makeConnection(side: .participant, events: events)
        #expect(owner.myScore == participant.partnerScore)
        #expect(owner.partnerScore == participant.myScore)
        #expect(participant.myScore == 2)
    }

    @Test func anEventCountsOnlyOnce() {
        var connection = makeConnection()
        let event = PointEvent(id: "e1", from: .participant, delta: 1)
        let first = connection.insert(event)
        let second = connection.insert(event)
        #expect(first)
        #expect(!second)
        #expect(connection.myScore == 1)
    }

    @Test func theWidgetNoteIsTheNewestOneFromThePartner() {
        let connection = makeConnection(side: .owner, events: [
            PointEvent(id: "a", from: .participant, delta: 1, comment: "older", createdAt: Date(timeIntervalSince1970: 10)),
            PointEvent(id: "b", from: .participant, delta: -1, comment: "newer", createdAt: Date(timeIntervalSince1970: 20)),
            PointEvent(id: "c", from: .participant, delta: 1, createdAt: Date(timeIntervalSince1970: 30)),
            PointEvent(id: "d", from: .owner, delta: 1, comment: "mine", createdAt: Date(timeIntervalSince1970: 40)),
        ])
        #expect(connection.latestReceivedNote?.comment == "newer")
    }

    @Test func aConfirmedCopyClearsTheUnsentFlag() {
        var connection = makeConnection()
        connection.insert(PointEvent(id: "e1", from: .owner, delta: 1, unsent: true))
        #expect(connection.hasUnsentEvents)
        let changed = connection.insert(PointEvent(id: "e1", from: .owner, delta: 1))
        #expect(changed)
        #expect(!connection.hasUnsentEvents)
        #expect(connection.events.count == 1)
    }
}

@Suite struct StoreTests {
    private func temporaryStore() -> LocalStore {
        LocalStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    @Test func stateSurvivesARoundTrip() throws {
        let store = temporaryStore()
        var state = StoreState()
        state.profile = LocalProfile(role: .goodgirl, displayName: "Mia")
        state.connections = [makeConnection(events: [PointEvent(from: .participant, delta: 1)])]
        try store.saveState(state)
        #expect(store.loadState() == state)
    }

    @Test func olderEventsWithoutANoteStillLoad() throws {
        let json = #"{"id":"e1","from":"owner","delta":1,"createdAt":0}"#
        let event = try JSONDecoder().decode(PointEvent.self, from: Data(json.utf8))
        #expect(event.comment == "")
    }

    @Test func aMissingFileIsAnEmptyState() {
        #expect(temporaryStore().loadState() == StoreState())
    }

    @Test func olderFilesWithoutNewFieldsStillLoad() throws {
        let json = #"{"connections":[],"profile":{"role":"goodboy","displayName":""}}"#
        let state = try JSONDecoder().decode(StoreState.self, from: Data(json.utf8))
        #expect(state.profile?.role == .goodboy)
        #expect(state.prefs == Prefs())
    }

    @Test func theSnapshotMergesTheInbox() throws {
        let store = temporaryStore()
        var state = StoreState()
        state.connections = [makeConnection(events: [PointEvent(id: "known", from: .participant, delta: 1)])]
        try store.saveState(state)

        var zone = ZoneInbox()
        zone.insert(PointEvent(id: "known", from: .participant, delta: 1))
        zone.insert(PointEvent(id: "new", from: .participant, delta: 1))
        var inbox = Inbox()
        inbox.zones["conn-1"] = zone
        inbox.zones["gone"] = ZoneInbox()
        try store.saveInbox(inbox)

        #expect(store.snapshot().connections[0].myScore == 2)
    }

    @Test func pruningDropsUnknownZonesAndKnownEvents() {
        var state = StoreState()
        state.connections = [makeConnection(events: [PointEvent(id: "known", from: .participant, delta: 1)])]
        var zone = ZoneInbox()
        zone.insert(PointEvent(id: "known", from: .participant, delta: 1))
        zone.insert(PointEvent(id: "new", from: .participant, delta: -1))
        var inbox = Inbox()
        inbox.zones["conn-1"] = zone
        inbox.zones["gone"] = ZoneInbox()
        inbox.prune(against: state)
        #expect(inbox.zones.keys.sorted() == ["conn-1"])
        #expect(inbox.zones["conn-1"]?.events.map(\.id) == ["new"])
    }
}

@Suite struct CloudSchemaTests {
    private let zoneID = CKRecordZone.ID(zoneName: "conn-1", ownerName: CKCurrentUserDefaultName)

    @Test func aPointSurvivesTheRecordRoundTrip() {
        let event = PointEvent(id: "e1", from: .participant, delta: -1, createdAt: Date(timeIntervalSince1970: 1000))
        let record = CloudSchema.pointRecord(event, in: zoneID)
        #expect(record.recordType == "PointFromParticipant")
        #expect(CloudSchema.event(from: record) == event)
    }

    @Test func aNoteTravelsWithThePoint() {
        let event = PointEvent(id: "e2", from: .owner, delta: 1, comment: "made me coffee", createdAt: Date(timeIntervalSince1970: 1000))
        let record = CloudSchema.pointRecord(event, in: zoneID)
        #expect(CloudSchema.hasComment(record))
        #expect(CloudSchema.event(from: record) == event)
    }

    @Test func aPointCanGoOutWithoutItsNote() {
        let event = PointEvent(id: "e3", from: .owner, delta: -1, comment: "late again")
        let record = CloudSchema.pointRecord(event, in: zoneID, includingComment: false)
        #expect(!CloudSchema.hasComment(record))
        #expect(CloudSchema.event(from: record)?.comment == "")
    }

    @Test func notesAreOneTrimmedLine() {
        #expect(AppConfig.cleanComment("  so\nsweet \n") == "so sweet")
        #expect(AppConfig.cleanComment(String(repeating: "a", count: 500)).count == AppConfig.maxCommentLength)
    }

    @Test func deltasOtherThanOneAreIgnored() {
        let record = CKRecord(recordType: "PointFromOwner", recordID: CKRecord.ID(recordName: "e1", zoneID: zoneID))
        record["delta"] = Int64(500)
        #expect(CloudSchema.event(from: record) == nil)
    }

    @Test func aProfileSurvivesTheRecordRoundTrip() {
        let record = CloudSchema.profileRecord(side: .participant, role: .goodgirl, name: "Anna", in: zoneID)
        #expect(record.recordID.recordName == "participant")
        #expect(CloudSchema.profile(from: record) == .init(side: .participant, role: .goodgirl, name: "Anna"))
    }

    @Test func systemFieldsAreReusedOnlyForTheSameRecord() {
        let original = CloudSchema.profileRecord(side: .owner, role: .goodboy, name: "Ben", in: zoneID)
        let fields = CloudSchema.encodeSystemFields(of: original)
        let same = CloudSchema.profileRecord(side: .owner, role: .goodgirl, name: "Ben", in: zoneID, systemFields: fields)
        #expect(same.recordID == original.recordID)
        let other = CloudSchema.profileRecord(side: .participant, role: .goodgirl, name: "Ben", in: zoneID, systemFields: fields)
        #expect(other.recordID.recordName == "participant")
    }

    @Test func connectionLinksRoundTrip() throws {
        let url = try #require(AppConfig.connectionURL(id: "conn-ABC"))
        #expect(AppConfig.connectionID(from: url) == "conn-ABC")
        #expect(AppConfig.connectionID(from: URL(string: "https://example.com/conn-ABC")!) == nil)
    }
}

@Suite struct PushTextTests {
    @Test func signedNumbersUseARealMinus() {
        #expect(PushText.signed(3) == "+3")
        #expect(PushText.signed(-1) == "\u{2212}1")
    }

    @Test func aSinglePointNamesTheRole() {
        #expect(PushText.phrase(delta: 1, role: .goodgirl) == "You received +1 goodgirl point 😻")
        #expect(PushText.phrase(delta: 3, role: .goodboy) == "You received +3 goodboy points 🐶🦴")
        #expect(PushText.phrase(delta: -1, role: .goodboy) == "You received \u{2212}1 goodboy point 🐶💔")
    }

    @Test func oneConnectionUsesThePartnerAsTitle() {
        let content = PushText.content(for: [PointSummary(connectionID: "a", partnerName: "Anna", role: .goodboy, delta: 2)])
        #expect(content?.title == "Anna")
        #expect(content?.body == "You received +2 goodboy points 🐶🦴")
    }

    @Test func theNotesFollowThePoints() {
        let content = PushText.content(for: [PointSummary(connectionID: "a", partnerName: "Anna", role: .goodgirl, delta: 2, comments: ["coffee", "flowers"])])
        #expect(content?.body == "You received +2 goodgirl points 😻\n\u{201C}coffee\u{201D}\n\u{201C}flowers\u{201D}")
    }

    @Test func aNicknameWinsOverThePartnersOwnName() {
        var connection = makeConnection()
        #expect(connection.partnerDisplayName == "Anna")
        connection.partnerNickname = "Bunny"
        #expect(connection.partnerDisplayName == "Bunny")
        connection.partnerNickname = ""
        #expect(connection.partnerShownName == "Anna")
    }

    @Test func severalConnectionsGetALineEach() {
        let content = PushText.content(for: [
            PointSummary(connectionID: "a", partnerName: "Anna", role: .goodboy, delta: 1),
            PointSummary(connectionID: "b", partnerName: nil, role: .goodboy, delta: -2),
        ])
        #expect(content?.title == nil)
        #expect(content?.body == "Anna: +1 goodboy point 🐶🦴\nYour partner: \u{2212}2 goodboy points 🐶💔")
    }

    @Test func aScoreHasAMood() {
        #expect([-3, 0, 1, 4, 5, 14, 15].map(Mood.init(score:)) == [.naughty, .fresh, .good, .good, .great, .great, .best])
        #expect(Role.goodgirl.moodLine(.great) == "Purring loudly")
        #expect(Role.goodboy.moodLine(.naughty) == "In the doghouse")
    }

    @Test func nothingUnseenMeansNoText() {
        #expect(PushText.content(for: []) == nil)
    }

    @Test func unseenPointsAreSummedPerConnectionSinceTheAppWasOpen() {
        let opened = Date(timeIntervalSince1970: 1000)
        var state = StoreState()
        state.lastActiveAt = opened
        state.connections = [
            makeConnection(id: "conn-1", side: .owner, events: [
                PointEvent(id: "old", from: .participant, delta: 1, createdAt: opened.addingTimeInterval(-60)),
                PointEvent(id: "n1", from: .participant, delta: 1, createdAt: opened.addingTimeInterval(10)),
                PointEvent(id: "n2", from: .participant, delta: 1, createdAt: opened.addingTimeInterval(20)),
                PointEvent(id: "mine", from: .owner, delta: 1, createdAt: opened.addingTimeInterval(30)),
            ]),
            makeConnection(id: "conn-2", side: .participant, events: [
                PointEvent(id: "skewed", from: .owner, delta: -1, createdAt: opened.addingTimeInterval(-5)),
            ]),
        ]
        #expect(state.unseenSummaries().map(\.delta) == [2])
        #expect(state.unseenSummaries(alsoCounting: ["conn-2": ["skewed"]]).map(\.delta) == [2, -1])
        #expect(state.unseenSummaries(side: .participant, alsoCounting: ["conn-2": ["skewed"]]).map(\.connectionID) == ["conn-2"])
    }
}
