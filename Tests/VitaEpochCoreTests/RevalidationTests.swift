import Foundation
import XCTest
@testable import VitaEpochCore
import X6Research

final class RevalidationTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-09-28T12:03:00+03:00")!
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Amman")!; return c }
    func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/physical-2026-09-28")))
    }
    func capture() throws -> LocalArchive { try JSONDecoder().decode(LocalArchive.self, from: fixture("capture")) }
    func start() -> SyncProgress {
        var p = SyncProgress(command: .movement, deviceID: "constructed", startedAt: now)
        p.wrote(X6Command.movement.bytes, at: now); return p
    }
    // Constructed transport frames; physical byte integrity is tested separately below.
    func receipt(_ page: UInt8, at seconds: Double, device: String = "constructed", value: UInt8 = 0) throws -> FrameReceipt {
        let bytes = Data([0xFD,0xDA,0x10,188,2,0x13,0,page] + Array(repeating: value, count: 180))
        let packet = RawPacket(deviceID: device, characteristic: "FDD3", direction: .rx, bytes: bytes, timestamp: now.addingTimeInterval(seconds), timeZoneID: "Asia/Amman")
        return FrameReceipt(packet: packet, frame: try X6Frame(bytes), sampleCount: value == 0 ? 0 : 180, error: nil)
    }
    func assertWrite(_ p: inout SyncProgress, page: UInt8, at seconds: Double, file: StaticString = #filePath, line: UInt = #line) {
        let date = now.addingTimeInterval(seconds)
        let expected = Data([0xFD,0xDA,0x10,8,2,0x13,0,page])
        XCTAssertEqual(p.movementAction(at: date), .write(expected), file: file, line: line)
        p.wrote(expected, at: date)
    }
    func testInitialOnlyQuietWindowThenFallbackOnceEachAndSameCapture() throws {
        var p = start(); let captureID = p.diagnostic.id
        p.received(try receipt(0, at: 0.1, value: 128))
        XCTAssertEqual(p.movementAction(at: now.addingTimeInterval(0.5)), .wait(until: now.addingTimeInterval(0.9)))
        for page: UInt8 in 1...7 {
            let t = Double(page)
            assertWrite(&p, page: page, at: t)
            XCTAssertEqual(p.movementAction(at: now.addingTimeInterval(t+0.01)), .wait(until: now.addingTimeInterval(t+8)))
            p.received(try receipt(page, at: t+0.1))
        }
        XCTAssertEqual(p.diagnostic.id, captureID)
        XCTAssertEqual(p.diagnostic.writes.count, 8)
        XCTAssertEqual(Set(p.diagnostic.writes.map(\.variantHex)).count, 8)
        XCTAssertTrue(p.isComplete)
        XCTAssertEqual(p.movementAction(at: now.addingTimeInterval(8)), .finish)
        XCTAssertEqual(p.diagnostic.acquisition(for: p.diagnostic.responses[0]), "automatic after initial request")
        XCTAssertTrue(p.diagnostic.responses.dropFirst().allSatisfy { p.diagnostic.acquisition(for: $0) == "after explicit fallback" })
    }
    func testPartialAutomaticBurstRequestsOnlyMissingAndAcceptsOutOfOrder() throws {
        var p = start()
        for page: UInt8 in [0,3,7,1] { p.received(try receipt(page, at: 0.1)) }
        assertWrite(&p, page: 2, at: 1)
        p.received(try receipt(6, at: 1.1)) // unrelated to outstanding selector: keep waiting
        XCTAssertEqual(p.movementAction(at: now.addingTimeInterval(2)), .wait(until: now.addingTimeInterval(9)))
        p.received(try receipt(2, at: 2.1))
        assertWrite(&p, page: 4, at: 3)
        p.received(try receipt(5, at: 3.1)); p.received(try receipt(4, at: 3.2))
        XCTAssertTrue(p.isComplete)
        XCTAssertEqual(p.diagnostic.writes.map(\.variantHex), ["0000","0002","0004"])
    }
    func testFullAutomaticBurstHasNoFallbackEvenForZeroFuturePages() throws {
        var p = start()
        for page: UInt8 in [0,7,5,3,1,6,2,4] { p.received(try receipt(page, at: 0.1)) }
        XCTAssertEqual(p.movementAction(at: now.addingTimeInterval(1)), .finish)
        XCTAssertTrue(p.isComplete); XCTAssertEqual(p.diagnostic.writes.count, 1)
    }
    func testMissingFallbackDoesNotResendAndReportsExactMissingPages() throws {
        var p = start(); p.received(try receipt(0, at: 0.1))
        for page: UInt8 in 1...7 { assertWrite(&p, page: page, at: 1 + Double(page-1)*8) }
        XCTAssertEqual(p.movementAction(at: now.addingTimeInterval(57)), .finish)
        p.finish(at: now.addingTimeInterval(57))
        XCTAssertFalse(p.diagnostic.complete)
        XCTAssertEqual(p.diagnostic.reason, "Timed out; missing 0001, 0002, 0003, 0004, 0005, 0006, 0007")
        XCTAssertEqual(p.diagnostic.writes.count, 8)
    }
    func testNoInitialResponseStillBoundedAndNoInitialResend() throws {
        var p = start()
        XCTAssertEqual(p.movementAction(at: now.addingTimeInterval(7)), .wait(until: now.addingTimeInterval(8)))
        for page: UInt8 in 1...7 { assertWrite(&p, page: page, at: Double(page)*8) }
        XCTAssertEqual(p.movementAction(at: now.addingTimeInterval(64)), .finish)
        XCTAssertEqual(p.missingPages, Array(0...7))
        XCTAssertEqual(p.movementAction(at: now.addingTimeInterval(72)), .finish)
    }
    func testOtherDeviceCannotCompleteCaptureAndDuplicatesCannotExtendDeadline() throws {
        var p = start()
        p.received(try receipt(0, at: 0.1, device: "other"))
        XCTAssertEqual(p.diagnostic.receivedPages, [])
        p.received(try receipt(0, at: 0.2)); assertWrite(&p, page: 1, at: 1)
        for t in [2.0,4,6,8.9] { p.received(try receipt(0, at: t)) }
        assertWrite(&p, page: 2, at: 9)
        XCTAssertEqual(p.movementAction(at: now.addingTimeInterval(72)), .finish)
    }
    func testPhysical28SeptemberBytesAreNotRepairedAndFutureIsUnobserved() throws {
        let original = try capture()
        XCTAssertEqual(original.packets.map { $0.bytes.count }, [188,188,188,188,186,184,188,182])
        let replay = PacketProcessor.reprocess(original)
        XCTAssertEqual(replay.packets.map(\.bytes), original.packets.map(\.bytes))
        XCTAssertEqual(replay.movementSamples?.count, 900)
        for packet in original.packets {
            if packet.bytes.count != 188 { XCTAssertThrowsError(try X6Frame(packet.bytes)); continue }
            let positions = try MovementHistoryDecoder.decode(X6Frame(packet.bytes), packet: packet, calendar: calendar)
            XCTAssertEqual(positions.count, 180)
            XCTAssertEqual(positions.map(\.rawValue), Array(packet.bytes.dropFirst(8)))
            XCTAssertEqual(positions.first?.minuteOffset, Int(Array(packet.bytes)[7])*180)
        }
        let future = try XCTUnwrap(replay.movementSamples?.filter { $0.page == 6 })
        XCTAssertEqual(future.count, 180)
        XCTAssertTrue(future.allSatisfy { $0.rawValue == 0 && $0.availability == .future })
        XCTAssertTrue(replay.samples.isEmpty)
        XCTAssertEqual(replay.schemaVersion, 3)
        var p = SyncProgress(command: .movement, deviceID: original.packets[0].deviceID, startedAt: now)
        var processor = PacketProcessor(), scratch = LocalArchive()
        for packet in original.packets { processor.process(packet, archive: &scratch).receipts.forEach { p.received($0) } }
        XCTAssertEqual(p.missingPages, [4,5,7])
    }
    func testAutomaticAndExplicitReplayDeduplicatesMinutePositions() throws {
        var processor = PacketProcessor(), archive = LocalArchive(), p = start()
        let first = try receipt(0, at: 0.1, value: 128)
        processor.process(first.packet, archive: &archive).receipts.forEach { p.received($0) }
        assertWrite(&p, page: 1, at: 1)
        for page: UInt8 in [1,1,0,7,2,3,6,4,5] {
            let r = try receipt(page, at: 1.1)
            processor.process(r.packet, archive: &archive).receipts.forEach { p.received($0) }
        }
        XCTAssertTrue(p.isComplete); XCTAssertEqual(archive.movementSamples?.count, 1440)
        XCTAssertEqual(archive.movementSamples?.filter { $0.rawValue == 128 }.count, 180)
        XCTAssertTrue(archive.samples.isEmpty)
    }
    func testReportedPhysicalHRVAndTemperatureReceiptSequencesComplete() throws {
        struct Report: Decodable { struct Sequence: Decodable { let feature: String; let variants: [String]; let byteCounts: [Int]; let sampleCounts: [Int] }; let sequences: [Sequence] }
        let report = try JSONDecoder().decode(Report.self, from: fixture("reported-sync-sequences"))
        for seq in report.sequences {
            let command: X6Command = seq.feature == "0210" ? .hrv : .temperature
            var p = SyncProgress(command: command, deviceID: "reported-X6", startedAt: now)
            p.wrote(command.bytes, at: now)
            for page in 0..<4 {
                if page > 0 { p.wrote(try XCTUnwrap(p.continuation), at: now.addingTimeInterval(Double(page))) }
                // Metadata replay of reported physical diagnostics. The placeholder body
                // is constructed, not decoded or claimed as captured HRV/temperature bytes.
                let bytes = Data([0xFD,0xDA,0x10,152,2,UInt8(seq.feature.suffix(2), radix: 16)!,0,UInt8(page)] + Array(repeating: UInt8(0), count: 144))
                let packet = RawPacket(deviceID: "reported-X6", characteristic: "FDD3", direction: .rx, bytes: bytes, timestamp: now.addingTimeInterval(Double(page)+0.1))
                XCTAssertEqual(bytes.count, seq.byteCounts[page])
                p.received(FrameReceipt(packet: packet, frame: try X6Frame(bytes), sampleCount: seq.sampleCounts[page], error: nil))
            }
            p.finish(at: now.addingTimeInterval(4))
            XCTAssertTrue(p.diagnostic.complete)
            XCTAssertEqual(p.diagnostic.writes.map(\.variantHex), seq.variants)
            XCTAssertEqual(p.diagnostic.responses.map(\.sampleCount), seq.sampleCounts)
            XCTAssertEqual(p.diagnostic.responses.suffix(2).map(\.status), ["Valid empty response","Valid empty response"])
        }
    }
    func testPeriodicHRRemainsPartialWithoutInventedSelector() throws {
        var p = SyncProgress(command: .periodicHeartRate, deviceID: "constructed", startedAt: now)
        p.wrote(X6Command.periodicHeartRate.bytes, at: now)
        let bytes = Data([0xFD,0xDA,0x10,152,2,0x0F,0,0] + Array(repeating: UInt8(0), count: 144))
        let packet = RawPacket(deviceID: "constructed", characteristic: "FDD3", direction: .rx, bytes: bytes, timestamp: now)
        p.received(FrameReceipt(packet: packet, frame: try X6Frame(bytes), sampleCount: 17, error: nil))
        XCTAssertNil(p.continuation)
        p.finish(at: now.addingTimeInterval(8))
        XCTAssertEqual(p.diagnostic.reason, "Timed out; missing 0001; continuation selector not validated")
    }
    func testSecondNightMidnightGapAndVendorPointsRemainSeparate() throws {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let reference = try decoder.decode(SleepReference.self, from: fixture("sleep-reference"))
        let vendor = try decoder.decode([VendorObservation].self, from: fixture("vendor-observations"))
        let archive = PacketProcessor.reprocess(try capture())
        let result = try SleepAlignment.align(archive: archive, reference: reference, vendorObservations: vendor)
        XCTAssertEqual(reference.intervals.count, 46)
        XCTAssertEqual(result.rows.count, 545)
        XCTAssertEqual(result.stages.map(\.labeledMinutes), [273,221,48,3])
        XCTAssertTrue(result.rows.prefix(30).allSatisfy { $0.movementRaw == nil })
        XCTAssertTrue(result.rows.dropFirst(30).allSatisfy { $0.movementRaw != nil })
        XCTAssertEqual(result.stages.reduce(0) { $0 + $1.missingMovementMinutes }, 30)
        XCTAssertTrue(result.rows.allSatisfy { $0.heartRate.isEmpty && $0.sdnn.isEmpty && $0.spo2.isEmpty })
        XCTAssertGreaterThan(result.rows.flatMap { $0.vendorObservations ?? [] }.count, 0)
        XCTAssertEqual(result.rows.flatMap { $0.vendorObservations ?? [] }.count, vendor.filter { $0.timestamp >= reference.intervals[0].start && $0.timestamp < reference.intervals.last!.end }.count)
        XCTAssertTrue(archive.samples.isEmpty) // reference labels never create production metrics
        XCTAssertEqual(result.stages.last?.movementRaw.count, 0) // all Awake is before midnight
        let transitions = SleepAlignment.transitions(in: result)
        XCTAssertEqual(transitions.labeledTransitions, 45)
        XCTAssertEqual(transitions.observedTransitions, 42)
        XCTAssertEqual(transitions.transitionAbsoluteChange.count + transitions.nontransitionAbsoluteChange.count, 514)
        let empty = try SleepAlignment.align(archive: LocalArchive(), reference: reference)
        XCTAssertEqual(SleepAlignment.transitions(in: empty).observedTransitions, 0)
        XCTAssertEqual(empty.rows.map(\.groundTruthStage), result.rows.map(\.groundTruthStage))
    }
}
