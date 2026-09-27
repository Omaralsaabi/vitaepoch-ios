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
        XCTAssertEqual(migrated.schemaVersion, 2)
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
}
