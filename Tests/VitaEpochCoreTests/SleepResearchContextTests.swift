import Foundation
import XCTest
@testable import VitaEpochCore
import X6Research

final class SleepResearchContextTests: XCTestCase {
    func fixture(_ folder: String, _ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/\(folder)")))
    }
    func testCapturedContextRetainsZeroSemanticsAndNeverCreatesSleepSamples() throws {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let reference = try decoder.decode(SleepReference.self, from: fixture("physical-2026-09-27", "sleep-reference"))
        let raw = try JSONDecoder().decode(LocalArchive.self, from: fixture("physical-2026-09-27", "capture"))
        let archive = PacketProcessor.reprocess(raw)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(archive)
        let context = try MovementContext.points(archive: archive, reference: reference)
        XCTAssertEqual(before, try encoder.encode(archive))
        XCTAssertTrue(context.contains { $0.availability == .zeroUninterpreted && $0.rawValue == 0 })
        XCTAssertTrue(context.contains { $0.minute < reference.intervals[0].start })
        XCTAssertTrue(context.contains { $0.minute >= reference.intervals.last!.end })
        XCTAssertTrue(context.allSatisfy { $0.minute >= reference.intervals[0].start.addingTimeInterval(-59*60) && $0.minute <= reference.intervals.last!.end.addingTimeInterval(30*60) })
        XCTAssertEqual(Set(context.map(\.minute)).count, context.count)
        XCTAssertEqual(try encoder.encode(context), try encoder.encode(MovementContext.points(archive: archive, reference: reference)))
        for point in context {
            let sample = try XCTUnwrap(archive.movementSamples?.first { $0.localMinute == point.minute })
            XCTAssertEqual(point.rawValue, sample.rawValue)
            XCTAssertEqual(point.packetID, sample.packetID)
        }
    }
    func testSecondNightContextDoesNotMixPriorNightAndIsUnlabeled() throws {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let reference = try decoder.decode(SleepReference.self, from: fixture("physical-2026-09-28", "sleep-reference"))
        var raw = try JSONDecoder().decode(LocalArchive.self, from: fixture("physical-2026-09-28", "capture"))
        raw.packets.append(contentsOf: try JSONDecoder().decode(LocalArchive.self, from: fixture("physical-2026-09-28-previous-day", "capture")).packets)
        let archive = PacketProcessor.reprocess(raw)
        let context = try MovementContext.points(archive: archive, reference: reference)
        XCTAssertTrue(archive.samples.isEmpty)
        XCTAssertTrue(context.contains { $0.selector == "0107" && $0.minute < reference.intervals[0].start })
        XCTAssertFalse(context.contains { $0.selector == "0100" })
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(context)) as? [[String: Any]])
        XCTAssertTrue(object.allSatisfy { $0["stage"] == nil && $0["groundTruthStage"] == nil })
    }
}
