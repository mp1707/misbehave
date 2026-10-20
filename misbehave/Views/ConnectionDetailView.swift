import MisbehaveKit
import SwiftUI

struct ConnectionDetailView: View {
    @Environment(AppModel.self) private var model
    var connectionID: String
    @State private var confirmsDisconnect = false
    @State private var isRenaming = false
    @State private var nickname = ""
    @State private var isCustomizing = false

    var body: some View {
        if let connection = model.connection(connectionID) {
            ScrollView {
                VStack(spacing: 18) {
                    switch connection.phase {
                    case .active:
                        ActiveConnectionView(connection: connection)
                        HistoryView(connection: connection)
                            .padding(.top, 8)
                    case .inviting: PendingInvitationView(connection: connection)
                    }
                }
                .padding(16)
            }
            .background { CozyBackground() }
            .themed(connection.look)
            .navigationTitle(Text(verbatim: connection.phase == .active ? connection.partnerDisplayName : String(localized: "Invitation")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if connection.phase == .active {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Customize", systemImage: "paintbrush.pointed.fill") { isCustomizing = true }
                            .tint(connection.look.tint(for: connection.myRole))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("More", systemImage: "ellipsis.circle") {
                            Button("Rename", systemImage: "pencil") {
                                nickname = connection.partnerNickname ?? ""
                                isRenaming = true
                            }
                            Button(connection.isDemo ? "Remove demo" : "Disconnect", systemImage: "xmark.circle", role: .destructive) {
                                confirmsDisconnect = true
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $isCustomizing) {
                LookEditor(target: .connection(connection.id))
            }
            .alert("Rename", isPresented: $isRenaming) {
                TextField(connection.partnerName ?? String(localized: "Name"), text: $nickname)
                Button("Save") { model.renamePartner(in: connection.id, to: nickname) }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let name = connection.partnerName, !name.isEmpty {
                    Text("What do you call \(name) here? Only you see this name. Leave it empty to use \(name).")
                } else {
                    Text("What do you call your partner here? Only you see this name.")
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
    /// The point waiting for its note.
    @State private var composing: Composing?

    private struct Composing: Identifiable {
        var delta: Int
        var id: Int { delta }
    }

    @Environment(\.look) private var look

    private var myMood: Mood { Mood(score: connection.myScore) }
    private var partnerMood: Mood { Mood(score: connection.partnerScore) }
    private var partnerRole: Role { connection.resolvedPartnerRole }

    var body: some View {
        VStack(spacing: 4) {
            MascotSticker(face: connection.myMascot, size: 96, badge: myMood.badge, onGradient: true)
                .hop(on: connection.myScore)
                .padding(.bottom, 6)
            Text("Your \(connection.myRole.label) points")
                .cozyFont(.headline, weight: .bold)
            Text(connection.myScore, format: .number)
                .cozyFont(size: 96, weight: .heavy)
                .contentTransition(.numericText(value: Double(connection.myScore)))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(verbatim: connection.myRole.moodLine(myMood))
                .cozyFont(.subheadline, weight: .bold)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.white.opacity(0.22), in: .capsule)
                .contentTransition(.opacity)
            Text("given by \(connection.partnerDisplayName)")
                .cozyFont(.subheadline)
                .opacity(0.95)
                .padding(.top, 8)
        }
        .foregroundStyle(.white)
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .gradientCard(connection.myRole, cornerRadius: 34)
        .emojiBurst(on: connection.myScore)
        .animation(.snappy, value: connection.myScore)
        .sensoryFeedback(trigger: connection.myScore) { old, new in new > old ? .increase : .decrease }
        .accessibilityElement(children: .combine)

        VStack(spacing: 18) {
            HStack(spacing: 14) {
                MascotSticker(face: connection.partnerMascot, size: 64, badge: partnerMood.badge)
                    .hop(on: connection.partnerScore)
                VStack(alignment: .leading, spacing: 2) {
                    if let partnerRole = connection.partnerRole {
                        Text("\(connection.partnerDisplayName)'s \(partnerRole.label) points")
                            .cozyFont(.headline, weight: .semibold)
                    } else {
                        Text("\(connection.partnerDisplayName)'s points")
                            .cozyFont(.headline, weight: .semibold)
                    }
                    Text(verbatim: partnerRole.moodLine(partnerMood))
                        .cozyFont(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
                Text(connection.partnerScore, format: .number)
                    .cozyFont(size: 46, weight: .heavy)
                    .contentTransition(.numericText(value: Double(connection.partnerScore)))
                    .foregroundStyle(look.tint(for: partnerRole))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .ink()
            .accessibilityElement(children: .combine)
            HStack(spacing: 14) {
                PointButton(systemImage: "minus", label: "Take a point away", role: partnerRole, filled: false) {
                    composing = Composing(delta: -1)
                }
                PointButton(systemImage: "plus", label: "Give a point", role: partnerRole, filled: true) {
                    composing = Composing(delta: 1)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .softCard(cornerRadius: 34)
        .emojiBurst(on: connection.partnerScore, extra: [look.burst.treat(for: partnerRole)])
        .animation(.snappy, value: connection.partnerScore)
        .sensoryFeedback(trigger: connection.partnerScore) { old, new in new > old ? .increase : .decrease }
        .sheet(item: $composing) { point in
            PointNoteSheet(delta: point.delta, partnerName: connection.partnerDisplayName, partnerRole: partnerRole, partnerMascot: connection.partnerMascot) { note in
                model.givePoint(point.delta, comment: note, in: connection.id)
            }
            .themed(look)
        }

        if connection.isDemo {
            footnote("The demo partner mirrors what you do. Nothing here leaves your iPhone.", systemImage: "wand.and.stars")
        } else if connection.hasUnsentEvents {
            footnote("Saved on this iPhone. Your partner gets it as soon as iCloud is reachable.", systemImage: "icloud.slash")
        }
    }

    private func footnote(_ text: LocalizedStringKey, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .cozyFont(.footnote)
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
    @Environment(\.look) private var look

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(filled ? .white : look.tint(for: role))
                .frame(maxWidth: .infinity, minHeight: 76)
                .background(filled ? AnyShapeStyle(look.gradient(for: role)) : AnyShapeStyle(look.palette.blush), in: .rect(cornerRadius: 26))
                .shadow(color: filled ? look.palette.shadow.opacity(1.6) : .clear, radius: 10, y: 5)
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
                    .cozyFont(.title2, weight: .heavy)
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
                    .cozyFont(.footnote)
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
