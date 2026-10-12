import MisbehaveKit
import SwiftUI

struct ConnectionDetailView: View {
    @Environment(AppModel.self) private var model
    var connectionID: String
    @State private var confirmsDisconnect = false

    var body: some View {
        if let connection = model.connection(connectionID) {
            ScrollView {
                VStack(spacing: 18) {
                    switch connection.phase {
                    case .active: ActiveConnectionView(connection: connection)
                    case .inviting: PendingInvitationView(connection: connection)
                    }
                }
                .padding(16)
            }
            .background { CozyBackground() }
            .navigationTitle(Text(verbatim: connection.phase == .active ? connection.partnerDisplayName : String(localized: "Invitation")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if connection.phase == .active {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("More", systemImage: "ellipsis.circle") {
                            Button(connection.isDemo ? "Remove demo" : "Disconnect", systemImage: "xmark.circle", role: .destructive) {
                                confirmsDisconnect = true
                            }
                        }
                    }
                }
            }
            .confirmationDialog(
                connection.isDemo ? "Remove the demo connection?" : "Disconnect from \(connection.partnerDisplayName)?",
                isPresented: $confirmsDisconnect,
                titleVisibility: .visible
            ) {
                Button(connection.isDemo ? "Remove demo" : "Disconnect", role: .destructive) {
                    model.disconnect(connection.id)
                }
            } message: {
                if !connection.isDemo {
                    Text("The points of this connection are deleted for both of you. Your other connections stay as they are.")
                }
            }
        } else {
            ContentUnavailableView("Connection ended", systemImage: "heart.slash")
                .background { CozyBackground() }
        }
    }
}

private struct ActiveConnectionView: View {
    @Environment(AppModel.self) private var model
    var connection: Connection

    private var myMood: Mood { Mood(score: connection.myScore) }
    private var partnerMood: Mood { Mood(score: connection.partnerScore) }
    private var partnerRole: Role { connection.partnerRole ?? connection.myRole.opposite }

    var body: some View {
        VStack(spacing: 4) {
            MascotSticker(face: connection.myRole.emoji, size: 96, badge: myMood.badge, onGradient: true)
                .hop(on: connection.myScore)
                .padding(.bottom, 6)
            Text("Your \(connection.myRole.label) points")
                .font(.system(.headline, design: .rounded, weight: .bold))
            Text(connection.myScore, format: .number)
                .font(.system(size: 96, weight: .heavy, design: .rounded))
                .contentTransition(.numericText(value: Double(connection.myScore)))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(verbatim: connection.myRole.moodLine(myMood))
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.white.opacity(0.22), in: .capsule)
                .contentTransition(.opacity)
            Text("given by \(connection.partnerDisplayName)")
                .font(.subheadline)
                .opacity(0.95)
                .padding(.top, 8)
        }
        .foregroundStyle(.white)
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .gradientCard(connection.myRole, cornerRadius: 34)
        .emojiBurst(on: connection.myScore, up: ["💕", "💖", "✨", "🐾"], down: ["💔", "💧"])
        .animation(.snappy, value: connection.myScore)
        .sensoryFeedback(trigger: connection.myScore) { old, new in new > old ? .increase : .decrease }
        .accessibilityElement(children: .combine)

        VStack(spacing: 18) {
            HStack(spacing: 14) {
                MascotSticker(face: partnerRole.emoji, size: 64, badge: partnerMood.badge)
                    .hop(on: connection.partnerScore)
                VStack(alignment: .leading, spacing: 2) {
                    if let partnerRole = connection.partnerRole {
                        Text("\(connection.partnerDisplayName)'s \(partnerRole.label) points")
                            .font(.headline)
                    } else {
                        Text("\(connection.partnerDisplayName)'s points")
                            .font(.headline)
                    }
                    Text(verbatim: partnerRole.moodLine(partnerMood))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
                Text(connection.partnerScore, format: .number)
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .contentTransition(.numericText(value: Double(connection.partnerScore)))
                    .foregroundStyle(partnerRole.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .ink()
            .accessibilityElement(children: .combine)
            HStack(spacing: 14) {
                PointButton(systemImage: "minus", label: "Take a point away", role: partnerRole, filled: false) {
                    model.givePoint(-1, in: connection.id)
                }
                PointButton(systemImage: "plus", label: "Give a point", role: partnerRole, filled: true) {
                    model.givePoint(1, in: connection.id)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .softCard(cornerRadius: 34)
        .emojiBurst(on: connection.partnerScore, up: ["💕", "💖", connection.partnerRole == .goodgirl ? "🐟" : "🦴"], down: ["💔", "💧"])
        .animation(.snappy, value: connection.partnerScore)
        .sensoryFeedback(trigger: connection.partnerScore) { old, new in new > old ? .increase : .decrease }

        if connection.isDemo {
            footnote("The demo partner mirrors what you do. Nothing here leaves your iPhone.", systemImage: "wand.and.stars")
        } else if connection.hasUnsentEvents {
            footnote("Saved on this iPhone. Your partner gets it as soon as iCloud is reachable.", systemImage: "icloud.slash")
        }
    }

    private func footnote(_ text: LocalizedStringKey, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .ink()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
    }
}

private struct PointButton: View {
    var systemImage: String
    var label: LocalizedStringKey
    var role: Role
    var filled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(filled ? .white : role.tint)
                .frame(maxWidth: .infinity, minHeight: 76)
                .background(filled ? AnyShapeStyle(role.gradient) : AnyShapeStyle(Cozy.blush), in: .rect(cornerRadius: 26))
                .shadow(color: filled ? Cozy.shadow.opacity(1.6) : .clear, radius: 10, y: 5)
        }
        .buttonStyle(SquishyButtonStyle())
        .accessibilityLabel(label)
    }
}

private struct PendingInvitationView: View {
    @Environment(AppModel.self) private var model
    var connection: Connection
    @State private var confirmsCancel = false

    var body: some View {
        VStack(spacing: 14) {
            MascotSticker(face: "💌", size: 104)
                .bobbing()
                .padding(.top, 24)
            VStack(spacing: 14) {
                Text("Waiting for your partner")
                    .font(.title2.weight(.heavy))
                Text("The link works exactly once. As soon as your partner opens it on their iPhone, you're connected.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .ink()

            if let url = connection.inviteURL {
                ShareLink(item: url, message: Text("Let's keep score. Open this on your iPhone to connect with me on misbehave.")) {
                    Label("Send the link again", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(ProminentButtonStyle(role: connection.myRole))
                .padding(.top, 8)
            } else {
                Text("The link was created on another device and can only be sent from there.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Cancel invitation", role: .destructive) { confirmsCancel = true }
                .padding(.top, 4)
        }
        .padding(.horizontal, 8)
        .confirmationDialog("Cancel this invitation?", isPresented: $confirmsCancel, titleVisibility: .visible) {
            Button("Cancel invitation", role: .destructive) { model.disconnect(connection.id) }
        } message: {
            Text("The link stops working.")
        }
    }
}
