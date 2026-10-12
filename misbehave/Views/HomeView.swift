import MisbehaveKit
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showsAdd = false
    @State private var showsSettings = false

    private var role: Role { model.state.profile?.role ?? .goodgirl }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            ScrollView {
                VStack(spacing: 18) {
                    notices
                    if model.state.connections.isEmpty {
                        emptyState
                    } else {
                        ForEach(model.state.connections) { connection in
                            NavigationLink(value: connection.id) {
                                ConnectionCard(connection: connection)
                            }
                            .buttonStyle(SquishyButtonStyle())
                        }
                    }
                }
                .padding(16)
            }
            .background { CozyBackground() }
            .navigationTitle(Text(verbatim: "misbehave"))
            .navigationDestination(for: String.self) { ConnectionDetailView(connectionID: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape.fill") { showsSettings = true }
                        .tint(role.tint)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add connection", systemImage: "plus") { showsAdd = true }
                        .tint(role.tint)
                }
            }
            .sheet(isPresented: $showsAdd) { AddConnectionView() }
            .sheet(isPresented: $showsSettings) { SettingsView() }
            .alert(
                "Connection ended",
                isPresented: Binding(get: { model.state.notices.first != nil }, set: { _ in }),
                presenting: model.state.notices.first
            ) { notice in
                Button("OK") { model.dismissNotice(notice) }
            } message: { notice in
                if let name = notice.partnerName, !name.isEmpty {
                    Text("\(name) ended your connection. Its points are gone on both phones.")
                } else {
                    Text("Your partner ended a connection. Its points are gone on both phones.")
                }
            }
        }
    }

    @ViewBuilder private var notices: some View {
        if model.showsPushPrompt {
            NoticeCard(
                emoji: "🔔",
                title: "Know right away",
                message: "Allow notifications to hear about it the moment your partner gives or takes a point."
            ) {
                Button("Allow notifications") { Task { await model.requestNotifications() } }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        } else if model.showsPushDeniedHint {
            NoticeCard(
                emoji: "🔕",
                title: "Notifications are off",
                message: "You'll see new points when you open the app. You can turn notifications on in Settings."
            ) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                Button("Dismiss") { model.dismissPushDeniedHint() }
            }
        }
        if model.quotaExceeded {
            NoticeCard(
                emoji: "☁️",
                title: "iCloud storage is full",
                message: "New points stay on this iPhone until there's room in iCloud again."
            ) {}
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            HStack(spacing: 4) {
                MascotSticker(face: Role.goodgirl.emoji, size: 88)
                    .rotationEffect(.degrees(-8))
                    .bobbing()
                Text(verbatim: "💞")
                    .font(.system(size: 30))
                MascotSticker(face: Role.goodboy.emoji, size: 88)
                    .rotationEffect(.degrees(8))
                    .bobbing(delay: 0.5)
            }
            .padding(.top, 36)
            .accessibilityHidden(true)
            VStack(spacing: 16) {
                Text("No connection yet")
                    .font(.title2.weight(.heavy))
                Text("Invite your partner with a link, or look around with a demo partner first.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .ink()
            Button("Add connection") { showsAdd = true }
                .buttonStyle(ProminentButtonStyle(role: role))
                .padding(.top, 8)
            Button("Try the demo") { model.addDemoConnection() }
                .font(.headline)
                .padding(.top, 4)
        }
        .padding(.horizontal, 16)
    }
}

struct ConnectionCard: View {
    var connection: Connection

    private var mood: Mood { Mood(score: connection.myScore) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                if connection.phase == .active {
                    MascotSticker(face: connection.myRole.face(mood), size: 72, badge: mood.badge, onGradient: true)
                        .hop(on: connection.myScore)
                } else {
                    MascotSticker(face: "💌", size: 72, onGradient: true)
                        .bobbing()
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(verbatim: connection.phase == .active ? connection.partnerDisplayName : String(localized: "Invitation sent"))
                            .font(.headline)
                            .lineLimit(1)
                        if connection.isDemo {
                            Text("Demo")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.white.opacity(0.28), in: .capsule)
                        }
                    }
                    if connection.phase == .active {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(connection.myScore, format: .number)
                                .font(.system(size: 52, weight: .heavy, design: .rounded))
                                .contentTransition(.numericText(value: Double(connection.myScore)))
                            Group {
                                if abs(connection.myScore) == 1 {
                                    Text("\(connection.myRole.label) point")
                                } else {
                                    Text("\(connection.myRole.label) points")
                                }
                            }
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        }
                    } else {
                        Text("Waiting for your partner to open the link.")
                            .font(.subheadline)
                            .opacity(0.95)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.bold())
                    .opacity(0.7)
            }
            if connection.phase == .active, let partnerRole = connection.partnerRole {
                HStack(spacing: 8) {
                    Text(verbatim: partnerRole.emoji)
                    Text("\(connection.partnerDisplayName)'s \(partnerRole.label) points: \(connection.partnerScore)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.white.opacity(0.2), in: .capsule)
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gradientCard(connection.myRole)
        .animation(.snappy, value: connection.myScore)
        .accessibilityElement(children: .combine)
    }
}

struct NoticeCard<Actions: View>: View {
    var emoji: String
    var title: LocalizedStringKey
    var message: LocalizedStringKey
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            MascotSticker(face: emoji, size: 48)
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    Text(title)
                        .font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .ink()
                HStack(spacing: 16) { actions }
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(cornerRadius: 24)
    }
}
