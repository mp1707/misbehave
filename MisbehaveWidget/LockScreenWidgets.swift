import MisbehaveKit
import SwiftUI
import WidgetKit

// Two more widgets for the lock screen, fed by the same timeline as "Your points".

/// Both scores of a connection in two lines: "2 You", "3 Puppy".
struct DuoWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "DuoWidget", intent: SelectConnectionIntent.self, provider: ScoreProvider()) { entry in
            LockScreenView(entry: entry) { DuoView(score: $0) }
        }
        .configurationDisplayName("Both scores")
        .description("Your points and your partner's, one line each.")
        .supportedFamilies([.accessoryRectangular])
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

    private var look: Look { score.look }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(points: score.score, name: Text("You"))
                .widgetAccentable()
            row(points: score.partnerScore, name: Text(verbatim: score.partner))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: String(localized: "You") + ": " + PushText.points(score.score, role: score.role) + ", "
            + score.partner + ": " + PushText.points(score.partnerScore, role: score.partnerRole)))
    }

    private func row(points: Int, name: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(points, format: .number)
                .font(look.font(.title2, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            name
                .font(look.font(.headline, weight: .semibold))
                .lineLimit(1)
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
