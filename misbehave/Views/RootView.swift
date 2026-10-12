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
        .fontDesign(.rounded)
        .animation(.default, value: model.state.profile == nil)
        .overlay {
            if model.isAcceptingInvite {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    VStack(spacing: 14) {
                        HStack(spacing: 6) {
                            MascotSticker(face: Role.goodgirl.emoji, size: 56).bobbing()
                            Text(verbatim: "💞").font(.title2)
                            MascotSticker(face: Role.goodboy.emoji, size: 56).bobbing(delay: 0.4)
                        }
                        ProgressView("Connecting…")
                    }
                    .ink()
                    .padding(28)
                    .softCard()
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
        .fullScreenCover(isPresented: Binding(get: { model.showsNotificationPrompt }, set: { _ in })) {
            NotificationPromptView()
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

/// Explains in one screen why notifications matter here, then hands over to the system prompt.
struct NotificationPromptView: View {
    @Environment(AppModel.self) private var model
    @State private var isAsking = false

    private var role: Role { model.state.profile?.role ?? .goodgirl }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            preview
                .padding(.bottom, 12)
            VStack(spacing: 20) {
                Text("Don't miss the moment")
                    .font(.largeTitle.weight(.heavy))
                Text("When your partner gives you a point, your iPhone tells you right away and the widget follows. Without notifications you only see it when you open the app.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .ink()
            Spacer()
            Button {
                isAsking = true
                Task {
                    await model.requestNotifications()
                    isAsking = false
                }
            } label: {
                if isAsking { ProgressView().tint(.white) } else { Text("Allow notifications") }
            }
            .buttonStyle(ProminentButtonStyle(role: role))
            .disabled(isAsking)
            Button("Later") { model.snoozeNotificationPrompt() }
                .font(.headline)
                .padding(.bottom, 8)
        }
        .padding(24)
        .background { CozyBackground() }
        .fontDesign(.rounded)
        .interactiveDismissDisabled()
    }

    /// What the notification will look like, so the system prompt that follows makes sense.
    private var preview: some View {
        HStack(spacing: 12) {
            Text(verbatim: role.face(afterDelta: 1))
                .font(.system(size: 30))
                .frame(width: 48, height: 48)
                .background(role.gradient, in: .rect(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: PushText.partnerFallback)
                    .font(.subheadline.weight(.bold))
                Text(verbatim: PushText.phrase(delta: 1, role: role))
                    .font(.footnote)
            }
            Spacer(minLength: 0)
        }
        .ink()
        .padding(14)
        .softCard(cornerRadius: 24)
        .overlay(alignment: .topTrailing) {
            Text(verbatim: "🔔")
                .font(.system(size: 38))
                .rotationEffect(.degrees(14))
                .offset(x: 6, y: -24)
                .bobbing()
        }
        .rotationEffect(.degrees(-2))
        .accessibilityHidden(true)
    }
}
