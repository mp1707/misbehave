import MisbehaveKit
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showsAdd = false
    @State private var showsSettings = false

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            ScrollView {
                VStack(spacing: 16) {
                    notices
                    if model.state.connections.isEmpty {
                        emptyState
                    } else {
                        ForEach(model.state.connections) { connection in
                            NavigationLink(value: connection.id) {
                                ConnectionCard(connection: connection)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle(Text(verbatim: "misbehave"))
            .navigationDestination(for: String.self) { ConnectionDetailView(connectionID: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { showsSettings = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add connection", systemImage: "plus") { showsAdd = true }
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
                systemImage: "bell.badge",
                title: "Know right away",
                message: "Allow notifications to hear about it the moment your partner gives or takes a point."
            ) {
                Button("Allow notifications") { Task { await model.requestNotifications() } }
                    .buttonStyle(.borderedProminent)
                Button("Not now") { model.dismissPushPrompt() }
            }
        } else if model.showsPushDeniedHint {
            NoticeCard(
                systemImage: "bell.slash",
                title: "Notifications are off",
                message: "You'll see new points when you open the app. You can turn notifications on in Settings."
            ) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                Button("Dismiss") { model.dismissPushDeniedHint() }
            }
        }
        if model.quotaExceeded {
            NoticeCard(
                systemImage: "exclamationmark.icloud",
                title: "iCloud storage is full",
                message: "New points stay on this iPhone until there's room in iCloud again."
            ) {}
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle((model.state.profile?.role ?? .goodgirl).gradient)
                .padding(.top, 40)
            Text("No connection yet")
                .font(.title2.bold())
            Text("Invite your partner with a link, or look around with a demo partner first.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add connection") { showsAdd = true }
                .buttonStyle(ProminentButtonStyle(role: model.state.profile?.role ?? .goodgirl))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(verbatim: connection.phase == .active ? connection.partnerDisplayName : String(localized: "Invitation sent"))
                    .font(.headline)
                if connection.isDemo {
                    Text("Demo")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.25), in: .capsule)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.bold())
                    .opacity(0.7)
            }
            if connection.phase == .active {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(connection.myScore, format: .number)
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .contentTransition(.numericText(value: Double(connection.myScore)))
                    Group {
                        if abs(connection.myScore) == 1 {
                            Text("\(connection.myRole.label) point")
                        } else {
                            Text("\(connection.myRole.label) points")
                        }
                    }
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                }
                if let partnerRole = connection.partnerRole {
                    Text("\(connection.partnerDisplayName)'s \(partnerRole.label) points: \(connection.partnerScore)")
                        .font(.subheadline)
                        .opacity(0.9)
                }
            } else {
                Text("Waiting for your partner to open the link.")
                    .font(.subheadline)
                    .opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(connection.myRole.gradient, in: .rect(cornerRadius: 24))
        .animation(.snappy, value: connection.myScore)
        .accessibilityElement(children: .combine)
    }
}

struct NoticeCard<Actions: View>: View {
    var systemImage: String
    var title: LocalizedStringKey
    var message: LocalizedStringKey
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) { actions }
                .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 20))
    }
}
