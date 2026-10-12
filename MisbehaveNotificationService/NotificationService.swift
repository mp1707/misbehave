import CloudKit
import MisbehaveKit
import UserNotifications
import WidgetKit

/// Turns CloudKit's neutral push ("You have new points") into the real message.
///
/// The push only says that something changed in one of the two databases. The extension fetches
/// the new entries itself, files them where the widget can read them, and rewrites the text to
/// e.g. "You received +1 goodgirl point 😻" with the partner's name as title and the mascot as picture.
/// If anything fails or takes too long, the neutral text is delivered as it came.
final class NotificationService: UNNotificationServiceExtension {
    private static let refresher = InboxRefresher()

    private var delivery: Delivery?
    private var work: Task<Void, Never>?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let content = (request.content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
        let delivery = Delivery(content: content, handler: contentHandler)
        self.delivery = delivery

        // Private database: we own the zone. Shared database: we were invited.
        let scope = (CKNotification(fromRemoteNotificationDictionary: request.content.userInfo) as? CKDatabaseNotification)?.databaseScope
        let side = scope.flatMap(CloudSchema.side(for:))

        work = Task {
            let outcome = await Self.refresher.refresh(side: side)
            WidgetCenter.shared.reloadAllTimelines()
            let summaries = outcome.snapshot.unseenSummaries(side: side, alsoCounting: outcome.newEventIDs)
            delivery.finish { content in
                guard let text = PushText.content(for: summaries) else { return }
                if let title = text.title { content.title = title }
                content.body = text.body
                content.threadIdentifier = "points"
                if summaries.count == 1 {
                    content.userInfo[AppConfig.connectionUserInfoKey] = summaries[0].connectionID
                    if let sticker = NotificationSticker.attachment(role: summaries[0].role, delta: summaries[0].delta) {
                        content.attachments = [sticker]
                    }
                }
            }
        }
    }

    override func serviceExtensionTimeWillExpire() {
        work?.cancel()
        delivery?.finish { _ in }
    }
}

/// Hands the notification to the system exactly once, from whichever thread gets there first.
private final class Delivery: @unchecked Sendable {
    private let lock = NSLock()
    private let content: UNMutableNotificationContent
    private var handler: ((UNNotificationContent) -> Void)?

    init(content: UNMutableNotificationContent, handler: @escaping (UNNotificationContent) -> Void) {
        self.content = content
        self.handler = handler
    }

    func finish(_ edit: (UNMutableNotificationContent) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard let handler else { return }
        self.handler = nil
        edit(content)
        handler(content)
    }
}
