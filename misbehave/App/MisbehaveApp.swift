import SwiftUI

@main
struct MisbehaveApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AppModel.shared)
        }
    }
}
