import MisbehaveKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        Group {
            if model.state.profile == nil {
                OnboardingView()
            } else {
                HomeView()
            }
        }
        .animation(.default, value: model.state.profile == nil)
        .overlay {
            if model.isAcceptingInvite {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    ProgressView("Connecting…")
                        .padding(24)
                        .background(.regularMaterial, in: .rect(cornerRadius: 16))
                }
            }
        }
        .alert(
            model.alert?.title ?? "",
            isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
            presenting: model.alert
        ) { _ in
            Button("OK") {}
        } message: { alert in
            Text(alert.message)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: model.sceneBecameActive()
            case .background: model.sceneLeftForeground()
            default: break
            }
        }
        .onOpenURL { model.open(url: $0) }
    }
}

/// A pill-shaped primary button in the role's colours.
struct ProminentButtonStyle: ButtonStyle {
    var role: Role

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(role.gradient, in: .capsule)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
