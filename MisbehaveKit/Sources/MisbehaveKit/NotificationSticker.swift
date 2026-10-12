#if canImport(UIKit)
import UIKit
import UserNotifications

/// The little picture next to the notification text: the receiver's mascot with the points on it.
public enum NotificationSticker {
    public static func attachment(role: Role, delta: Int) -> UNNotificationAttachment? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sticker-\(UUID().uuidString).png")
        do {
            try image(role: role, delta: delta).pngData()?.write(to: url)
            return try UNNotificationAttachment(identifier: "sticker", url: url)
        } catch {
            return nil
        }
    }

    static func image(role: Role, delta: Int) -> UIImage {
        let side: CGFloat = 300
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let colors = [role.gradientStart, role.gradientEnd].map {
                UIColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: 1).cgColor
            }
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
            }

            UIColor.white.withAlphaComponent(0.28).setFill()
            UIBezierPath(ovalIn: CGRect(x: 35, y: 30, width: 230, height: 230)).fill()
            draw(role.emoji, size: 150, centeredAt: CGPoint(x: 150, y: 145))
            if let accent = role.accent(afterDelta: delta) {
                draw(accent, size: 64, centeredAt: CGPoint(x: 62, y: 62))
            }

            guard delta != 0 else { return }
            let label = NSAttributedString(string: PushText.signed(delta), attributes: [
                .font: roundedFont(size: 62),
                .foregroundColor: UIColor(red: role.gradientStart.red, green: role.gradientStart.green, blue: role.gradientStart.blue, alpha: 1),
            ])
            let labelSize = label.size()
            let badge = CGRect(x: side - max(labelSize.width + 44, 104) - 14, y: side - 104 - 14, width: max(labelSize.width + 44, 104), height: 104)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: badge, cornerRadius: 52).fill()
            label.draw(at: CGPoint(x: badge.midX - labelSize.width / 2, y: badge.midY - labelSize.height / 2))
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
