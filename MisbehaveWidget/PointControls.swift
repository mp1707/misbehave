import AppIntents
import MisbehaveKit
import SwiftUI
import WidgetKit

// Buttons for the lock screen corners and Control Center. A point always needs a note,
// so they open the app with the note sheet already up instead of sending a point blind.

struct PointControlIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Connection"

    @Parameter(title: "Connection")
    var connection: ConnectionEntity?
}

/// Opens the connection's page with the note sheet for +1 or −1.
struct OpenPointIntent: AppIntent {
    static let title: LocalizedStringResource = "Give or take a point"
    static let isDiscoverable = false

    @Parameter(title: "Connection")
    var connectionID: String

    @Parameter(title: "Points")
    var delta: Int

    init() {}

    init(connectionID: String, delta: Int) {
        self.connectionID = connectionID
        self.delta = delta
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        let url = AppConfig.pointURL(id: connectionID, delta: delta) ?? URL(string: "\(AppConfig.urlScheme)://")!
        return .result(opensIntent: OpenURLIntent(url))
    }
}

struct PointControlTarget: Sendable {
    var id: String
    var name: String
}

struct PointControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: PointControlIntent) -> PointControlTarget {
        PointControlTarget(id: configuration.connection?.id ?? "", name: configuration.connection?.name ?? PushText.partnerFallback)
    }

    func currentValue(configuration: PointControlIntent) async throws -> PointControlTarget {
        let active = LocalStore.shared.snapshot().connections.filter { $0.phase == .active }
        let connection = configuration.connection.flatMap { chosen in active.first { $0.id == chosen.id } } ?? active.first
        return PointControlTarget(id: connection?.id ?? "", name: connection?.partnerDisplayName ?? PushText.partnerFallback)
    }
}

struct GivePointControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "GivePointControl", provider: PointControlProvider()) { target in
            ControlWidgetButton(action: OpenPointIntent(connectionID: target.id, delta: 1)) {
                Label("+1 for \(target.name)", systemImage: "heart.fill")
            }
        }
        .displayName("Give a point")
        .description("Opens misbehave ready to give a point, note included.")
    }
}

struct TakePointControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "TakePointControl", provider: PointControlProvider()) { target in
            ControlWidgetButton(action: OpenPointIntent(connectionID: target.id, delta: -1)) {
                Label("\u{2212}1 for \(target.name)", systemImage: "heart.slash.fill")
            }
        }
        .displayName("Take a point")
        .description("Opens misbehave ready to take a point away, note included.")
    }
}
