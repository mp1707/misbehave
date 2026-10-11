import AppIntents
import MisbehaveKit
import SwiftUI
import WidgetKit

// MARK: Choosing the connection

struct ConnectionEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Connection"
    static let defaultQuery = ConnectionQuery()

    var id: String
    var name: String
    var role: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: name),
            subtitle: LocalizedStringResource(stringLiteral: role)
        )
    }

    init(_ connection: Connection) {
        id = connection.id
        name = connection.partnerDisplayName
        role = connection.myRole.label
    }
}

struct ConnectionQuery: EntityQuery {
    private func connections() -> [Connection] {
        LocalStore.shared.snapshot().connections.filter { $0.phase == .active }
    }

    func entities(for identifiers: [String]) async throws -> [ConnectionEntity] {
        connections().filter { identifiers.contains($0.id) }.map(ConnectionEntity.init)
    }

    func suggestedEntities() async throws -> [ConnectionEntity] {
        connections().map(ConnectionEntity.init)
    }

    func defaultResult() async -> ConnectionEntity? {
        connections().first.map(ConnectionEntity.init)
    }
}

struct SelectConnectionIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Connection"
    static let description = IntentDescription("Choose whose points the widget shows.")

    @Parameter(title: "Connection")
    var connection: ConnectionEntity?
}

// MARK: Timeline

struct ScoreEntry: TimelineEntry {
    enum Content: Equatable {
        case score(id: String, partner: String, role: Role, score: Int)
        /// The app has no connection at all.
        case noConnection
        /// The widget was set up for a connection that has ended since.
        case disconnected
    }

    var date: Date
    var content: Content
}

struct ScoreProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ScoreEntry {
        ScoreEntry(date: .now, content: .score(id: "", partner: "Alex", role: .goodgirl, score: 12))
    }

    func snapshot(for configuration: SelectConnectionIntent, in context: Context) async -> ScoreEntry {
        let entry = entry(for: configuration)
        if context.isPreview, case .noConnection = entry.content { return placeholder(in: context) }
        return entry
    }

    func timeline(for configuration: SelectConnectionIntent, in context: Context) async -> Timeline<ScoreEntry> {
        // The app and the notification extension reload the widget when points change;
        // the periodic refresh only catches a reload that got lost.
        Timeline(entries: [entry(for: configuration)], policy: .after(.now.addingTimeInterval(30 * 60)))
    }

    private func entry(for configuration: SelectConnectionIntent) -> ScoreEntry {
        let active = LocalStore.shared.snapshot().connections.filter { $0.phase == .active }
        let connection: Connection?
        if let chosen = configuration.connection {
            connection = active.first { $0.id == chosen.id }
            if connection == nil { return ScoreEntry(date: .now, content: .disconnected) }
        } else {
            connection = active.first
        }
        guard let connection else { return ScoreEntry(date: .now, content: .noConnection) }
        return ScoreEntry(date: .now, content: .score(
            id: connection.id,
            partner: connection.partnerDisplayName,
            role: connection.myRole,
            score: connection.myScore
        ))
    }
}

// MARK: Views

struct ScoreWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    var entry: ScoreEntry

    var body: some View {
        content
            .containerBackground(for: .widget) { background }
            .widgetURL(url)
    }

    private var url: URL? {
        if case .score(let id, _, _, _) = entry.content { return AppConfig.connectionURL(id: id) }
        return nil
    }

    @ViewBuilder private var background: some View {
        if case .score(_, _, let role, _) = entry.content {
            role.gradient
        } else {
            Color(.secondarySystemBackground)
        }
    }

    /// White on the role's gradient; in the tinted and clear styles the system colours the text.
    private var foreground: Color {
        renderingMode == .fullColor && isScore ? .white : .primary
    }

    private var isScore: Bool {
        if case .score = entry.content { return true }
        return false
    }

    @ViewBuilder private var content: some View {
        switch entry.content {
        case .score(_, let partner, let role, let score):
            switch family {
            case .accessoryInline:
                Text(verbatim: "\(role.label) · \(score)")
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Text(score, format: .number)
                        .font(.system(.title2, design: .rounded, weight: .heavy))
                        .minimumScaleFactor(0.5)
                        .widgetAccentable()
                    Text(verbatim: role == .goodgirl ? "girl" : "boy")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(role.label) · \(score)"))
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: partner)
                        .font(.headline)
                        .widgetAccentable()
                    Text(verbatim: "\(role.label) · \(score)")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: partner)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .opacity(0.9)
                    Spacer(minLength: 0)
                    Text(score, format: .number)
                        .font(.system(size: 54, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .contentTransition(.numericText(value: Double(score)))
                        .widgetAccentable()
                    Text(verbatim: role.label)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                }
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(partner), \(role.label) · \(score)"))
            }
        case .noConnection:
            emptyState("heart.circle", "No connection", "Open misbehave to connect.")
        case .disconnected:
            emptyState("heart.slash", "Disconnected", "Hold to choose another connection.")
        }
    }

    @ViewBuilder
    private func emptyState(_ systemImage: String, _ title: LocalizedStringKey, _ hint: LocalizedStringKey) -> some View {
        switch family {
        case .accessoryInline:
            Text(title)
        case .accessoryCircular:
            Image(systemName: systemImage)
                .font(.title2)
                .accessibilityLabel(Text(title))
        case .accessoryRectangular:
            Label(title, systemImage: systemImage)
                .font(.headline)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title)
                    .widgetAccentable()
                Spacer(minLength: 0)
                Text(title)
                    .font(.headline)
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

struct ScoreWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: AppConfig.widgetKind, intent: SelectConnectionIntent.self, provider: ScoreProvider()) { entry in
            ScoreWidgetView(entry: entry)
        }
        .configurationDisplayName("Your points")
        .description("Shows your points from one connection.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct MisbehaveWidgetBundle: WidgetBundle {
    var body: some Widget {
        ScoreWidget()
    }
}
