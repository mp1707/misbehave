import MisbehaveKit
import SwiftUI

struct ConnectionDetailView: View {
    @Environment(AppModel.self) private var model
    var connectionID: String
    @State private var confirmsDisconnect = false

    var body: some View {
        if let connection = model.connection(connectionID) {
            ScrollView {
                VStack(spacing: 16) {
                    switch connection.phase {
                    case .active: ActiveConnectionView(connection: connection)
                    case .inviting: PendingInvitationView(connection: connection)
                    }
                }
                .padding(16)
            }
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
        }
    }
}

private struct ActiveConnectionView: View {
    @Environment(AppModel.self) private var model
    var connection: Connection

    var body: some View {
        VStack(spacing: 6) {
            Text("Your \(connection.myRole.label) points")
                .font(.system(.headline, design: .rounded))
            Text(connection.myScore, format: .number)
                .font(.system(size: 96, weight: .heavy, design: .rounded))
                .contentTransition(.numericText(value: Double(connection.myScore)))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("given by \(connection.partnerDisplayName)")
                .font(.subheadline)
                .opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(connection.myRole.gradient, in: .rect(cornerRadius: 28))
        .animation(.snappy, value: connection.myScore)
        .sensoryFeedback(trigger: connection.myScore) { old, new in new > old ? .increase : .decrease }
        .accessibilityElement(children: .combine)

        VStack(spacing: 18) {
            VStack(spacing: 4) {
                if let partnerRole = connection.partnerRole {
                    Text("\(connection.partnerDisplayName)'s \(partnerRole.label) points")
                        .font(.system(.headline, design: .rounded))
                } else {
                    Text("\(connection.partnerDisplayName)'s points")
                        .font(.system(.headline, design: .rounded))
                }
                Text(connection.partnerScore, format: .number)
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .contentTransition(.numericText(value: Double(connection.partnerScore)))
                    .foregroundStyle(partnerTint)
            }
            HStack(spacing: 20) {
                PointButton(systemImage: "minus", label: "Take a point away", tint: partnerTint, filled: false) {
                    model.givePoint(-1, in: connection.id)
                }
                PointButton(systemImage: "plus", label: "Give a point", tint: partnerTint, filled: true) {
                    model.givePoint(1, in: connection.id)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 28))
        .animation(.snappy, value: connection.partnerScore)
        .sensoryFeedback(trigger: connection.partnerScore) { old, new in new > old ? .increase : .decrease }

        if connection.isDemo {
            footnote("The demo partner mirrors what you do. Nothing here leaves your iPhone.", systemImage: "wand.and.stars")
        } else if connection.hasUnsentEvents {
            footnote("Saved on this iPhone. Your partner gets it as soon as iCloud is reachable.", systemImage: "icloud.slash")
        }
    }

    private var partnerTint: Color {
        (connection.partnerRole ?? connection.myRole.opposite).tint
    }

    private func footnote(_ text: LocalizedStringKey, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

private struct PointButton: View {
    var systemImage: String
    var label: LocalizedStringKey
    var tint: Color
    var filled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(filled ? .white : tint)
                .frame(maxWidth: .infinity, minHeight: 72)
                .background(filled ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.15)), in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct PendingInvitationView: View {
    @Environment(AppModel.self) private var model
    var connection: Connection
    @State private var confirmsCancel = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "paperplane.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(connection.myRole.gradient)
                .padding(.top, 24)
            Text("Waiting for your partner")
                .font(.title2.bold())
            Text("The link works exactly once. As soon as your partner opens it on their iPhone, you're connected.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

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
