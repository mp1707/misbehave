import MisbehaveKit
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var role: Role?
    @State private var name = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 10) {
                    HStack(spacing: 4) {
                        MascotSticker(face: Role.goodgirl.emoji, size: 84)
                            .rotationEffect(.degrees(-8))
                            .bobbing()
                        Text(verbatim: "💞")
                            .font(.system(size: 30))
                        MascotSticker(face: Role.goodboy.emoji, size: 84)
                            .rotationEffect(.degrees(8))
                            .bobbing(delay: 0.5)
                    }
                    .accessibilityHidden(true)
                    Text(verbatim: "misbehave")
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .foregroundStyle(Role.goodgirl.gradient)
                    Text("Give each other points. Take them away again.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Which one are you?")
                        .font(.headline)
                    HStack(spacing: 14) {
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
                        .padding(.horizontal, 18)
                        .padding(.vertical, 15)
                        .softCard(cornerRadius: 20)
                    Text("Your partner sees this name.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .ink()
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { CozyBackground() }
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
            VStack(spacing: 8) {
                MascotSticker(face: role.emoji, size: 78, onGradient: isSelected)
                    .hop(on: isSelected)
                Text(verbatim: role.label)
                    .font(.system(.title3, design: .rounded, weight: .heavy))
            }
            .foregroundStyle(isSelected ? .white : role.tint)
            .frame(maxWidth: .infinity, minHeight: 150)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(role.gradient)
                        .shadow(color: Cozy.shadow.opacity(1.8), radius: 14, y: 7)
                } else {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Cozy.card)
                        .shadow(color: Cozy.shadow, radius: 12, y: 5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(12)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(isSelected ? 1.03 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.5), value: isSelected)
        }
        .buttonStyle(SquishyButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}
