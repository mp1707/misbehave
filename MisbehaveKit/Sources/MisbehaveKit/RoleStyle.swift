import SwiftUI

extension Role {
    public var tint: Color {
        switch self {
        case .goodgirl: Color(red: 0.91, green: 0.22, blue: 0.47)
        case .goodboy: Color(red: 0.22, green: 0.42, blue: 0.93)
        }
    }

    public var gradient: LinearGradient {
        let end: Color = switch self {
        case .goodgirl: Color(red: 0.98, green: 0.47, blue: 0.38)
        case .goodboy: Color(red: 0.20, green: 0.70, blue: 0.86)
        }
        return LinearGradient(colors: [tint, end], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
