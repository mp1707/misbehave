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

    public static func connectionURL(id: String) -> URL? {
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = "connection"
        components.path = "/" + id
        return components.url
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
}
