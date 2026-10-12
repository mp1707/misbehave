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
    var symbolName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: name),
            subtitle: LocalizedStringResource(stringLiteral: role),
            image: .init(systemName: symbolName)
        )
    }

    init(_ connection: Connection) {
        id = connection.id
        name = connection.partnerDisplayName
        role = connection.myRole.label
        symbolName = connection.myRole.symbolName
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
    struct Score: Equatable {
        var id: String
        var partner: String
        var role: Role
        var score: Int
        var partnerRole: Role
        var partnerScore: Int

        var mood: Mood { Mood(score: score) }
        var partnerMood: Mood { Mood(score: partnerScore) }
    }

    enum Content: Equatable {
        case score(Score)
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
        ScoreEntry(date: .now, content: .score(.init(id: "", partner: "Alex", role: .goodgirl, score: 12, partnerRole: .goodboy, partnerScore: 8)))
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
        return ScoreEntry(date: .now, content: .score(.init(
            id: connection.id,
            partner: connection.partnerDisplayName,
            role: connection.myRole,
            score: connection.myScore,
            partnerRole: connection.partnerRole ?? connection.myRole.opposite,
            partnerScore: connection.partnerScore
        )))
    }
}

// MARK: Views

struct ScoreWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    var entry: ScoreEntry

    var body: some View {
        content
            .fontDesign(.rounded)
            .containerBackground(for: .widget) { background }
            .widgetURL(url)
    }

    private var url: URL? {
        if case .score(let score) = entry.content { return AppConfig.connectionURL(id: score.id) }
        return nil
    }

    @ViewBuilder private var background: some View {
        if case .score(let score) = entry.content {
            score.role.gradient
                .overlay { PawPattern(size: 24).foregroundStyle(.white.opacity(0.14)) }
        } else {
            Cozy.background
                .overlay { PawPattern(size: 24).foregroundStyle(Cozy.blush) }
        }
    }

    /// White on the role's gradient; in the tinted and clear styles the system colours the text.
    private var foreground: Color {
        renderingMode == .fullColor ? .white : .primary
    }

    @ViewBuilder private var content: some View {
        switch entry.content {
        case .score(let score):
            switch family {
            case .accessoryInline:
                Label {
                    Text(verbatim: "\(score.role.label) · \(score.score)")
                } icon: {
                    Image(systemName: score.role.symbolName)
                }
            case .accessoryCircular:
                VStack(spacing: -1) {
                    Image(systemName: score.role.symbolName)
                        .font(.system(size: 13))
                    Text(score.score, format: .number)
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .minimumScaleFactor(0.5)
                        .widgetAccentable()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(score.role.label) · \(score.score)"))
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: score.role.symbolName)
                        .font(.title2)
                        .widgetAccentable()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: score.partner)
                            .font(.headline)
                            .widgetAccentable()
                        Text(verbatim: "\(score.role.label) · \(score.score)")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .systemMedium:
                HStack(spacing: 4) {
                    half(face: score.role.emoji, badge: score.mood.badge, score: score.score, role: score.role, name: Text("You"))
                    Text(verbatim: "💞")
                        .font(.system(size: 22))
                    half(face: score.partnerRole.emoji, badge: score.partnerMood.badge, score: score.partnerScore, role: score.partnerRole, name: Text(verbatim: score.partner))
                }
                .foregroundStyle(foreground)
            default:
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 4) {
                        Text(verbatim: score.partner)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(2)
                            .opacity(0.95)
                        Spacer(minLength: 0)
                        sticker(score.role.emoji, badge: score.mood.badge, size: 46)
                    }
                    Spacer(minLength: 0)
                    Text(score.score, format: .number)
                        .font(.system(size: 50, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .contentTransition(.numericText(value: Double(score.score)))
                        .widgetAccentable()
                    Text(verbatim: score.role.label)
                        .font(.system(.subheadline, design: .rounded).weight(.heavy))
                }
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(score.partner), \(score.role.label) · \(score.score)"))
            }
        case .noConnection:
            emptyState("🐾", "pawprint.fill", "No connection", "Open misbehave to connect.")
        case .disconnected:
            emptyState("💤", "heart.slash", "Disconnected", "Hold to choose another connection.")
        }
    }

    /// One person in the wide widget: mascot, score, what the points are called and whose they are.
    private func half(face: String, badge: String?, score: Int, role: Role, name: Text) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                sticker(face, badge: badge, size: 50)
                Text(score, format: .number)
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .contentTransition(.numericText(value: Double(score)))
                    .widgetAccentable()
            }
            Text(verbatim: role.label)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .padding(.top, 8)
            name
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .opacity(0.9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func sticker(_ face: String, badge: String?, size: CGFloat) -> some View {
        Text(verbatim: face)
            .font(.system(size: size * 0.62))
            .frame(width: size, height: size)
            .background(.white.opacity(0.28), in: .circle)
            .overlay(alignment: .bottomTrailing) {
                if let badge {
                    Text(verbatim: badge)
                        .font(.system(size: size * 0.32))
                        .offset(x: size * 0.1, y: size * 0.06)
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func emptyState(_ emoji: String, _ systemImage: String, _ title: LocalizedStringKey, _ hint: LocalizedStringKey) -> some View {
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
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: emoji)
                    .font(.system(size: 28))
                    .frame(width: 46, height: 46)
                    .background(Cozy.blush, in: .circle)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                Text(title)
                    .font(.headline.weight(.heavy))
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(Cozy.ink)
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
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct MisbehaveWidgetBundle: WidgetBundle {
    var body: some Widget {
        ScoreWidget()
    }
}
