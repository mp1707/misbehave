import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// How a connection or the app looks. A connection's look is shared by both partners and synced
// through CloudKit as JSON, so a new option never needs a schema change. Unknown values from a
// newer app version fall back to the default instead of breaking the whole look.

/// An enum stored by raw value that decodes unknown values as its default.
public protocol LookOption: RawRepresentable<String>, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    static var standard: Self { get }
    /// Shown in the editor; English only, like the rest of the app.
    var name: String { get }
}

extension LookOption {
    public var id: String { rawValue }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .standard
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: Colours

public enum Palette: String, LookOption {
    case bubblegum, peach, cherry, sunset, lemon, matcha, ocean, lavender, unicorn, midnight, cocoa

    public static let standard = Palette.bubblegum

    public var name: String {
        switch self {
        case .bubblegum: "Bubblegum"
        case .peach: "Peach"
        case .cherry: "Cherry"
        case .sunset: "Sunset"
        case .lemon: "Lemonade"
        case .matcha: "Matcha"
        case .ocean: "Lagoon"
        case .lavender: "Lavender"
        case .unicorn: "Unicorn"
        case .midnight: "Midnight"
        case .cocoa: "Cocoa"
        }
    }

    public var emoji: String {
        switch self {
        case .bubblegum: "🍬"
        case .peach: "🍑"
        case .cherry: "🍒"
        case .sunset: "🌅"
        case .lemon: "🍋"
        case .matcha: "🍵"
        case .ocean: "🌊"
        case .lavender: "💜"
        case .unicorn: "🦄"
        case .midnight: "🌙"
        case .cocoa: "🍫"
        }
    }

    /// The gradient of a person's card. Cat and dog get two close shades of the same colour.
    func stops(for role: Role) -> (start: RGB, end: RGB) {
        let girl = role == .goodgirl
        switch self {
        case .bubblegum: return girl ? (RGB(0.93, 0.29, 0.56), RGB(0.99, 0.53, 0.69)) : (RGB(0.91, 0.30, 0.43), RGB(0.99, 0.57, 0.53))
        case .peach: return girl ? (RGB(0.95, 0.43, 0.38), RGB(1.0, 0.68, 0.52)) : (RGB(0.93, 0.38, 0.30), RGB(1.0, 0.62, 0.40))
        case .cherry: return girl ? (RGB(0.78, 0.10, 0.25), RGB(0.95, 0.33, 0.42)) : (RGB(0.72, 0.08, 0.18), RGB(0.92, 0.28, 0.30))
        case .sunset: return girl ? (RGB(0.97, 0.42, 0.25), RGB(0.85, 0.25, 0.62)) : (RGB(0.98, 0.53, 0.20), RGB(0.88, 0.27, 0.45))
        case .lemon: return girl ? (RGB(0.90, 0.55, 0.05), RGB(0.97, 0.76, 0.22)) : (RGB(0.88, 0.50, 0.04), RGB(0.96, 0.70, 0.20))
        case .matcha: return girl ? (RGB(0.30, 0.58, 0.33), RGB(0.58, 0.78, 0.43)) : (RGB(0.24, 0.52, 0.38), RGB(0.50, 0.74, 0.48))
        case .ocean: return girl ? (RGB(0.07, 0.52, 0.72), RGB(0.30, 0.78, 0.84)) : (RGB(0.06, 0.42, 0.70), RGB(0.27, 0.70, 0.87))
        case .lavender: return girl ? (RGB(0.58, 0.38, 0.90), RGB(0.83, 0.58, 0.98)) : (RGB(0.50, 0.36, 0.88), RGB(0.73, 0.56, 0.98))
        case .unicorn: return girl ? (RGB(0.96, 0.45, 0.72), RGB(0.55, 0.62, 0.99)) : (RGB(0.68, 0.48, 0.98), RGB(0.38, 0.76, 0.93))
        case .midnight: return girl ? (RGB(0.20, 0.16, 0.45), RGB(0.55, 0.30, 0.75)) : (RGB(0.14, 0.18, 0.42), RGB(0.40, 0.30, 0.72))
        case .cocoa: return girl ? (RGB(0.45, 0.28, 0.22), RGB(0.73, 0.50, 0.38)) : (RGB(0.40, 0.25, 0.20), RGB(0.67, 0.45, 0.34))
        }
    }

    /// Hue of the paper behind everything, so cards, blush and ink match the gradient.
    private var paperHue: Double {
        switch self {
        case .bubblegum: 0.95
        case .peach: 0.04
        case .cherry: 0.98
        case .sunset: 0.03
        case .lemon: 0.12
        case .matcha: 0.30
        case .ocean: 0.53
        case .lavender: 0.75
        case .unicorn: 0.85
        case .midnight: 0.70
        case .cocoa: 0.06
        }
    }

    public func gradient(for role: Role) -> LinearGradient {
        let stops = stops(for: role)
        return LinearGradient(colors: [stops.start.color, stops.end.color], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public func tint(for role: Role) -> Color { stops(for: role).start.color }

    public var background: Color {
        self == .bubblegum ? Cozy.background : adaptive(light: hsb(0.05, 1.0), dark: hsb(0.33, 0.105))
    }

    public var card: Color {
        self == .bubblegum ? Cozy.card : adaptive(light: RGB(1, 1, 1), dark: hsb(0.30, 0.18))
    }

    public var blush: Color {
        self == .bubblegum ? Cozy.blush : adaptive(light: hsb(0.11, 1.0), dark: hsb(0.40, 0.28))
    }

    public var ink: Color {
        self == .bubblegum ? Cozy.ink : adaptive(light: hsb(0.50, 0.28), dark: hsb(0.07, 1.0))
    }

    public var shadow: Color {
        self == .bubblegum ? Cozy.shadow : hsb(0.70, 0.75).color.opacity(0.18)
    }

    private func hsb(_ saturation: Double, _ brightness: Double) -> RGB {
        RGB(hue: paperHue, saturation: saturation, brightness: brightness)
    }

    private func adaptive(light: RGB, dark: RGB) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark.uiColor : light.uiColor })
        #else
        light.color
        #endif
    }
}

// MARK: Background pattern

public enum Pattern: String, LookOption {
    case paws, hearts, stars, sparkles, flowers, leaves, clouds, moons, music, bubbles, plain

    public static let standard = Pattern.paws

    public var name: String {
        switch self {
        case .paws: "Paws"
        case .hearts: "Hearts"
        case .stars: "Stars"
        case .sparkles: "Glitter"
        case .flowers: "Flowers"
        case .leaves: "Leaves"
        case .clouds: "Clouds"
        case .moons: "Night sky"
        case .music: "Music"
        case .bubbles: "Bubbles"
        case .plain: "Plain"
        }
    }

    /// The SF Symbol scattered over cards and screens; nil for none.
    public var symbol: String? {
        switch self {
        case .paws: "pawprint.fill"
        case .hearts: "heart.fill"
        case .stars: "star.fill"
        case .sparkles: "sparkle"
        case .flowers: "camera.macro"
        case .leaves: "leaf.fill"
        case .clouds: "cloud.fill"
        case .moons: "moon.stars.fill"
        case .music: "music.note"
        case .bubbles: "circle.fill"
        case .plain: nil
        }
    }
}

// MARK: Type

public enum Typeface: String, LookOption {
    case rounded, classic, serif, mono, marker, chalk, notebook, handwriting, typewriter, futura, loveLetter

    public static let standard = Typeface.rounded

    public var name: String {
        switch self {
        case .rounded: "Rounded"
        case .classic: "Classic"
        case .serif: "Serif"
        case .mono: "Mono"
        case .marker: "Marker"
        case .chalk: "Chalk"
        case .notebook: "Notebook"
        case .handwriting: "Handwriting"
        case .typewriter: "Typewriter"
        case .futura: "Futura"
        case .loveLetter: "Love letter"
        }
    }

    /// For the system faces; custom families set none.
    public var design: Font.Design? {
        switch self {
        case .rounded: .rounded
        case .classic: .default
        case .serif: .serif
        case .mono: .monospaced
        default: nil
        }
    }

    /// A font family that ships with iOS.
    var family: String? {
        switch self {
        case .marker: "Marker Felt"
        case .chalk: "Chalkboard SE"
        case .notebook: "Noteworthy"
        case .handwriting: "Bradley Hand"
        case .typewriter: "American Typewriter"
        case .futura: "Futura"
        case .loveLetter: "Snell Roundhand"
        default: nil
        }
    }

    public func font(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        guard let family else { return .system(style, design: design, weight: weight) }
        #if canImport(UIKit)
        let font = Self.face(in: family, weight: weight, size: Self.pointSize(of: style))
        return Font(UIFontMetrics(forTextStyle: Self.uiStyle(style)).scaledFont(for: font))
        #else
        return .custom(family, size: Self.pointSize(of: style), relativeTo: style).weight(weight)
        #endif
    }

    public func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard let family else { return .system(size: size, weight: weight, design: design) }
        #if canImport(UIKit)
        return Font(Self.face(in: family, weight: weight, size: size))
        #else
        return .custom(family, size: size).weight(weight)
        #endif
    }

    #if canImport(UIKit)
    /// The face of the family closest to the weight. `Font.custom` wants a face name, not a family,
    /// and these families only have a few weights each.
    private static func face(in family: String, weight: Font.Weight, size: CGFloat) -> UIFont {
        let wanted = uiWeight(weight).rawValue
        let faces = UIFont.fontNames(forFamilyName: family).compactMap { UIFont(name: $0, size: size) }
        let best = faces.min { abs(weightOf($0) - wanted) < abs(weightOf($1) - wanted) }
        return best ?? .systemFont(ofSize: size, weight: uiWeight(weight))
    }

    private static func weightOf(_ font: UIFont) -> CGFloat {
        let traits = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
        let weight = (traits?[.weight] as? CGFloat) ?? 0
        // Italic faces only when nothing else is there.
        return font.fontDescriptor.symbolicTraits.contains(.traitItalic) ? weight + 0.5 : weight
    }

    private static func uiWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }

    private static func uiStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
    #endif

    private static func pointSize(of style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }
}

// MARK: What flies when points change

public enum Burst: String, LookOption {
    case hearts, sparkles, flowers, sweets, fire, party, kisses, space, pizza

    public static let standard = Burst.hearts

    public var name: String {
        switch self {
        case .hearts: "Hearts"
        case .sparkles: "Sparkles"
        case .flowers: "Flowers"
        case .sweets: "Sweets"
        case .fire: "On fire"
        case .party: "Party"
        case .kisses: "Kisses"
        case .space: "Space"
        case .pizza: "Snacks"
        }
    }

    /// Flies up when a score grows.
    public var up: [String] {
        switch self {
        case .hearts: ["💕", "💖", "✨", "🐾"]
        case .sparkles: ["✨", "⭐️", "🌟", "💫"]
        case .flowers: ["🌸", "🌷", "🌼", "💐"]
        case .sweets: ["🍓", "🧁", "🍬", "🍫"]
        case .fire: ["🔥", "💯", "⚡️"]
        case .party: ["🎉", "🎊", "🥳", "🎈"]
        case .kisses: ["💋", "😘", "💌"]
        case .space: ["🚀", "🪐", "⭐️", "👽"]
        case .pizza: ["🍕", "🍔", "🍟", "🌮"]
        }
    }

    /// Flies up when a score shrinks.
    public var down: [String] {
        switch self {
        case .hearts: ["💔", "💧"]
        case .sparkles: ["💨", "☁️"]
        case .flowers: ["🥀", "🍂"]
        case .sweets: ["🧂", "🥦"]
        case .fire: ["🧊", "💧"]
        case .party: ["😤", "💤"]
        case .kisses: ["🙄", "😒"]
        case .space: ["☄️", "🕳️"]
        case .pizza: ["🥦", "🧅"]
        }
    }

    /// Sits next to the mascot in the notification picture after a point: a treat.
    public func treat(for role: Role) -> String {
        switch self {
        case .hearts: role == .goodgirl ? "🐟" : "🦴"
        case .sparkles: "🌟"
        case .flowers: "💐"
        case .sweets: "🧁"
        case .fire: "🔥"
        case .party: "🎉"
        case .kisses: "💋"
        case .space: "🪐"
        case .pizza: "🍕"
        }
    }
}

// MARK: Look

/// Colours, background, type and celebration: everything the app and each connection can change.
public struct Look: Codable, Sendable, Hashable {
    public var palette: Palette
    public var pattern: Pattern
    public var typeface: Typeface
    public var burst: Burst

    public init(palette: Palette = .standard, pattern: Pattern = .standard, typeface: Typeface = .standard, burst: Burst = .standard) {
        self.palette = palette
        self.pattern = pattern
        self.typeface = typeface
        self.burst = burst
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        palette = (try? container.decodeIfPresent(Palette.self, forKey: .palette)) ?? .standard
        pattern = (try? container.decodeIfPresent(Pattern.self, forKey: .pattern)) ?? .standard
        typeface = (try? container.decodeIfPresent(Typeface.self, forKey: .typeface)) ?? .standard
        burst = (try? container.decodeIfPresent(Burst.self, forKey: .burst)) ?? .standard
    }

    public func gradient(for role: Role) -> LinearGradient { palette.gradient(for: role) }
    public func tint(for role: Role) -> Color { palette.tint(for: role) }
    public func font(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font { typeface.font(style, weight: weight) }
    public func font(size: CGFloat, weight: Font.Weight = .regular) -> Font { typeface.font(size: size, weight: weight) }
}

/// A connection's shared look plus the mascot each partner wears in it.
public struct ConnectionStyle: Codable, Sendable, Hashable {
    public var look: Look
    /// Emoji instead of the role's cat or dog; nil keeps the default.
    public var ownerMascot: String?
    public var participantMascot: String?
    /// Decides which of two versions wins when both partners changed something.
    public var updatedAt: Date

    public init(look: Look = Look(), ownerMascot: String? = nil, participantMascot: String? = nil, updatedAt: Date = .now) {
        self.look = look
        self.ownerMascot = ownerMascot
        self.participantMascot = participantMascot
        self.updatedAt = updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        look = (try? container.decodeIfPresent(Look.self, forKey: .look)) ?? Look()
        ownerMascot = try? container.decodeIfPresent(String.self, forKey: .ownerMascot)
        participantMascot = try? container.decodeIfPresent(String.self, forKey: .participantMascot)
        updatedAt = (try? container.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? .distantPast
    }

    public func mascot(of side: Side) -> String? {
        side == .owner ? ownerMascot : participantMascot
    }

    public mutating func setMascot(_ emoji: String?, of side: Side) {
        if side == .owner { ownerMascot = emoji } else { participantMascot = emoji }
    }

    /// The JSON stored in CloudKit.
    public func payload() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    public static func decode(payload: String) -> ConnectionStyle? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ConnectionStyle.self, from: Data(payload.utf8))
    }
}

/// Mascots to pick from. Any other single emoji works too.
public enum Mascots {
    public static let all = [
        "🐱", "🐶", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐸",
        "🐵", "🐧", "🐤", "🦄", "🐹", "🐭", "🐷", "🐮", "🐺", "🦝",
        "🦦", "🦥", "🐢", "🐙", "🦖", "🐳", "🦋", "🐝", "🐞", "🦔",
        "👻", "👽", "🤖", "😈", "😇", "👑", "🍑", "🌚", "🧁", "🌸",
    ]

    /// The first character of `text` if it is an emoji, else nil.
    public static func emoji(in text: String) -> String? {
        guard let first = text.trimmingCharacters(in: .whitespaces).first else { return nil }
        let scalars = first.unicodeScalars
        let isEmoji = scalars.contains { $0.properties.isEmojiPresentation }
            || (scalars.first?.properties.isEmoji == true && scalars.count > 1)
        return isEmoji ? String(first) : nil
    }
}

// MARK: Environment

extension EnvironmentValues {
    /// The look of whatever is on screen: the app's own, or a connection's inside it.
    @Entry public var look = Look()
}
