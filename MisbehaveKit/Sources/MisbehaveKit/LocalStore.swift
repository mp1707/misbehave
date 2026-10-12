import Foundation

/// The JSON files in the App Group container that app, widget and notification extension share.
///
/// Each file has exactly one writer, so no cross-process lock is needed: the app owns
/// `store.json`, the notification extension owns `inbox.json`. Readers merge the two.
public struct LocalStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static let shared: LocalStore = {
        let fileManager = FileManager.default
        let base = fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupID)
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LocalStore(directory: base.appendingPathComponent("misbehave", isDirectory: true))
    }()

    private var stateURL: URL { directory.appendingPathComponent("store.json") }
    private var inboxURL: URL { directory.appendingPathComponent("inbox.json") }
    private var diagnosticsURL: URL { directory.appendingPathComponent("diagnostics.json") }

    public func loadState() -> StoreState {
        read(StoreState.self, from: stateURL) ?? StoreState()
    }

    public func saveState(_ state: StoreState) throws {
        try write(state, to: stateURL)
    }

    public func loadInbox() -> Inbox {
        read(Inbox.self, from: inboxURL) ?? Inbox()
    }

    public func saveInbox(_ inbox: Inbox) throws {
        try write(inbox, to: inboxURL)
    }

    public func loadDiagnostics() -> AppDiagnostics {
        read(AppDiagnostics.self, from: diagnosticsURL) ?? AppDiagnostics()
    }

    public func saveDiagnostics(_ diagnostics: AppDiagnostics) {
        try? write(diagnostics, to: diagnosticsURL)
    }

    /// The app's state plus whatever the notification extension fetched since.
    public func snapshot() -> StoreState {
        var state = loadState()
        state.absorb(loadInbox())
        return state
    }

    public func deleteAll() {
        try? FileManager.default.removeItem(at: stateURL)
        try? FileManager.default.removeItem(at: inboxURL)
        try? FileManager.default.removeItem(at: diagnosticsURL)
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        #if os(iOS)
        // Readable while the phone is locked, so widget and extension keep working.
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}
