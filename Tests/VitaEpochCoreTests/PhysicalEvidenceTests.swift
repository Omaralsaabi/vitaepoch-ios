import Foundation
import XCTest
@testable import VitaEpochCore
import X6Research

final class PhysicalEvidenceTests: XCTestCase {
    func resource(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/physical-2026-09-27")))
    }
    func capture() throws -> LocalArchive { try JSONDecoder().decode(LocalArchive.self, from: resource("capture")) }
    func sleepReference() throws -> SleepReference { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return try decoder.decode(SleepReference.self, from: resource("sleep-reference")) }
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Amman")!; return c }
    var now: Date { calendar.date(from: DateComponents(year: 2026,month: 9,day: 27,hour: 18,minute: 58))! }
    func constructedMovement(_ page: UInt8, day: UInt8 = 0) -> RawPacket {
        let raw = (0..<180).map { UInt8(($0 + Int(page)) % 256) }
        return RawPacket(deviceID: "constructed-X6", characteristic: "FDD3", direction: .rx,
            bytes: Data([0xFD,0xDA,0x10,188,2,0x13,day,page] + raw), timestamp: now, timeZoneID: calendar.timeZone.identifier,
            captureEvidence: CaptureEvidence(kind: .constructed, sourceID: "eight-page-edge-case", note: "Constructed complete burst, not a repaired physical transcription.", deviceProfile: nil))
    }
    func testPhysicalHRVSDNNAndReportedExportTimes() throws {
        let archived = PacketProcessor.reprocess(try capture())
        let sdnn = archived.samples.filter { $0.metric == .hrv }.sorted { $0.timestamp < $1.timestamp }
        XCTAssertEqual(sdnn.map(\.value), [13,12,12,10,14,11,11,10,10,13,11,10])
        XCTAssertTrue(sdnn.allSatisfy { $0.resolvedHRVStatistic == .sdnn && $0.semanticEvidence?.status == .confirmed })
        XCTAssertTrue(sdnn.allSatisfy { $0.semanticEvidence?.sourceID == "da-halo-health-export-2026-09-27-hrv-sdnn" })
        for (i,sample) in sdnn.prefix(10).enumerated() {
            XCTAssertEqual(calendar.component(.hour, from: sample.timestamp), i/2)
            XCTAssertEqual(calendar.component(.minute, from: sample.timestamp), i.isMultiple(of: 2) ? 5 : 35)
        }
        let view = ArchiveSnapshot(archived, now: now, calendar: calendar)
        XCTAssertEqual(view.latest[.hrv]?.resolvedHRVStatistic, .sdnn)
        XCTAssertEqual(view.charts[.hrv]?[.day]?.records.count, 12)
    }
    func testSDNNDoesNotGeneralizeToUnknownFirmwareOrUnidentifiedDevice() throws {
        let p = try XCTUnwrap(capture().packets.first { $0.bytes.count == 152 })
        let frame = try X6Frame(p.bytes)
        XCTAssertTrue(try X6Decoder.decode(frame, packet: p, calendar: calendar).allSatisfy { $0.resolvedHRVStatistic == .unknown })
        let wrong = VerifiedX6Profile(serial: "EDA75689", firmware: "unverified-firmware")
        XCTAssertTrue(try X6Decoder.decode(frame, packet: p, calendar: calendar, profile: wrong).allSatisfy { $0.resolvedHRVStatistic == .unknown })
        let other = VerifiedX6Profile(serial: "other-device", firmware: "MOY-I4E3-1.1.6")
        XCTAssertFalse(other.confirmsSDNN)
    }
    func testAllFourSpO2TimestampsIndependentlyConfirmedStressStillProvisional() throws {
        let replay = PacketProcessor.reprocess(try capture())
        let oxygen = replay.samples.filter { $0.metric == .oxygen }.sorted { $0.timestamp < $1.timestamp }
        XCTAssertEqual(oxygen.map(\.value), [98,97,99,99])
        for (sample, expected) in zip(oxygen, [(15,18,35),(15,20,11),(15,25,2),(18,36,46)]) {
            let date = calendar.date(from: DateComponents(year: 2026,month: 9,day: 26,hour: expected.0,minute: expected.1,second: expected.2))!
            XCTAssertEqual(sample.timestamp, date)
            XCTAssertEqual(sample.timestampEvidence?.basis, .independentlyConfirmedVendorExport)
            XCTAssertEqual(sample.timestampEvidence?.adjustmentSeconds, 18000)
            XCTAssertEqual(sample.timestampEvidence?.referenceID, "da-halo-health-export-2026-09-27-spo2")
            XCTAssertNotNil(sample.timestampEvidence?.rawBytesHex)
        }
        let ref = try XCTUnwrap(replay.timestampReferences?.first)
        XCTAssertEqual(ref.resolve(raw: 0x6AB78455, feature: 0x19, deviceID: ref.deviceID)?.1.basis, .sharedManualReferenceProvisional)
        XCTAssertNil(ref.resolve(raw: 0x6AB771CB + 86400, feature: 0x0B, deviceID: ref.deviceID))
    }
    func testPhysicalTranscriptBytesRemainExactAndShortPagesStayPartial() throws {
        let original = try capture()
        let pages = original.packets.filter { $0.characteristic == "FDD3" && Array($0.bytes)[5] == 0x13 }
        XCTAssertEqual(pages.map { $0.bytes.count }, [188,188,188,188,188,188,186,186])
        var processor = PacketProcessor(); var archive = LocalArchive()
        var progress = SyncProgress(command: .movement, deviceID: pages[0].deviceID, startedAt: now.addingTimeInterval(-3))
        progress.wrote(X6Command.movement.bytes, at: now.addingTimeInterval(-3))
        for packet in pages {
            let result = processor.process(packet, archive: &archive)
            result.receipts.forEach { progress.received($0) }
        }
        XCTAssertEqual(archive.movementSamples?.count, 1080)
        XCTAssertEqual(progress.diagnostic.receivedPages, [0,1,2,3,4,5])
        XCTAssertEqual(progress.missingPages, [6,7])
        XCTAssertFalse(progress.isComplete)
        XCTAssertEqual(archive.packets.map(\.bytes), pages.map(\.bytes))
        for page in pages.prefix(6) {
            let decoded = try MovementHistoryDecoder.decode(X6Frame(page.bytes), packet: page, calendar: calendar)
            XCTAssertEqual(decoded.count, 180)
            XCTAssertEqual(decoded.map(\.rawValue), Array(page.bytes.dropFirst(8)))
            XCTAssertEqual(decoded.first?.minuteOffset, Int(Array(page.bytes)[7])*180)
        }
        XCTAssertNil(progress.continuation)
    }
    func testCompleteConstructedEightPageBurstDeduplicatesAndCompletesWithoutPageWrites() throws {
        var archive = LocalArchive(); var processor = PacketProcessor()
        var progress = SyncProgress(command: .movement, deviceID: "constructed-X6", startedAt: now)
        progress.wrote(X6Command.movement.bytes, at: now)
        for page: UInt8 in [3,0,7,1,4,2,6,5,0,7] {
            let result = processor.process(constructedMovement(page), archive: &archive)
            result.receipts.forEach { progress.received($0) }
            XCTAssertNil(progress.continuation)
        }
        XCTAssertEqual(archive.movementSamples?.count, 1440)
        XCTAssertTrue(progress.isComplete)
        XCTAssertEqual(progress.diagnostic.writes.map(\.bytesHex), ["FDDA100802130000"])
        XCTAssertTrue(archive.samples.isEmpty) // no physiological or sleep metric inferred
        XCTAssertTrue((archive.movementSamples ?? []).filter { $0.page == 7 }.allSatisfy { $0.availability == .future })
        XCTAssertEqual(archive.movementSamples?.first { $0.minuteOffset == 0 }?.availability, .zeroUninterpreted)
        XCTAssertThrowsError(try MovementHistoryDecoder.decode(X6Frame(constructedMovement(0, day: 2).bytes), packet: constructedMovement(0, day: 2), calendar: calendar))
    }
    func testPhysicalTemperatureExcerptIsNotFabricatedIntoFullFrame() throws {
        let original = try capture(), replay = PacketProcessor.reprocess(try capture())
        let excerpt = try XCTUnwrap(original.packets.first { $0.bytes.hex == "6B016A016C016901" })
        XCTAssertEqual(excerpt.captureEvidence?.kind, .physicalTranscription)
        XCTAssertTrue(replay.packets.contains { $0.id == excerpt.id && $0.bytes == excerpt.bytes })
        XCTAssertFalse(replay.samples.contains { $0.metric == .wristTemperature })
        // Decode values only in an explicitly constructed page with known positions.
        var bytes = [UInt8]([0xFD,0xDA,0x10,152,2,0x16,0,0]) + Array(excerpt.bytes) + Array(repeating: 0, count: 136)
        XCTAssertEqual(bytes.count, 152)
        let packet = RawPacket(deviceID: "constructed", characteristic: "FDD3", direction: .rx, bytes: Data(bytes), timestamp: now)
        let values = try X6Decoder.decode(X6Frame(packet.bytes), packet: packet, calendar: calendar)
        XCTAssertEqual(values.map(\.value), [36.3,36.2,36.4,36.1])
        XCTAssertTrue(values.allSatisfy { $0.semanticEvidence?.status == .provisional && $0.confidence == .provisionalLayout })
        bytes.removeLast()
        XCTAssertThrowsError(try X6Frame(Data(bytes)))
    }
    func testNegative020EAndUnknown0212ArePreservedAndNeverScheduled() throws {
        let original = try capture(), replay = PacketProcessor.reprocess(try capture())
        let negative = original.packets.filter { $0.bytes.count >= 6 && [UInt8(0x0E),0x12].contains(Array($0.bytes)[5]) }
        XCTAssertEqual(negative.count, 5)
        for packet in negative { XCTAssertTrue(replay.packets.contains { $0.id == packet.id && $0.bytes == packet.bytes }) }
        XCTAssertFalse(X6Command.allCases.contains { [UInt8(0x0E),0x12].contains(Array($0.bytes)[5]) })
    }
    func testOneNightAlignmentTotalsSparseDataAndNoStageInference() throws {
        let reference = try sleepReference()
        XCTAssertEqual(reference.intervals.count, 47)
        let archive = PacketProcessor.reprocess(try capture())
        let result = try SleepAlignment.align(archive: archive, reference: reference)
        XCTAssertEqual(result.rows.count, 552)
        XCTAssertEqual(result.stages.map(\.labeledMinutes), [260,218,11,63])
        XCTAssertTrue(result.rows.allSatisfy { $0.heartRate.isEmpty && $0.spo2.isEmpty })
        XCTAssertEqual(result.rows.flatMap(\.sdnn).count, 10)
        XCTAssertTrue(result.stages.allSatisfy { $0.raw80Minutes > 0 }) // 0x80 is NOT a stage code
        let noSignals = try SleepAlignment.align(archive: LocalArchive(), reference: reference)
        XCTAssertEqual(noSignals.rows.map(\.groundTruthStage), result.rows.map(\.groundTruthStage))
        XCTAssertTrue(noSignals.rows.allSatisfy { $0.movementRaw == nil && $0.sdnn.isEmpty })
    }
    func testKnownAndUnknownHRVDoNotShareDailyMedian() {
        let a = MetricSample(metric: .hrv, value: 12, timestamp: now, method: .periodic, feature: "0210", deviceID: "known", packetID: UUID(), hrvStatistic: .sdnn)
        let b = MetricSample(metric: .hrv, value: 100, timestamp: now.addingTimeInterval(-1), method: .periodic, feature: "0210", deviceID: "other", packetID: UUID(), hrvStatistic: .unknown)
        let series = MetricQueries.series(.hrv, samples: [a,b], packetDates: [:], range: .week, now: now, calendar: calendar)
        XCTAssertEqual(series.points.map(\.value), [12])
    }
}
