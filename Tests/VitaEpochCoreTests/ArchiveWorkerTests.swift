import Foundation
import XCTest
@testable import VitaEpochCore

@MainActor
final class ArchiveWorkerTests: XCTestCase {
    func directory() -> URL { FileManager.default.temporaryDirectory.appending(path: "VitaEpochTests-\(UUID())") }
    func fixture() throws -> Data { try Data(contentsOf: Bundle.module.url(forResource: "device-2026-09-26", withExtension: "json", subdirectory: "Fixtures")!) }
    func testFirstRunCreatesDirectoryWithoutOpeningMissingArchiveAndBatchesBurst() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "nested/archive.json")
        let worker = ArchiveWorker(url: url)
        let error = await worker.load()
        XCTAssertNil(error)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        for i in 0..<50 {
            _ = await worker.process(RawPacket(deviceID: "test", characteristic: "2A37", direction: .rx,
                                              bytes: Data([6,75]), timestamp: Date(timeIntervalSince1970: Double(1000+i))))
        }
        await worker.flush()
        let writes = await worker.writeCount
        XCTAssertLessThan(writes, 50)
        let saved = try LocalArchive.read(from: url)
        XCTAssertEqual(saved.packets.count, 50)
        XCTAssertEqual(saved.samples.count, 50)
    }
    func testMigrationMakesExactBackupRetainsEvidenceAndIsIdempotent() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "archive.json")
        let bytes = try fixture()
        let worker = ArchiveWorker(url: url)
        let error = await worker.load(fixture: bytes)
        XCTAssertNil(error)
        XCTAssertEqual(try Data(contentsOf: directory.appending(path: "archive.before-v2.json")), bytes)
        let migrated = try LocalArchive.read(from: url)
        XCTAssertEqual(migrated.packets.count, 35)
        XCTAssertEqual(migrated.previousDecodes?.count, 16)
        XCTAssertEqual(migrated.samples.count, 16)
        XCTAssertEqual(migrated.schemaVersion, 3)
        XCTAssertEqual(migrated.syncDiagnostics?.filter { !$0.complete }.count, 6)
        let next = ArchiveWorker(url: url)
        let secondError = await next.load()
        XCTAssertNil(secondError)
        let snapshot = await next.snapshot()
        XCTAssertEqual(snapshot.archive.previousDecodes?.count, 16)
        XCTAssertEqual(snapshot.archive.packets.count, 35)
    }
    func testCorruptArchiveIsNeverOverwritten() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "archive.json")
        let evidence = Data("{invalid archive".utf8); try evidence.write(to: url)
        let worker = ArchiveWorker(url: url)
        let error = await worker.load()
        XCTAssertNotNil(error)
        _ = await worker.process(RawPacket(deviceID: "test", characteristic: "2A37", direction: .rx, bytes: Data([6,75])))
        await worker.flush()
        XCTAssertEqual(try Data(contentsOf: url), evidence)
    }
    func testV2MigrationKeepsHistoricalBackupAndPromotesEvidenceLosslessly() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var v2 = try JSONDecoder().decode(LocalArchive.self, from: fixture())
        v2.schemaVersion = 2
        let oldBytes = try JSONEncoder().encode(v2)
        let url = directory.appending(path: "archive.json")
        try oldBytes.write(to: url)
        let historicalBackup = Data("unchanged prior backup".utf8)
        try historicalBackup.write(to: directory.appending(path: "archive.before-v2.json"))
        let worker = ArchiveWorker(url: url)
        let error = await worker.load(); XCTAssertNil(error)
        XCTAssertEqual(try Data(contentsOf: directory.appending(path: "archive.before-v2.json")), historicalBackup)
        XCTAssertEqual(try Data(contentsOf: directory.appending(path: "archive.before-v3.json")), oldBytes)
        let snapshot = await worker.snapshot()
        XCTAssertEqual(snapshot.archive.schemaVersion, 3)
        XCTAssertEqual(Set(snapshot.archive.packets.map(\.id)), Set(v2.packets.map(\.id)))
        XCTAssertEqual(snapshot.archive.samples.count, v2.samples.count)
        XCTAssertTrue(snapshot.archive.samples.filter { $0.metric == .oxygen }.allSatisfy { $0.timestampEvidence?.basis == .independentlyConfirmedVendorExport })
        let reloaded = ArchiveWorker(url: url); _ = await reloaded.load()
        let next = await reloaded.snapshot()
        XCTAssertEqual(next.archive.previousDecodes?.count, snapshot.archive.previousDecodes?.count)
    }

    func testPhysicalMovementRelaunchAndReplayKeepRawAndDeduplicatePositions() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let fixtureURL = try XCTUnwrap(Bundle.module.url(forResource: "capture", withExtension: "json", subdirectory: "Fixtures/physical-2026-09-27"))
        let data = try Data(contentsOf: fixtureURL)
        let original = try JSONDecoder().decode(LocalArchive.self, from: data)
        let url = directory.appending(path: "archive.json")
        let worker = ArchiveWorker(url: url)
        let error = await worker.load(fixture: data); XCTAssertNil(error)
        let initial = await worker.snapshot()
        XCTAssertEqual(initial.archive.movementSamples?.count, 1080)
        XCTAssertEqual(initial.latest[.hrv]?.resolvedHRVStatistic, .sdnn)
        for packet in original.packets { _ = await worker.process(packet) }
        await worker.flush()
        let next = ArchiveWorker(url: url); _ = await next.load()
        let saved = await next.snapshot()
        XCTAssertEqual(saved.archive.movementSamples?.count, 1080)
        XCTAssertEqual(saved.archive.samples.filter { $0.metric == .hrv }.count, 12)
        XCTAssertEqual(Set(saved.archive.packets.map(\.id)), Set(original.packets.map(\.id)))
        XCTAssertTrue(saved.archive.packets.contains { $0.bytes.count == 186 })
    }

}
