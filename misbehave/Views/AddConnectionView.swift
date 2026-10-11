import MisbehaveKit
import os
import SwiftUI

struct AddConnectionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var isCreating = false
    @State private var created: Connection?
    @State private var failed = false

    private var role: Role { model.state.profile?.role ?? .goodgirl }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: created == nil ? "link.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(role.gradient)
                        .padding(.top, 24)
                        .contentTransition(.symbolEffect(.replace))

                    if let url = created?.inviteURL {
                        Text("Your link is ready")
                            .font(.title2.bold())
                        Text("Send it to your partner. It works exactly once, so nobody else can join with it.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        ShareLink(item: url, message: Text("Let's keep score. Open this on your iPhone to connect with me on misbehave.")) {
                            Label("Send invitation", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(ProminentButtonStyle(role: role))
                    } else {
                        Text("Invite your partner")
                            .font(.title2.bold())
                        VStack(alignment: .leading, spacing: 14) {
                            step("1.circle.fill", "Create a link and send it to your partner.")
                            step("2.circle.fill", "Your partner opens it on their iPhone with misbehave installed.")
                            step("3.circle.fill", "You're connected. This connection keeps its own score, separate from all others.")
                        }
                        Text("You'll be \(role.label) in this connection.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if !model.isCloudAvailable {
                            Label("Sign in to iCloud in the Settings app to connect with a partner.", systemImage: "icloud.slash")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if failed {
                            Label("That didn't work. Check your internet connection and iCloud, then try again.", systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                        Button {
                            Task { await create() }
                        } label: {
                            if isCreating { ProgressView().tint(.white) } else { Text("Create invitation link") }
                        }
                        .buttonStyle(ProminentButtonStyle(role: role))
                        .disabled(isCreating || !model.isCloudAvailable)
                        .opacity(model.isCloudAvailable ? 1 : 0.4)

                        if !model.state.connections.contains(where: \.isDemo) {
                            Button("Try the demo instead") {
                                dismiss()
                                model.addDemoConnection()
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .navigationTitle("New connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: created == nil ? .cancellationAction : .confirmationAction) {
                    Button(created == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
            .interactiveDismissDisabled(isCreating)
        }
    }

    private func step(_ systemImage: String, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(role.tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func create() async {
        isCreating = true
        failed = false
        defer { isCreating = false }
        do {
            created = try await model.createInvitation()
        } catch {
            Logger(subsystem: "com.mp17.mpapps.misbehave", category: "linking")
                .error("Creating the invitation failed: \(String(describing: error), privacy: .public)")
            failed = true
        }
    }
}
