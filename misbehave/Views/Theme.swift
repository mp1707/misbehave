import MisbehaveKit
import SwiftUI
import UIKit

// The look shared by every screen: cream paper, pink cards, round type, mascots as stickers.

/// Cream with faint paw prints behind a whole screen.
struct CozyBackground: View {
    var body: some View {
        Cozy.background
            .overlay { PawPattern(size: 46).foregroundStyle(Cozy.blush.opacity(0.7)) }
            .ignoresSafeArea()
    }
}

extension View {
    /// Plum instead of black for text on cream. Not for containers with plain buttons: it would take their tint.
    func ink() -> some View {
        foregroundStyle(Cozy.ink)
    }

    /// A white card that floats a little above the cream.
    func softCard(cornerRadius: CGFloat = 28) -> some View {
        background(Cozy.card, in: .rect(cornerRadius: cornerRadius))
            .shadow(color: Cozy.shadow, radius: 14, y: 6)
    }

    /// The role's pink gradient with paw prints, for the cards that carry a score.
    func gradientCard(_ role: Role, cornerRadius: CGFloat = 30) -> some View {
        background {
            role.gradient
                .overlay { PawPattern().foregroundStyle(.white.opacity(0.14)) }
                .clipShape(.rect(cornerRadius: cornerRadius))
                .shadow(color: Cozy.shadow.opacity(1.6), radius: 16, y: 8)
        }
    }

    /// A grouped list on cream instead of grey.
    func cozyForm() -> some View {
        scrollContentBackground(.hidden).background { CozyBackground() }
    }

    /// A happy little hop whenever `trigger` changes.
    func hop<T: Equatable>(on trigger: T) -> some View {
        phaseAnimator([false, true], trigger: trigger) { content, lifted in
            content
                .scaleEffect(lifted ? 1.22 : 1)
                .rotationEffect(.degrees(lifted ? -10 : 0))
        } animation: { _ in
            .spring(duration: 0.28, bounce: 0.55)
        }
    }

    /// Floats gently up and down, forever.
    func bobbing(delay: Double = 0) -> some View {
        modifier(Bobbing(delay: delay))
    }

    /// Emoji fly up from the view when `value` changes: `up` when it grew, `down` when it shrank.
    func emojiBurst(on value: Int, up: [String], down: [String]) -> some View {
        modifier(EmojiBurst(value: value, up: up, down: down))
    }
}

/// A mascot (or any emoji) as a round sticker, with an optional small badge on its shoulder.
struct MascotSticker: View {
    var face: String
    var size: CGFloat = 64
    var badge: String?
    /// Frosted instead of blush, for sitting on a gradient.
    var onGradient = false

    var body: some View {
        Text(verbatim: face)
            .font(.system(size: size * 0.58))
            .frame(width: size, height: size)
            .background(onGradient ? AnyShapeStyle(.white.opacity(0.28)) : AnyShapeStyle(Cozy.blush), in: .circle)
            .overlay(alignment: .bottomTrailing) {
                if let badge {
                    Text(verbatim: badge)
                        .font(.system(size: size * 0.3))
                        .offset(x: size * 0.08, y: size * 0.04)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .accessibilityHidden(true)
    }
}

/// A pill-shaped primary button in the role's colours.
struct ProminentButtonStyle: ButtonStyle {
    var role: Role

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(role.gradient, in: .capsule)
            .shadow(color: Cozy.shadow.opacity(1.6), radius: 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.5), value: configuration.isPressed)
    }
}

/// Gives way under the finger like a marshmallow.
struct SquishyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.6), value: configuration.isPressed)
    }
}

private struct Bobbing: ViewModifier {
    var delay: Double
    @State private var isUp = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(y: isUp ? -4 : 3)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true).delay(delay)) { isUp = true }
            }
    }
}

private struct EmojiBurst: ViewModifier {
    struct Particle: Identifiable {
        let id = UUID()
        var emoji: String
        var x = Double.random(in: -110...110)
        var rise = Double.random(in: 80...170)
        var size = Double.random(in: 20...34)
        var spin = Double.random(in: -30...30)
    }

    var value: Int
    var up: [String]
    var down: [String]
    @State private var particles: [Particle] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    ForEach(particles) { FloatingEmoji(particle: $0) }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .onChange(of: value) { old, new in
                guard !reduceMotion else { return }
                let emoji = new > old ? up : down
                let fresh = (0..<7).compactMap { _ in emoji.randomElement().map { Particle(emoji: $0) } }
                particles.append(contentsOf: fresh)
                let ids = Set(fresh.map(\.id))
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    particles.removeAll { ids.contains($0.id) }
                }
            }
    }
}

private struct FloatingEmoji: View {
    var particle: EmojiBurst.Particle
    @State private var hasFlown = false
    @State private var hasFaded = false

    var body: some View {
        Text(verbatim: particle.emoji)
            .font(.system(size: particle.size))
            .rotationEffect(.degrees(hasFlown ? particle.spin : 0))
            .scaleEffect(hasFlown ? 1.15 : 0.3)
            .offset(x: hasFlown ? particle.x : particle.x * 0.15, y: hasFlown ? -particle.rise : 0)
            .opacity(hasFaded ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1.2)) { hasFlown = true }
                withAnimation(.easeIn(duration: 0.5).delay(0.8)) { hasFaded = true }
            }
    }
}

enum CozyAppearance {
    /// Navigation titles are drawn by UIKit and need the round type and the ink separately.
    @MainActor static func apply() {
        let ink = UIColor(Cozy.ink)
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: rounded(.largeTitle, weight: .heavy), .foregroundColor: ink]
        bar.titleTextAttributes = [.font: rounded(.headline, weight: .bold), .foregroundColor: ink]
    }

    private static func rounded(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let size = UIFont.preferredFont(forTextStyle: style).pointSize
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        return font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? font
    }
}
