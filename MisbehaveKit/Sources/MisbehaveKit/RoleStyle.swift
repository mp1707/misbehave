import SwiftUI

/// Red, green and blue in 0...1, so SwiftUI and the UIKit drawing of the notification picture share one palette.
struct RGB: Sendable {
    var red: Double
    var green: Double
    var blue: Double

    init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    var color: Color { Color(red: red, green: green, blue: blue) }
}

extension Role {
    /// Girls are cats, boys are dogs.
    public var emoji: String { self == .goodgirl ? "🐱" : "🐶" }

    /// For places that cannot show colour, like the lock screen.
    public var symbolName: String { self == .goodgirl ? "cat.fill" : "dog.fill" }

    /// Everyone is pink: rose for the cat, a warmer strawberry for the dog.
    var gradientStart: RGB {
        switch self {
        case .goodgirl: RGB(0.93, 0.29, 0.56)
        case .goodboy: RGB(0.91, 0.30, 0.43)
        }
    }

    var gradientEnd: RGB {
        switch self {
        case .goodgirl: RGB(0.99, 0.53, 0.69)
        case .goodboy: RGB(0.99, 0.57, 0.53)
        }
    }

    public var tint: Color { gradientStart.color }

    public var gradient: LinearGradient {
        LinearGradient(colors: [gradientStart.color, gradientEnd.color], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The app's warm colours, shared with the widget.
public enum Cozy {
    /// Cream with a hint of pink behind every screen.
    public static let background = adaptive(light: RGB(1.0, 0.955, 0.945), dark: RGB(0.105, 0.07, 0.085))
    public static let card = adaptive(light: RGB(1.0, 1.0, 1.0), dark: RGB(0.18, 0.125, 0.15))
    public static let blush = adaptive(light: RGB(1.0, 0.895, 0.915), dark: RGB(0.28, 0.17, 0.21))
    /// Text: a soft plum instead of black.
    public static let ink = adaptive(light: RGB(0.29, 0.15, 0.22), dark: RGB(1.0, 0.93, 0.95))
    public static let shadow = Color(red: 0.80, green: 0.25, blue: 0.45).opacity(0.18)

    private static func adaptive(light: RGB, dark: RGB) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
        #else
        light.color
        #endif
    }
}

/// A few paw prints scattered over a card or a screen.
public struct PawPattern: View {
    private struct Paw {
        var x: Double
        var y: Double
        var scale: Double
        var angle: Double
    }

    private static let paws = [
        Paw(x: 0.08, y: 0.16, scale: 0.9, angle: -24),
        Paw(x: 0.36, y: 0.02, scale: 0.7, angle: 14),
        Paw(x: 0.70, y: 0.22, scale: 1.1, angle: 28),
        Paw(x: 0.97, y: 0.04, scale: 0.8, angle: -12),
        Paw(x: 0.22, y: 0.62, scale: 1.0, angle: 20),
        Paw(x: 0.52, y: 0.90, scale: 0.8, angle: -30),
        Paw(x: 0.90, y: 0.70, scale: 1.2, angle: -18),
        Paw(x: 0.02, y: 0.98, scale: 0.7, angle: 34),
    ]

    private var size: Double

    public init(size: Double = 30) {
        self.size = size
    }

    public var body: some View {
        GeometryReader { proxy in
            ForEach(Self.paws.indices, id: \.self) { index in
                let paw = Self.paws[index]
                Image(systemName: "pawprint.fill")
                    .font(.system(size: size * paw.scale))
                    .rotationEffect(.degrees(paw.angle))
                    .position(x: proxy.size.width * paw.x, y: proxy.size.height * paw.y)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
