import Foundation
import XCTest
@testable import VitaEpochCore

final class ProtocolTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_424_000)
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 10800)!; return c }
    func packet(_ hex: String, characteristic: String = "FDD3") -> RawPacket {
        RawPacket(deviceID: "fixture-X6", characteristic: characteristic, direction: .rx, bytes: Data(hex: hex)!, timestamp: now)
    }
    func decode(_ hex: String) throws -> [MetricSample] {
        let p = packet(hex)
        return try X6Decoder.decode(X6Frame(p.bytes), packet: p, calendar: calendar)
    }
    func testConfirmedManualFixtures() throws {
        let hr = try decode("FDDA102A02090740B86DB76A4A356EB76A56A16EB76A4A1370B76A4BBB70B76A4A5C74B76A5BD274B76A")
        XCTAssertEqual(hr.map(\.value), [64,74,86,74,75,74,91])
        XCTAssertEqual(hr[0].timestamp.timeIntervalSince1970, Double(0x6AB76DB8))
        XCTAssertEqual(try decode("FDDA101B020B0462CB71B76A612B72B76A634E73B76A633EA0B76A").map(\.value), [98,97,99,99])
        XCTAssertEqual(try decode("FDDA1011021902165584B76A245F85B76A").map(\.value), [22,36])
    }
    func testActivityFixturesAndUnknownFieldIsNotDecoded() throws {
        let activity = try decode("FDDA1017020D00A2010000E093040000000000666D0000")
        XCTAssertEqual(activity.map(\.value), [418,30,280.06])
        let compact = try X6Decoder.compactActivity(packet("D00100360100200000", characteristic: "FDD1"), calendar: calendar)
        XCTAssertEqual(compact.map(\.value), [464,310,32])
        XCTAssertEqual(Set(compact.map(\.confidence)), [.provisionalLayout])
    }
    func testHeartRateFlagsAndTruncation() throws {
        XCTAssertEqual(try X6Decoder.heartRate(packet("064B", characteristic: "2A37")).first?.value, 75)
        XCTAssertEqual(try X6Decoder.heartRate(packet("012C01", characteristic: "2A37")).first?.value, 300)
        XCTAssertThrowsError(try X6Decoder.heartRate(packet("01FF")))
        XCTAssertThrowsError(try X6Decoder.heartRate(packet("084B")))
        XCTAssertThrowsError(try X6Decoder.heartRate(packet("104B01")))
        XCTAssertTrue(try X6Decoder.heartRate(packet("0600")).isEmpty)
    }
    func paged(_ feature: UInt8, day: UInt8 = 0, page: UInt8, slot: Int, value: UInt16) -> RawPacket {
        var bytes: [UInt8] = [0xFD,0xDA,0x10,152,2,feature,day,page] + Array(repeating: 0, count: 144)
        let index = 8 + slot * (feature == 0x0F ? 6 : 2)
        bytes[index] = UInt8(value & 255); bytes[index+1] = UInt8(value >> 8)
        return RawPacket(deviceID: "fixture-X6", characteristic: "FDD3", direction: .rx, bytes: Data(bytes), timestamp: now)
    }
    func testPagingTimeGridAndMissingValues() throws {
        for (feature, page, slot, value, expectedHour, expectedMinute, expectedValue) in [
            (UInt8(0x0F),UInt8(1),1,UInt16(101),12,30,101.0),
            (UInt8(0x10),UInt8(2),48,UInt16(11),16,0,11.0),
            (UInt8(0x16),UInt8(0),1,UInt16(363),0,5,36.3)
        ] {
            let p = paged(feature, day: 1, page: page, slot: slot, value: value)
            let result = try X6Decoder.decode(X6Frame(p.bytes), packet: p, calendar: calendar)
            XCTAssertEqual(result.count, 1)
            XCTAssertEqual(result[0].value, expectedValue)
            XCTAssertEqual(calendar.component(.hour, from: result[0].timestamp), expectedHour)
            XCTAssertEqual(calendar.component(.minute, from: result[0].timestamp), expectedMinute)
            XCTAssertEqual(calendar.startOfDay(for: result[0].timestamp), calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)))
            XCTAssertEqual(result[0].packetID, p.id)
        }
    }
    func testMalformedAndUnknownFrames() throws {
        XCTAssertThrowsError(try X6Frame(Data(hex: "FDDA1011021900")!))
        XCTAssertThrowsError(try decode("FDDA1007020901"))
        XCTAssertThrowsError(try decode("FDDA1007021300"))
        let invalid = paged(0x10, page: 4, slot: 0, value: 1)
        XCTAssertThrowsError(try X6Decoder.decode(X6Frame(invalid.bytes), packet: invalid))
        for count in 0..<17 {
            let b = Data([0xFD,0xDA,0x10,UInt8(count+6),2,0x0D] + Array(repeating: UInt8(0), count: count))
            XCTAssertThrowsError(try X6Decoder.decode(X6Frame(b), packet: packet("00")))
        }
    }
    func testAssemblerFragmentationCoalescingAndResynchronization() {
        let frame = Data(hex: "FDDA1011021902165584B76A245F85B76A")!
        for cut in 1..<frame.count {
            var assembler = X6FrameAssembler()
            XCTAssertTrue(assembler.append(frame.prefix(cut)).isEmpty)
            XCTAssertEqual(assembler.append(frame.dropFirst(cut)), [frame])
        }
        var assembler = X6FrameAssembler()
        XCTAssertEqual(assembler.append(Data([1,2,3]) + frame + frame), [frame,frame])
        _ = assembler.append(frame.prefix(5)); assembler.reset()
        XCTAssertEqual(assembler.append(frame), [frame])
    }
    func testZeroStressIsPreservedAndActivitySnapshotIsReplaced() throws {
        // Synthetic boundary case: a zero score must not be confused with missing HRV slots.
        XCTAssertEqual(try decode("FDDA100C021901005584B76A").map(\.value), [0])
        var archive = LocalArchive()
        let initial = try X6Decoder.compactActivity(packet("D00100360100200000"), calendar: calendar)
        let updated = try X6Decoder.compactActivity(packet("D10100360100200000"), calendar: calendar)
        archive.ingest(initial); archive.ingest(updated)
        XCTAssertEqual(archive.samples.count, 3)
        XCTAssertEqual(archive.samples.first { $0.metric == .steps }?.value, 465)
    }
    func testCommandsAreValidAndLimitedToKnownFeatures() throws {
        for command in X6Command.allCases { XCTAssertNoThrow(try X6Frame(command.bytes)) }
        XCTAssertEqual(X6Command.startHeartRate.bytes.hex, "FDDA1007010901")
        XCTAssertEqual(X6Command.temperature.bytes.hex, "FDDA100802160000")
        XCTAssertEqual(X6Command.sync.count, 7)
    }
    func testPersistenceDeduplicationAndEvidence() throws {
        let p = packet("FDDA1011021902165584B76A245F85B76A")
        let readings = try X6Decoder.decode(X6Frame(p.bytes), packet: p)
        var archive = LocalArchive(); archive.packets.append(p)
        archive.ingest(readings); archive.ingest(readings)
        XCTAssertEqual(archive.samples.count, 2)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "archive.json")
        try archive.write(to: url)
        let restored = try LocalArchive.read(from: url)
        XCTAssertEqual(restored.samples, readings)
        XCTAssertEqual(restored.packets[0].bytes, p.bytes)
        XCTAssertEqual(restored.samples[0].packetID, restored.packets[0].id)
        let otherDevice = RawPacket(deviceID: "second-device", characteristic: "FDD3", direction: .rx, bytes: p.bytes)
        archive.ingest(try X6Decoder.decode(X6Frame(p.bytes), packet: otherDevice))
        XCTAssertEqual(archive.samples.count, 4)
    }
}
