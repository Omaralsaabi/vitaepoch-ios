import Foundation
import XCTest
@testable import VitaEpochCore
import X6Research

final class PreviousDayMovementTests: XCTestCase {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Amman")!; return c }
    func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func data(_ folder: String, _ name: String = "capture") throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/\(folder)")))
    }
    func previous() throws -> LocalArchive { try JSONDecoder().decode(LocalArchive.self, from: data("physical-2026-09-28-previous-day")) }
    func decoded(_ packet: RawPacket, calendar: Calendar? = nil) throws -> [MinuteMovementSample] {
        try MovementHistoryDecoder.decode(X6Frame(packet.bytes), packet: packet, calendar: calendar ?? self.calendar)
    }
    func testPhysical0100And0107MapToPreviousDayWithoutChangingRawValues() throws {
        let capture = try previous()
        XCTAssertEqual(capture.packets.map { $0.bytes.count }, [188,188])
        for packet in capture.packets {
            let positions = try decoded(packet)
            XCTAssertEqual(positions.count, 180)
            XCTAssertEqual(positions.map(\.rawValue), Array(packet.bytes.dropFirst(8)))
            XCTAssertTrue(positions.allSatisfy { $0.day == date("2026-09-27T00:00:00+03:00") })
            XCTAssertTrue(positions.allSatisfy { $0.selector(from: packet)?.dayOffset == 1 })
            XCTAssertEqual(positions.first?.selector(from: packet)?.hex, Array(packet.bytes)[7] == 0 ? "0100" : "0107")
            XCTAssertTrue(positions.allSatisfy { $0.decoderVersion == "x6-movement-v0.2" && $0.semanticEvidence.status == .strongInference })
        }
        let page7 = try decoded(capture.packets[1])
        XCTAssertEqual(page7.first?.localMinute, date("2026-09-27T21:00:00+03:00"))
        XCTAssertEqual(page7.last?.localMinute, date("2026-09-27T23:59:00+03:00"))
        XCTAssertEqual(page7.suffix(30).first?.localMinute, date("2026-09-27T23:30:00+03:00"))
        XCTAssertTrue(page7.suffix(30).allSatisfy { $0.availability == .observedRawSignal })
        let old = try JSONDecoder().decode(LocalArchive.self, from: data("physical-2026-09-27"))
        let oldPage0 = try XCTUnwrap(old.packets.first { $0.bytes.count == 188 && Array($0.bytes)[6...7] == [0,0][...] })
        XCTAssertEqual(capture.packets[0].bytes.dropFirst(8), oldPage0.bytes.dropFirst(8))
    }
    func testSameRepresentedDayDeduplicatesWhileDifferentDaysDoNotCollide() throws {
        let previousPacket = try previous().packets[1]
        var bytes = Array(previousPacket.bytes); bytes[6] = 0
        // Same represented date captured the evening before, with a current-day selector.
        let earlier = RawPacket(deviceID: previousPacket.deviceID, characteristic: "FDD3", direction: .rx,
            bytes: Data(bytes), timestamp: date("2026-09-27T23:59:59+03:00"), timeZoneID: "Asia/Amman")
        let current = RawPacket(deviceID: previousPacket.deviceID, characteristic: "FDD3", direction: .rx,
            bytes: Data(bytes), timestamp: previousPacket.timestamp, timeZoneID: "Asia/Amman")
        var archive = LocalArchive(); var processor = PacketProcessor()
        _ = processor.process(earlier, archive: &archive)
        _ = processor.process(previousPacket, archive: &archive)
        _ = processor.process(previousPacket, archive: &archive)
        XCTAssertEqual(archive.movementSamples?.count, 180)
        XCTAssertEqual(Set(try decoded(earlier).map(\.id)), Set(try decoded(previousPacket).map(\.id)))
        _ = processor.process(current, archive: &archive)
        XCTAssertEqual(archive.movementSamples?.count, 360)
        XCTAssertTrue(archive.samples.isEmpty)
        let restored = try JSONDecoder().decode(LocalArchive.self, from: JSONEncoder().encode(archive))
        XCTAssertEqual(restored.schemaVersion, 3)
        XCTAssertEqual(restored.movementSamples, archive.movementSamples)
        let linked = try XCTUnwrap(restored.movementSamples?.first { $0.packetID == previousPacket.id })
        XCTAssertEqual(linked.selector(from: previousPacket)?.hex, "0107")
        XCTAssertNil(linked.selector(from: current))
    }
    func testSelectorBoundsAndObservedVersusInferredPages() throws {
        for page: UInt8 in 0...7 {
            let selector = try MovementSelector(dayOffset: 1, page: page)
            XCTAssertEqual(selector.request.hex, String(format: "FDDA1008021301%02X", page))
            XCTAssertEqual(selector.physicallyObserved, page == 0 || page == 7)
        }
        XCTAssertThrowsError(try MovementSelector(dayOffset: 2, page: 0))
        XCTAssertThrowsError(try MovementSelector(dayOffset: 1, page: 8))
        let original = try previous().packets[0]; var bytes = Array(original.bytes); bytes[6] = 2
        let packet = RawPacket(deviceID: original.deviceID, characteristic: "FDD3", direction: .rx, bytes: Data(bytes), timestamp: original.timestamp)
        var archive = LocalArchive(); var processor = PacketProcessor()
        let result = processor.process(packet, archive: &archive)
        XCTAssertNotNil(result.error)
        XCTAssertEqual(archive.packets.first?.bytes, packet.bytes)
        XCTAssertTrue((archive.movementSamples ?? []).isEmpty)
        XCTAssertFalse(X6Command.sync.contains(.movement))
    }
    func testSinglePreviousPageAcquisitionMatchesDayAndDoesNotFanOut() throws {
        let packet = try previous().packets[1]
        let selector = try MovementSelector(dayOffset: 1, page: 7)
        var progress = SyncProgress(command: .movement, deviceID: packet.deviceID, startedAt: packet.timestamp, movementPage: selector)
        progress.wrote(selector.request, at: packet.timestamp)
        var wrongDay = Array(packet.bytes); wrongDay[6] = 0
        let other = RawPacket(deviceID: packet.deviceID, characteristic: "FDD3", direction: .rx, bytes: Data(wrongDay), timestamp: packet.timestamp)
        progress.received(FrameReceipt(packet: other, frame: try X6Frame(other.bytes), sampleCount: 180, error: nil))
        XCTAssertFalse(progress.isComplete)
        XCTAssertEqual(progress.movementAction(at: packet.timestamp.addingTimeInterval(1)), .wait(until: packet.timestamp.addingTimeInterval(8)))
        progress.received(FrameReceipt(packet: packet, frame: try X6Frame(packet.bytes), sampleCount: 180, error: nil))
        XCTAssertTrue(progress.isComplete)
        XCTAssertEqual(progress.movementAction(at: packet.timestamp.addingTimeInterval(2)), .finish)
        XCTAssertEqual(progress.diagnostic.receivedSelectors, ["0107"])
        XCTAssertEqual(progress.diagnostic.writes.count, 1)
        XCTAssertEqual(progress.diagnostic.acquisition(for: progress.diagnostic.responses.last!), "after explicit previous-day request")
        var missing = SyncProgress(command: .movement, deviceID: packet.deviceID, startedAt: packet.timestamp, movementPage: selector)
        missing.wrote(selector.request, at: packet.timestamp)
        XCTAssertEqual(missing.movementAction(at: packet.timestamp.addingTimeInterval(8)), .finish)
        missing.finish(at: packet.timestamp.addingTimeInterval(8))
        XCTAssertEqual(missing.diagnostic.reason, "Timed out; missing 0107")
        var fullCurrent = SyncProgress(command: .movement, deviceID: packet.deviceID, startedAt: packet.timestamp)
        fullCurrent.wrote(X6Command.movement.bytes, at: packet.timestamp)
        fullCurrent.received(FrameReceipt(packet: packet, frame: try X6Frame(packet.bytes), sampleCount: 180, error: nil))
        XCTAssertTrue(fullCurrent.diagnostic.receivedPages.isEmpty)
    }
    func testOvernightPlannerSelectsOnlyIntersectingPagesAndRejectsUnsupportedDays() throws {
        let capture = date("2026-09-28T12:03:00+03:00")
        let plan = try MovementPagePlanner.selectors(start: date("2026-09-27T23:30:00+03:00"), end: date("2026-09-28T08:35:00+03:00"), capturedAt: capture, calendar: calendar)
        XCTAssertEqual(plan.map(\.hex), ["0107","0000","0001","0002"])
        let exactBoundary = try MovementPagePlanner.selectors(start: date("2026-09-28T02:59:30+03:00"), end: date("2026-09-28T03:00:00+03:00"), capturedAt: capture, calendar: calendar)
        XCTAssertEqual(exactBoundary.map(\.hex), ["0000"])
        XCTAssertThrowsError(try MovementPagePlanner.selectors(start: date("2026-09-26T23:30:00+03:00"), end: capture, capturedAt: capture, calendar: calendar))
        XCTAssertThrowsError(try MovementPagePlanner.selectors(start: capture, end: capture, capturedAt: capture, calendar: calendar))
        XCTAssertThrowsError(try MovementPagePlanner.selectors(start: capture, end: date("2026-09-29T00:01:00+03:00"), capturedAt: capture, calendar: calendar))
    }
    func testPreviousLocalDayUsesCalendarDaysAcrossDSTInsteadOf86400Seconds() throws {
        var ny = Calendar(identifier: .gregorian); ny.timeZone = TimeZone(identifier: "America/New_York")!
        let source = try previous().packets[1]
        let packet = RawPacket(deviceID: source.deviceID, characteristic: "FDD3", direction: .rx, bytes: source.bytes,
            timestamp: date("2026-03-09T12:00:00-04:00"), timeZoneID: ny.timeZone.identifier)
        let positions = try decoded(packet, calendar: ny)
        XCTAssertEqual(positions.first?.day, date("2026-03-08T00:00:00-05:00"))
        XCTAssertEqual(positions.first?.localMinute, date("2026-03-08T21:00:00-04:00"))
    }
    func testSecondNightFullCoverageOnlyAddsMissingThirtyMinutesAndIsDeterministic() throws {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let reference = try decoder.decode(SleepReference.self, from: data("physical-2026-09-28", "sleep-reference"))
        let vendor = try decoder.decode([VendorObservation].self, from: data("physical-2026-09-28", "vendor-observations"))
        var original = try JSONDecoder().decode(LocalArchive.self, from: data("physical-2026-09-28"))
        let before = try SleepAlignment.align(archive: PacketProcessor.reprocess(original), reference: reference, vendorObservations: vendor)
        original.packets.append(contentsOf: try previous().packets)
        let archive = PacketProcessor.reprocess(original)
        let after = try SleepAlignment.align(archive: archive, reference: reference, vendorObservations: vendor)
        XCTAssertEqual(after.rows.count, 545)
        XCTAssertEqual(after.rows.filter { $0.movementRaw != nil }.count, 545)
        XCTAssertTrue(after.rows.allSatisfy { $0.movementAvailability == "observedRawSignal" })
        XCTAssertEqual(after.stages.map(\.movementRaw.count), [273,221,48,3])
        XCTAssertEqual(after.stages.reduce(0) { $0 + $1.missingMovementMinutes }, 0)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        XCTAssertEqual(try encoder.encode(Array(before.rows.dropFirst(30))), try encoder.encode(Array(after.rows.dropFirst(30))))
        XCTAssertEqual(after.rows.first?.minute, date("2026-09-27T23:30:00+03:00"))
        XCTAssertEqual(SleepAlignment.transitions(in: after).observedTransitions, 45)
        XCTAssertTrue(archive.samples.isEmpty)
        let again = try SleepAlignment.align(archive: PacketProcessor.reprocess(original), reference: reference, vendorObservations: vendor)
        XCTAssertEqual(try encoder.encode(after), try encoder.encode(again))
    }
}
