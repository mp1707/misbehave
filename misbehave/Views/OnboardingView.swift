import MisbehaveKit
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var role: Role?
    @State private var name = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text(verbatim: "misbehave")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                    Text("Give each other points. Take them away again.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 48)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Which one are you?")
                        .font(.headline)
                    HStack(spacing: 12) {
                        ForEach(Role.allCases) { option in
                            RoleCard(role: option, isSelected: role == option) { role = option }
                        }
                    }
                    Text("This is what your points are called. You can change it later.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your name (optional)")
                        .font(.headline)
                    TextField("Name", text: $name)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                        .padding(14)
                        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
                    Text("Your partner sees this name.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button("Continue") {
                if let role { model.completeOnboarding(role: role, name: name) }
            }
            .buttonStyle(ProminentButtonStyle(role: role ?? .goodgirl))
            .disabled(role == nil)
            .opacity(role == nil ? 0.4 : 1)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .onChange(of: name) { _, new in
            if new.count > AppConfig.maxNameLength { name = String(new.prefix(AppConfig.maxNameLength)) }
        }
    }
}

struct RoleCard: View {
    var role: Role
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                Text(verbatim: role.label)
                    .font(.system(.title3, design: .rounded, weight: .bold))
            }
            .foregroundStyle(isSelected ? .white : role.tint)
            .frame(maxWidth: .infinity, minHeight: 110)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 20).fill(role.gradient)
                } else {
                    RoundedRectangle(cornerRadius: 20).fill(role.tint.opacity(0.12))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}
