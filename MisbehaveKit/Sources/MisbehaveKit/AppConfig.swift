import Foundation

/// Identifiers shared by the app, the widget and the notification extension.
public enum AppConfig {
    public static let appGroupID = "group.com.mp17.mpapps.misbehave"
    public static let cloudContainerID = "iCloud.com.mp17.mpapps.misbehave"
    public static let widgetKind = "ScoreWidget"
    public static let urlScheme = "misbehave"
    /// `userInfo` key the notification extension sets when a push belongs to exactly one connection.
    public static let connectionUserInfoKey = "connectionID"
    public static let maxNameLength = 40
    public static let maxCommentLength = 160

    public static func connectionURL(id: String) -> URL? {
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = "connection"
        components.path = "/" + id
        return components.url
    }

    /// Opens a connection with the note sheet for a point already up; used by the lock screen controls.
    public static func pointURL(id: String, delta: Int) -> URL? {
        guard var components = connectionURL(id: id).flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else { return nil }
        components.queryItems = [URLQueryItem(name: "point", value: delta < 0 ? "minus" : "plus")]
        return components.url
    }

    /// +1 or −1 when the link asks for a point, else nil.
    public static func pointRequest(from url: URL) -> Int? {
        let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "point" }?.value
        switch value {
        case "plus": return 1
        case "minus": return -1
        default: return nil
        }
    }

    public static func connectionID(from url: URL) -> String? {
        guard url.scheme == urlScheme, url.host() == "connection" else { return nil }
        let id = url.lastPathComponent
        return id.isEmpty || id == "/" ? nil : id
    }

    public static func cleanName(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maxNameLength))
    }

    /// One line, trimmed and capped, so a note always fits a notification and a history bubble.
    public static func cleanComment(_ raw: String?) -> String {
        let oneLine = (raw ?? "").components(separatedBy: .newlines).joined(separator: " ")
        let trimmed = oneLine.trimmingCharacters(in: .whitespaces)
        return String(trimmed.prefix(maxCommentLength))
    }
}
