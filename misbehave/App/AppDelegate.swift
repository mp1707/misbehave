import CloudKit
import MisbehaveKit
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // CloudKit's silent sync pushes need the registration even without notification permission.
        application.registerForRemoteNotifications()
        AppModel.shared.start()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        AppModel.shared.noteDiagnostics {
            $0.pushTokenAt = .now
            $0.pushTokenError = nil
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        AppModel.shared.noteDiagnostics { $0.pushTokenError = InboxRefresher.describe(error) }
    }

    /// The visible CloudKit push also carries `content-available`, so the app gets a moment
    /// in the background to sync and refresh the widget.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        await AppModel.shared.wokenByPush()
        return .newData
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // While the app is open the score changes on screen; only the demo shows what a push looks like.
        notification.request.identifier == AppModel.demoNotificationID ? [.banner, .sound] : []
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let id = response.notification.request.content.userInfo[AppConfig.connectionUserInfoKey] as? String
        await MainActor.run {
            if let id { AppModel.shared.open(connectionID: id) }
        }
    }
}

/// SwiftUI has no hook for accepted CloudKit shares, so a UIKit scene delegate receives them:
/// once when the link launches the app, once when the app is already running.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            AppModel.shared.handleIncomingShare(metadata)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        AppModel.shared.handleIncomingShare(cloudKitShareMetadata)
    }
}
