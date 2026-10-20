import MisbehaveKit
import SwiftUI
import WidgetKit

// Two more widgets for the lock screen, fed by the same timeline as "Your points".

/// Both scores of a connection at a glance.
struct DuoWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "DuoWidget", intent: SelectConnectionIntent.self, provider: ScoreProvider()) { entry in
            LockScreenView(entry: entry) { DuoView(score: $0) }
        }
        .configurationDisplayName("Both scores")
        .description("Your points and your partner's, side by side.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular])
    }
}

/// Why the partner gave or took the last point.
struct NoteWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NoteWidget", intent: SelectConnectionIntent.self, provider: ScoreProvider()) { entry in
            LockScreenView(entry: entry) { NoteView(score: $0) }
        }
        .configurationDisplayName("Latest note")
        .description("Why your partner gave or took your last point.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

/// Shows `content` for a connection and leaves the empty states to the score widget's view.
private struct LockScreenView<Content: View>: View {
    var entry: ScoreEntry
    @ViewBuilder var content: (ScoreEntry.Score) -> Content

    var body: some View {
        if case .score(let score) = entry.content {
            content(score)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(AppConfig.connectionURL(id: score.id))
        } else {
            ScoreWidgetView(entry: entry)
        }
    }
}

private struct DuoView: View {
    var score: ScoreEntry.Score
    @Environment(\.widgetFamily) private var family

    private var look: Look { score.look }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Text(score.score, format: .number)
                        .font(look.font(size: 24, weight: .heavy))
                        .widgetAccentable()
                    Capsule()
                        .frame(width: 24, height: 2)
                        .opacity(0.6)
                    Text(score.partnerScore, format: .number)
                        .font(look.font(size: 15, weight: .bold))
                }
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(6)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: label))
        default:
            VStack(alignment: .leading, spacing: 2) {
                row(symbol: score.role.symbolName, name: Text("You"), points: score.score, role: score.role)
                    .widgetAccentable()
                row(symbol: score.partnerRole.symbolName, name: Text(verbatim: score.partner), points: score.partnerScore, role: score.partnerRole)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: label))
        }
    }

    private var label: String {
        String(localized: "You") + ": " + PushText.points(score.score, role: score.role) + ", "
            + score.partner + ": " + PushText.points(score.partnerScore, role: score.partnerRole)
    }

    private func row(symbol: String, name: Text, points: Int, role: Role) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .frame(width: 20)
            name
                .font(look.font(.headline, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(points, format: .number)
                .font(look.font(.title3, weight: .heavy))
        }
    }
}

private struct NoteView: View {
    var score: ScoreEntry.Score
    @Environment(\.widgetFamily) private var family

    private var look: Look { score.look }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label {
                if let note = score.note {
                    Text(verbatim: PushText.quoted(note))
                } else {
                    Text("No notes yet")
                }
            } icon: {
                Image(systemName: score.partnerRole.symbolName)
            }
        default:
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Image(systemName: score.partnerRole.symbolName)
                    Text(verbatim: score.partner)
                        .font(look.font(.headline, weight: .semibold))
                        .lineLimit(1)
                    if let delta = score.noteDelta {
                        Text(verbatim: PushText.signed(delta))
                            .font(look.font(.headline, weight: .heavy))
                            .fixedSize()
                    }
                }
                .widgetAccentable()
                if let note = score.note {
                    Text(verbatim: PushText.quoted(note))
                        .font(look.font(.body))
                        .lineLimit(2)
                } else {
                    Text("Every point comes with a note. The newest lands here.")
                        .font(look.font(.caption))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
