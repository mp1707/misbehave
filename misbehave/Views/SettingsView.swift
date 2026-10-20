import MisbehaveKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var role: Role = .goodgirl
    @State private var confirmsDelete = false
    @State private var isDeleting = false
    @State private var isCustomizing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MascotSticker(face: role.emoji, size: 96)
                        .hop(on: role)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
                .listSectionSpacing(8)

                Section {
                    TextField("Name", text: $name)
                        .textContentType(.givenName)
                    Picker("Role", selection: $role) {
                        ForEach(Role.allCases) { Text(verbatim: "\($0.emoji) \($0.label)").tag($0) }
                    }
                } header: {
                    Text("You")
                } footer: {
                    Text("Your partners see the name. The role applies to connections you add from now on.")
                }

                Section {
                    Button {
                        isCustomizing = true
                    } label: {
                        Label {
                            Text("Customize the app")
                        } icon: {
                            Image(systemName: "paintbrush.pointed.fill")
                        }
                    }
                } footer: {
                    Text("Colours, background, font and more for this iPhone. The app icon follows the colours. Each connection has its own look, set on its page.")
                }

                Section("Notifications") {
                    LabeledContent("Status") { Text(notificationStatusText) }
                    switch model.notificationStatus {
                    case .notDetermined:
                        Button("Allow notifications") { Task { await model.requestNotifications() } }
                    case .denied:
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    default:
                        EmptyView()
                    }
                }

                Section {
                    if !model.state.connections.contains(where: \.isDemo) {
                        Button("Add demo connection") {
                            save()
                            dismiss()
                            model.addDemoConnection()
                        }
                    }
                    NavigationLink("Privacy") { PrivacyView() }
                    NavigationLink("Diagnostics") { DiagnosticsView() }
                    LabeledContent("Version") { Text(verbatim: appVersion) }
                }

                Section {
                    Button("Delete all data", role: .destructive) { confirmsDelete = true }
                        .disabled(isDeleting)
                } footer: {
                    Text("Ends every connection and removes your profile and all points from this iPhone and from iCloud.")
                }
            }
            .cozyForm()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        save()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Delete all data?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) {
                    isDeleting = true
                    Task {
                        await model.deleteAllData()
                        dismiss()
                    }
                }
            } message: {
                Text("All connections end for you and your partners, and every point is deleted. This can't be undone.")
            }
            .onAppear {
                name = model.state.profile?.displayName ?? ""
                role = model.state.profile?.role ?? .goodgirl
            }
            .onChange(of: name) { _, new in
                if new.count > AppConfig.maxNameLength { name = String(new.prefix(AppConfig.maxNameLength)) }
            }
            .task { await model.refreshNotificationStatus() }
            .sheet(isPresented: $isCustomizing) { LookEditor(target: .app) }
        }
    }

    private func save() {
        model.updateProfile(role: role, name: name)
    }

    private var notificationStatusText: LocalizedStringKey {
        switch model.notificationStatus {
        case .authorized, .provisional, .ephemeral: "On"
        case .denied: "Off"
        default: "Not asked yet"
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "\(version) (\(build))"
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                paragraph("🗂️", "What is stored", "Your role, the name you entered, the names you give your partners and one entry for every point you give or take away, with its note. Nothing else.")
                paragraph("☁️", "Where it is stored", "On your iPhone and in iCloud. Each connection lives in the iCloud account of the person who sent the invitation and is shared only with the one partner who accepted it.")
                paragraph("👀", "Who can see it", "You and the partner of that connection. The developer has no server and cannot see any of it. There is no tracking, no advertising and no analytics.")
                paragraph("🧹", "How to delete it", "Disconnect removes one connection with all its points for both of you. \"Delete all data\" in Settings removes everything.")
            }
            .padding(16)
        }
        .background { CozyBackground() }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func paragraph(_ emoji: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            MascotSticker(face: emoji, size: 44)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary)
            }
        }
        .ink()
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(cornerRadius: 24)
    }
}

/// The facts needed to see why a push did or did not arrive, readable on each iPhone.
struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @State private var pushRun: PushRun?
    @State private var isChecking = false

    var body: some View {
        let diagnostics = model.diagnostics
        Form {
            Section {
                row("iCloud", ok: model.isCloudAvailable, value: model.isCloudAvailable ? String(localized: "Available") : String(localized: "Not available"))
                row("Notification permission", ok: notificationsAllowed, value: notificationsAllowed ? String(localized: "On") : String(localized: "Off"))
                row("Push registration", date: diagnostics.pushTokenAt, error: diagnostics.pushTokenError)
                row("Subscription, own invitations", date: diagnostics.privateSubscriptionAt, error: diagnostics.privateSubscriptionError)
                row("Subscription, accepted invitations", date: diagnostics.sharedSubscriptionAt, error: diagnostics.sharedSubscriptionError)
            } header: {
                Text("Setup")
            } footer: {
                Text("All five need a green check for notifications to arrive while the app is closed.")
            }

            Section {
                row("Last sync", date: diagnostics.lastSyncAt)
                row("Last background sync", date: diagnostics.lastBackgroundSyncAt)
                row("Last wake-up by push", date: diagnostics.lastWakeByPushAt)
                row(
                    "Last push processed",
                    date: pushRun?.date,
                    error: pushRun?.error,
                    detail: pushRun.map { String(localized: "\($0.newEvents) new, \($0.zonesFailed) failed") }
                )
                row("Last fallback notification", date: diagnostics.lastFallbackNotificationAt)
                row("Last point sent with its note", date: diagnostics.lastCommentSavedAt, error: diagnostics.commentError)
                row("Last look sent", date: diagnostics.lastStyleSavedAt, error: diagnostics.styleError)
            } header: {
                Text("What happened")
            } footer: {
                Text("Give a point from the other iPhone while this app is closed, then open this page. The times show how far the push got.")
            }

            Section {
                Button {
                    Task {
                        isChecking = true
                        await model.refreshAccountStatus()
                        await model.refreshNotificationStatus()
                        await model.ensureSubscriptionsIfNeeded(force: true)
                        pushRun = model.lastPushRun()
                        isChecking = false
                    }
                } label: {
                    if isChecking { ProgressView() } else { Text("Check again") }
                }
                .disabled(isChecking)
            }
        }
        .cozyForm()
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { pushRun = model.lastPushRun() }
    }

    private var notificationsAllowed: Bool {
        model.notificationStatus == .authorized || model.notificationStatus == .provisional
    }

    private func row(_ title: LocalizedStringKey, ok: Bool, value: String) -> some View {
        LabeledContent {
            Text(verbatim: value)
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(ok ? .green : .red)
            }
        }
    }

    private func row(_ title: LocalizedStringKey, date: Date?, error: String? = nil, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent {
                Text(verbatim: date.map { $0.formatted(date: .abbreviated, time: .standard) } ?? String(localized: "Never"))
            } label: {
                Label {
                    Text(title)
                } icon: {
                    if error != nil {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    } else if date != nil {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                    }
                }
            }
            if let detail {
                Text(verbatim: detail).font(.footnote).foregroundStyle(.secondary)
            }
            if let error {
                Text(verbatim: error).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
            }
        }
    }
}
