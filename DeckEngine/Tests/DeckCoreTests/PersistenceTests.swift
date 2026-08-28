import XCTest
@testable import DeckCore

/// A payload at the current schema, with a rule it can check about itself.
private struct Ledger: PersistablePayload, Equatable {
    static let schemaVersion = 2
    static let storeKey = "test.ledger"

    var owner: String
    var chips: Int
    var seats: [String]

    func validate() -> String? {
        if owner.isEmpty { return "an owner is required" }
        if chips < 0 { return "chips cannot go negative" }
        return nil
    }

    /// Version 1 stored a single `seat` string where version 2 stores a list.
    static func migrate(from version: Int, data: Data) -> Ledger? {
        guard version == 1 else { return nil }
        struct V1: Codable { var owner: String; var chips: Int; var seat: String }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let old = try? decoder.decode(VersionedRecord<V1>.self, from: data) else { return nil }
        return Ledger(owner: old.payload.owner,
                      chips: old.payload.chips,
                      seats: [old.payload.seat])
    }
}

/// A payload that refuses every migration, to prove the store gives up loudly
/// rather than handing back something half-understood.
private struct Brittle: PersistablePayload, Equatable {
    static let schemaVersion = 4
    static let storeKey = "test.brittle"
    var value: Int
}

private func writeRaw(_ json: String, key: String, into store: DataStore) throws {
    try store.write(Data(json.utf8), for: key)
}

final class PersistenceTests: XCTestCase {

    // MARK: - The round trip

    func testSavedRecordComesBackIdentical() throws {
        let store = MemoryDataStore()
        let records = RecordStore(store: store)
        let ledger = Ledger(owner: "ada", chips: 1500, seats: ["north", "south"])
        try records.save(ledger)
        let loaded = try records.load(Ledger.self)
        XCTAssertEqual(loaded, ledger)
    }

    func testLoadingSomethingNeverWrittenIsNilNotAnError() throws {
        let records = RecordStore(store: MemoryDataStore())
        XCTAssertNil(try records.load(Ledger.self))
    }

    func testTheSchemaVersionIsWrittenIntoTheRecord() throws {
        let store = MemoryDataStore()
        let records = RecordStore(store: store)
        try records.save(Ledger(owner: "ada", chips: 10, seats: []))
        let data = try XCTUnwrap(try store.read(Ledger.storeKey))
        let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(envelope?["schemaVersion"] as? Int, Ledger.schemaVersion)
        XCTAssertNotNil(envelope?["writtenAt"], "a record records when it was written")
    }

    func testEveryWriteBumpsTheRevision() throws {
        let store = MemoryDataStore()
        let records = RecordStore(store: store)
        try records.save(Ledger(owner: "ada", chips: 1, seats: []))
        try records.save(Ledger(owner: "ada", chips: 2, seats: []))
        try records.save(Ledger(owner: "ada", chips: 3, seats: []))
        let data = try XCTUnwrap(try store.read(Ledger.storeKey))
        let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(envelope?["revision"] as? Int, 3)
    }

    // MARK: - Validation

    func testAnInvalidPayloadIsRefusedBeforeItIsWritten() throws {
        let store = MemoryDataStore()
        let records = RecordStore(store: store)
        XCTAssertThrowsError(try records.save(Ledger(owner: "", chips: 5, seats: []))) { error in
            guard case let StoreError.validationFailed(key, reason) = error else {
                return XCTFail("expected a validation failure, got \(error)")
            }
            XCTAssertEqual(key, Ledger.storeKey)
            XCTAssertFalse(reason.isEmpty, "a rejection explains itself")
        }
        XCTAssertTrue(store.isEmpty, "a rejected save leaves nothing behind")
    }

    func testAnInvalidPayloadOnDiskIsRefusedOnLoad() throws {
        let store = MemoryDataStore()
        let records = RecordStore(store: store)
        // Hand-written by an imaginary bad build: negative chips.
        try writeRaw(#"{"schemaVersion":2,"revision":1,"writtenAt":"2026-01-01T00:00:00Z","payload":{"owner":"ada","chips":-40,"seats":[]}}"#,
                     key: Ledger.storeKey, into: store)
        XCTAssertThrowsError(try records.load(Ledger.self)) { error in
            guard case StoreError.validationFailed = error else {
                return XCTFail("expected a validation failure, got \(error)")
            }
        }
    }

    // MARK: - Versioning

    func testAnOlderRecordIsMigratedForward() throws {
        let store = MemoryDataStore()
        let records = RecordStore(store: store)
        try writeRaw(#"{"schemaVersion":1,"revision":7,"writtenAt":"2026-01-01T00:00:00Z","payload":{"owner":"ada","chips":900,"seat":"north"}}"#,
                     key: Ledger.storeKey, into: store)
        let loaded = try XCTUnwrap(try records.load(Ledger.self))
        XCTAssertEqual(loaded, Ledger(owner: "ada", chips: 900, seats: ["north"]),
                       "the v1 seat becomes a one-element seat list")
    }

    func testARecordFromANewerBuildIsRefusedRatherThanMangled() throws {
        let store = MemoryDataStore()
        let records = RecordStore(store: store)
        try writeRaw(#"{"schemaVersion":99,"revision":1,"writtenAt":"2026-01-01T00:00:00Z","payload":{"owner":"ada","chips":10,"seats":[]}}"#,
                     key: Ledger.storeKey, into: store)
        XCTAssertThrowsError(try records.load(Ledger.self)) { error in
            guard case let StoreError.unsupportedVersion(_, found, supported) = error else {
                return XCTFail("expected an unsupported-version error, got \(error)")
            }
            XCTAssertEqual(found, 99)
            XCTAssertEqual(supported, Ledger.schemaVersion)
        }
    }

    func testAnOlderRecordWithNoMigrationIsRefused() throws {
        let store = MemoryDataStore()
        let records = RecordStore(store: store)
        try writeRaw(#"{"schemaVersion":1,"revision":1,"writtenAt":"2026-01-01T00:00:00Z","payload":{"value":3}}"#,
                     key: Brittle.storeKey, into: store)
        XCTAssertThrowsError(try records.load(Brittle.self)) { error in
            guard case StoreError.unsupportedVersion = error else {
                return XCTFail("expected an unsupported-version error, got \(error)")
            }
        }
    }

    func testCorruptDataIsReportedAsCorruptNotAsAMissingRecord() throws {
        let store = MemoryDataStore()
        let records = RecordStore(store: store)
        try store.write(Data("this is not json".utf8), for: Ledger.storeKey)
        XCTAssertThrowsError(try records.load(Ledger.self)) { error in
            guard case let StoreError.corrupt(key) = error else {
                return XCTFail("expected a corruption error, got \(error)")
            }
            XCTAssertEqual(key, Ledger.storeKey)
        }
    }

    func testAPayloadThatDoesNotMatchItsEnvelopeIsCorrupt() throws {
        let store = MemoryDataStore()
        let records = RecordStore(store: store)
        // Right version, wrong shape.
        try writeRaw(#"{"schemaVersion":2,"revision":1,"writtenAt":"2026-01-01T00:00:00Z","payload":{"nonsense":true}}"#,
                     key: Ledger.storeKey, into: store)
        XCTAssertThrowsError(try records.load(Ledger.self)) { error in
            guard case StoreError.corrupt = error else {
                return XCTFail("expected a corruption error, got \(error)")
            }
        }
    }

    // MARK: - Lists

    func testLoadingAListSkipsOneBadFileInsteadOfFailingEntirely() throws {
        let store = MemoryDataStore()
        let records = RecordStore(store: store)
        try records.save(Ledger(owner: "ada", chips: 1, seats: []), key: "slot.a")
        try store.write(Data("garbage".utf8), for: "slot.b")
        try records.save(Ledger(owner: "grace", chips: 2, seats: []), key: "slot.c")

        let loaded = try records.loadAll(Ledger.self, prefix: "slot.")
        XCTAssertEqual(loaded.count, 2, "the bad slot is skipped, the good ones survive")
        XCTAssertEqual(Set(loaded.map(\.owner)), ["ada", "grace"])
    }

    func testKeysAreListedByPrefix() throws {
        let store = MemoryDataStore()
        let records = RecordStore(store: store)
        try records.save(Ledger(owner: "a", chips: 0, seats: []), key: "save.1")
        try records.save(Ledger(owner: "b", chips: 0, seats: []), key: "save.2")
        try records.save(Ledger(owner: "c", chips: 0, seats: []), key: "other.1")
        XCTAssertEqual(try records.keys(withPrefix: "save."), ["save.1", "save.2"])
    }

    func testRemovingARecordMakesItGone() throws {
        let store = MemoryDataStore()
        let records = RecordStore(store: store)
        try records.save(Ledger(owner: "ada", chips: 5, seats: []))
        try records.remove(Ledger.storeKey)
        XCTAssertNil(try records.load(Ledger.self))
    }

    // MARK: - Disk

    func testFileStoreWritesAndReadsBack() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try FileDataStore(directory: directory)
        let records = RecordStore(store: store)
        let ledger = Ledger(owner: "ada", chips: 250, seats: ["north"])
        try records.save(ledger)

        // A brand new store object over the same folder: this is the relaunch case.
        let reopened = RecordStore(store: try FileDataStore(directory: directory))
        XCTAssertEqual(try reopened.load(Ledger.self), ledger)
    }

    func testFileStoreListsAndRemovesByKeyNotByFilename() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try FileDataStore(directory: directory)
        try store.write(Data("{}".utf8), for: "save.active")
        try store.write(Data("{}".utf8), for: "save.slot.2")
        try store.write(Data("{}".utf8), for: "profile")

        XCTAssertEqual(try store.keys(withPrefix: "save."), ["save.active", "save.slot.2"])
        try store.remove("save.active")
        XCTAssertEqual(try store.keys(withPrefix: "save."), ["save.slot.2"])
        XCTAssertNil(try store.read("save.active"))
    }

    func testFileStoreOverwritesRatherThanAppending() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try FileDataStore(directory: directory)
        try store.write(Data(repeating: 0x41, count: 4096), for: "big")
        try store.write(Data("small".utf8), for: "big")
        XCTAssertEqual(try store.read("big"), Data("small".utf8),
                       "an atomic write replaces the file whole")
    }

    // MARK: - The checkpoint envelope

    func testCheckpointCarriesEverythingNeededToResume() throws {
        let seats = [
            Seat(id: SeatID(0), displayName: "A", controller: .human(profileID: "a")),
            Seat(id: SeatID(1), displayName: "B", controller: .ai(profile: .balanced))
        ]
        let configuration = GameConfiguration(gameID: GameID("toy"),
                                              seating: SeatingPlan(seats: seats),
                                              seed: 99)
        let checkpoint = GameCheckpoint(gameID: GameID("toy"),
                                        rulesVersion: 3,
                                        configuration: configuration,
                                        stateData: Data("state".utf8),
                                        replayLog: ["0/play/1", "1/play/2"],
                                        turnCount: 2,
                                        elapsed: 42)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(GameCheckpoint.self,
                                          from: try encoder.encode(checkpoint))

        XCTAssertEqual(restored.gameID, GameID("toy"))
        XCTAssertEqual(restored.rulesVersion, 3)
        XCTAssertEqual(restored.configuration.seed, 99)
        XCTAssertEqual(restored.replayLog, ["0/play/1", "1/play/2"])
        XCTAssertEqual(restored.turnCount, 2)
        XCTAssertEqual(restored.elapsed, 42)
        XCTAssertEqual(restored.envelopeVersion, GameCheckpoint.currentEnvelopeVersion)
    }
}
