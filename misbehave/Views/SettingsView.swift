import MisbehaveKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var role: Role = .goodgirl
    @State private var confirmsDelete = false
    @State private var isDeleting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.givenName)
                    Picker("Role", selection: $role) {
                        ForEach(Role.allCases) { Text(verbatim: $0.label).tag($0) }
                    }
                } header: {
                    Text("You")
                } footer: {
                    Text("Your partners see the name. The role applies to connections you add from now on.")
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
                    LabeledContent("Version") { Text(verbatim: appVersion) }
                }

                Section {
                    Button("Delete all data", role: .destructive) { confirmsDelete = true }
                        .disabled(isDeleting)
                } footer: {
                    Text("Ends every connection and removes your profile and all points from this iPhone and from iCloud.")
                }
            }
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
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                paragraph("What is stored", "Your role, the name you entered and one entry for every point you give or take away. Nothing else.")
                paragraph("Where it is stored", "On your iPhone and in iCloud. Each connection lives in the iCloud account of the person who sent the invitation and is shared only with the one partner who accepted it.")
                paragraph("Who can see it", "You and the partner of that connection. The developer has no server and cannot see any of it. There is no tracking, no advertising and no analytics.")
                paragraph("How to delete it", "Disconnect removes one connection with all its points for both of you. \"Delete all data\" in Settings removes everything.")
            }
            .padding(20)
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func paragraph(_ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(text).foregroundStyle(.secondary)
        }
    }
}
