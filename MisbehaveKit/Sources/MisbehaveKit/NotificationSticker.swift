#if canImport(UIKit)
import UIKit
import UserNotifications

/// The little picture next to the notification text: the receiver's mascot with the points on it,
/// in the connection's colours. It is the only part of a notification an app can colour.
public enum NotificationSticker {
    public static func attachment(for summary: PointSummary) -> UNNotificationAttachment? {
        attachment(mascot: summary.mascot, role: summary.role, look: summary.look, delta: summary.delta)
    }

    public static func attachment(mascot: String, role: Role, look: Look, delta: Int) -> UNNotificationAttachment? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sticker-\(UUID().uuidString).png")
        do {
            try image(mascot: mascot, role: role, look: look, delta: delta).pngData()?.write(to: url)
            return try UNNotificationAttachment(identifier: "sticker", url: url)
        } catch {
            return nil
        }
    }

    static func image(mascot: String, role: Role, look: Look, delta: Int) -> UIImage {
        let side: CGFloat = 300
        let stops = look.palette.stops(for: role)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let colors = [stops.start.uiColor.cgColor, stops.end.uiColor.cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
            }
            drawPattern(look.pattern, in: side)

            UIColor.white.withAlphaComponent(0.28).setFill()
            UIBezierPath(ovalIn: CGRect(x: 35, y: 30, width: 230, height: 230)).fill()
            draw(mascot, size: 150, centeredAt: CGPoint(x: 150, y: 145))
            if delta != 0 {
                draw(delta < 0 ? "💔" : look.burst.treat(for: role), size: 64, centeredAt: CGPoint(x: 62, y: 62))
            }

            guard delta != 0 else { return }
            let label = NSAttributedString(string: PushText.signed(delta), attributes: [
                .font: roundedFont(size: 62),
                .foregroundColor: stops.start.uiColor,
            ])
            let labelSize = label.size()
            let badge = CGRect(x: side - max(labelSize.width + 44, 104) - 14, y: side - 104 - 14, width: max(labelSize.width + 44, 104), height: 104)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: badge, cornerRadius: 52).fill()
            label.draw(at: CGPoint(x: badge.midX - labelSize.width / 2, y: badge.midY - labelSize.height / 2))
        }
    }

    /// A few faint symbols in the corners, like on the cards in the app.
    private static func drawPattern(_ pattern: Pattern, in side: CGFloat) {
        guard let name = pattern.symbol else { return }
        let spots: [(CGFloat, CGFloat, CGFloat)] = [(0.12, 0.85, 44), (0.88, 0.14, 38), (0.86, 0.62, 30), (0.30, 0.10, 26)]
        for (x, y, size) in spots {
            let configuration = UIImage.SymbolConfiguration(pointSize: size, weight: .regular)
            guard let symbol = UIImage(systemName: name, withConfiguration: configuration)?
                .withTintColor(.white.withAlphaComponent(0.18), renderingMode: .alwaysOriginal) else { continue }
            symbol.draw(at: CGPoint(x: x * side - symbol.size.width / 2, y: y * side - symbol.size.height / 2))
        }
    }

    private static func draw(_ emoji: String, size: CGFloat, centeredAt center: CGPoint) {
        let text = NSAttributedString(string: emoji, attributes: [.font: UIFont.systemFont(ofSize: size)])
        let textSize = text.size()
        text.draw(at: CGPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2))
    }

    private static func roundedFont(size: CGFloat) -> UIFont {
        let font = UIFont.systemFont(ofSize: size, weight: .heavy)
        return font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? font
    }
}
#endif
