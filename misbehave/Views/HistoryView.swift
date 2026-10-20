import MisbehaveKit
import SwiftUI

/// Every point of a connection with its note, newest first, like a little chat:
/// what the partner gave on the left under their mascot, what this person gave on the right.
struct HistoryView: View {
    var connection: Connection

    private struct Day: Identifiable {
        var id: Date
        var events: [PointEvent]
    }

    private var days: [Day] {
        let calendar = Calendar.current
        let sorted = connection.events.sorted { $0.createdAt > $1.createdAt }
        var days: [Day] = []
        for event in sorted {
            let start = calendar.startOfDay(for: event.createdAt)
            if days.last?.id == start {
                days[days.count - 1].events.append(event)
            } else {
                days.append(Day(id: start, events: [event]))
            }
        }
        return days
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("History")
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .ink()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)

            if connection.events.isEmpty {
                Text("Every point lands here, together with why it was given.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .ink()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(days) { day in
                        DayLabel(date: day.id)
                            .padding(.top, 4)
                        ForEach(day.events) { event in
                            HistoryRow(event: event, connection: connection)
                        }
                    }
                }
            }
        }
    }
}

private struct DayLabel: View {
    var date: Date

    var body: some View {
        Group {
            if Calendar.current.isDateInToday(date) {
                Text("Today")
            } else if Calendar.current.isDateInYesterday(date) {
                Text("Yesterday")
            } else if Calendar.current.isDate(date, equalTo: .now, toGranularity: .year) {
                Text(date, format: .dateTime.weekday(.wide).day().month(.wide))
            } else {
                Text(date, format: .dateTime.day().month(.wide).year())
            }
        }
        .font(.caption.weight(.bold))
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Cozy.blush, in: .capsule)
        .ink()
    }
}

private struct HistoryRow: View {
    var event: PointEvent
    var connection: Connection

    private var received: Bool { event.from == connection.side.other }
    private var partnerRole: Role { connection.partnerRole ?? connection.myRole.opposite }
    /// Whose points these are: the bubble wears their colours.
    private var receiverRole: Role { received ? connection.myRole : partnerRole }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if received {
                MascotSticker(face: partnerRole.emoji, size: 34)
                bubble
                Spacer(minLength: 44)
            } else {
                Spacer(minLength: 44)
                bubble
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: PushText.signed(event.delta))
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .foregroundStyle(received ? AnyShapeStyle(receiverRole.tint) : AnyShapeStyle(.white))
                Text(verbatim: event.delta > 0 ? "💕" : "💔")
                    .font(.subheadline)
            }
            // Room for the time, which sits in the top corner however wide the note makes the bubble.
            .padding(.trailing, 64)
            if !event.comment.isEmpty {
                Text(verbatim: event.comment)
                    .font(.system(.body, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(received ? AnyShapeStyle(Cozy.ink) : AnyShapeStyle(.white))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 3) {
                if event.unsent {
                    Image(systemName: "clock")
                }
                Text(event.createdAt, format: .dateTime.hour().minute())
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(received ? AnyShapeStyle(Cozy.ink) : AnyShapeStyle(.white))
            .opacity(0.7)
            .padding(.top, 15)
            .padding(.trailing, 14)
        }
        .background {
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: 22,
                bottomLeadingRadius: received ? 6 : 22,
                bottomTrailingRadius: received ? 22 : 6,
                topTrailingRadius: 22
            )
            if received {
                shape.fill(Cozy.card).shadow(color: Cozy.shadow, radius: 8, y: 3)
            } else {
                shape.fill(receiverRole.gradient).shadow(color: Cozy.shadow.opacity(1.4), radius: 8, y: 3)
            }
        }
    }

    private var accessibilityText: Text {
        let points = PushText.signed(event.delta)
        let time = event.createdAt.formatted(date: .omitted, time: .shortened)
        let giver = received ? connection.partnerDisplayName : String(localized: "You")
        return Text(verbatim: "\(giver), \(points), \(event.comment), \(time)")
    }
}
