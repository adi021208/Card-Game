import Foundation

/// Somewhere versioned, validated records can be written and read back.
///
/// Abstracted so tests run against memory, the app runs against disk, and an
/// iCloud mirror can be slotted in later without touching a caller.
public protocol DataStore: AnyObject, Sendable {
    func read(_ key: String) throws -> Data?
    func write(_ data: Data, for key: String) throws
    func remove(_ key: String) throws
    func keys(withPrefix prefix: String) throws -> [String]
}

public enum StoreError: Error, Hashable, Sendable {
    case unreadable(String)
    case unwritable(String)
    case corrupt(String)
    case unsupportedVersion(key: String, found: Int, supported: Int)
    case validationFailed(key: String, reason: String)
}

/// A record with a schema version attached, so a future release can migrate it
/// instead of guessing or throwing the player's progress away.
public struct VersionedRecord<Payload: Codable & Sendable>: Codable, Sendable {
    public var schemaVersion: Int
    public var writtenAt: Date
    /// Bumped on every write; used to resolve a conflict against a cloud copy.
    public var revision: Int
    public var payload: Payload

    public init(schemaVersion: Int, payload: Payload, revision: Int = 0, writtenAt: Date = Date()) {
        self.schemaVersion = schemaVersion
        self.writtenAt = writtenAt
        self.revision = revision
        self.payload = payload
    }
}

/// A payload that knows its own schema version and can check itself.
public protocol PersistablePayload: Codable, Sendable {
    static var schemaVersion: Int { get }
    static var storeKey: String { get }
    /// Called before a write and after a read. Return a reason to reject.
    func validate() -> String?
    /// Upgrades a payload written by an earlier schema. Return nil to reject.
    static func migrate(from version: Int, data: Data) -> Self?
}

public extension PersistablePayload {
    func validate() -> String? { nil }
    static func migrate(from version: Int, data: Data) -> Self? { nil }
}

/// Reads and writes `PersistablePayload`s through a `DataStore`, applying the
/// full contract: validate, serialise, write versioned; then on load validate
/// the version, migrate if needed, and validate the result before handing it back.
public final class RecordStore: @unchecked Sendable {
    private let store: DataStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var revisions: [String: Int] = [:]
    private let lock = NSLock()

    public init(store: DataStore) {
        self.store = store
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func load<Payload: PersistablePayload>(_ type: Payload.Type, key: String? = nil) throws -> Payload? {
        let storeKey = key ?? Payload.storeKey
        guard let data = try store.read(storeKey) else { return nil }
        return try decode(type, data: data, key: storeKey)
    }

    public func save<Payload: PersistablePayload>(_ payload: Payload, key: String? = nil) throws {
        let storeKey = key ?? Payload.storeKey
        if let reason = payload.validate() {
            throw StoreError.validationFailed(key: storeKey, reason: reason)
        }
        lock.lock()
        let revision = (revisions[storeKey] ?? 0) + 1
        revisions[storeKey] = revision
        lock.unlock()
        let record = VersionedRecord(schemaVersion: Payload.schemaVersion,
                                     payload: payload,
                                     revision: revision)
        let data = try encoder.encode(record)
        try store.write(data, for: storeKey)
    }

    public func remove(_ key: String) throws {
        try store.remove(key)
    }

    public func keys(withPrefix prefix: String) throws -> [String] {
        try store.keys(withPrefix: prefix)
    }

    /// Loads every record under a prefix, skipping any that fail to decode so a
    /// single bad file cannot take out a whole list.
    public func loadAll<Payload: PersistablePayload>(_ type: Payload.Type, prefix: String) throws -> [Payload] {
        var results: [Payload] = []
        for key in try store.keys(withPrefix: prefix) {
            guard let data = (try? store.read(key)) ?? nil else { continue }
            if let payload = try? decode(type, data: data, key: key) {
                results.append(payload)
            }
        }
        return results
    }

    private func decode<Payload: PersistablePayload>(_ type: Payload.Type, data: Data, key: String) throws -> Payload {
        // Peek at the envelope first so a version mismatch is a migration, not a
        // decode failure.
        guard let envelope = try? decoder.decode(SchemaEnvelope.self, from: data) else {
            throw StoreError.corrupt(key)
        }
        if envelope.schemaVersion > Payload.schemaVersion {
            // Written by a newer build. Refuse rather than mangle it.
            throw StoreError.unsupportedVersion(key: key,
                                                found: envelope.schemaVersion,
                                                supported: Payload.schemaVersion)
        }
        let payload: Payload
        if envelope.schemaVersion == Payload.schemaVersion {
            guard let record = try? decoder.decode(VersionedRecord<Payload>.self, from: data) else {
                throw StoreError.corrupt(key)
            }
            lock.lock()
            revisions[key] = max(revisions[key] ?? 0, record.revision)
            lock.unlock()
            payload = record.payload
        } else {
            guard let migrated = Payload.migrate(from: envelope.schemaVersion, data: data) else {
                throw StoreError.unsupportedVersion(key: key,
                                                    found: envelope.schemaVersion,
                                                    supported: Payload.schemaVersion)
            }
            payload = migrated
        }
        if let reason = payload.validate() {
            throw StoreError.validationFailed(key: key, reason: reason)
        }
        return payload
    }

    private struct SchemaEnvelope: Codable {
        var schemaVersion: Int
    }
}

/// In-memory store. Used by tests and by the debug menu's "sandbox" mode.
public final class MemoryDataStore: DataStore, @unchecked Sendable {
    private var contents: [String: Data] = [:]
    private let lock = NSLock()

    public init() {}

    public func read(_ key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return contents[key]
    }

    public func write(_ data: Data, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        contents[key] = data
    }

    public func remove(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        contents[key] = nil
    }

    public func keys(withPrefix prefix: String) throws -> [String] {
        lock.lock(); defer { lock.unlock() }
        return contents.keys.filter { $0.hasPrefix(prefix) }.sorted()
    }

    public var isEmpty: Bool {
        lock.lock(); defer { lock.unlock() }
        return contents.isEmpty
    }
}

/// Disk store. Writes atomically so a crash mid-save cannot leave a half-written
/// file where the player's progress used to be.
public final class FileDataStore: DataStore, @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// The app's own folder in Application Support, excluded from iCloud backup
    /// only where that is appropriate (saves are small and worth backing up, so
    /// they are not excluded).
    public static func applicationSupport(subdirectory: String = "Deck") throws -> FileDataStore {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
        return try FileDataStore(directory: base.appendingPathComponent(subdirectory, isDirectory: true))
    }

    private func url(for key: String) -> URL {
        // Keys are namespaced with dots; encode anything path-unsafe.
        let safe = key.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent(safe).appendingPathExtension("json")
    }

    public func read(_ key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        let fileURL = url(for: key)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            throw StoreError.unreadable(key)
        }
    }

    public func write(_ data: Data, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        do {
            try data.write(to: url(for: key), options: [.atomic])
        } catch {
            throw StoreError.unwritable(key)
        }
    }

    public func remove(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        let fileURL = url(for: key)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    public func keys(withPrefix prefix: String) throws -> [String] {
        lock.lock(); defer { lock.unlock() }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return contents
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(5)) }
            .filter { $0.hasPrefix(prefix) }
            .sorted()
    }
}
