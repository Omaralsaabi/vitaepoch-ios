import Foundation
import XCTest
@testable import VitaEpochCore

final class StabilityTests: XCTestCase {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Amman")!; return c }
    func capturedData() throws -> Data { try Data(contentsOf: Bundle.module.url(forResource: "device-2026-09-26", withExtension: "json", subdirectory: "Fixtures")!) }
    func captured() throws -> LocalArchive { try JSONDecoder().decode(LocalArchive.self, from: capturedData()) }
    func packet(feature: UInt8, page: UInt8, values: [Int: UInt16] = [:], headerOnly: Bool = false) -> RawPacket {
        var bytes: [UInt8] = [0xFD,0xDA,0x10,headerOnly ? 8 : 152,2,feature,0,page]
        if !headerOnly {
            bytes += Array(repeating: 0, count: 144)
            for (slot,value) in values { let i = 8 + slot * (feature == 0x0F ? 6 : 2); bytes[i] = UInt8(value & 255); bytes[i+1] = UInt8(value >> 8) }
        }
        return RawPacket(deviceID: "constructed-X6", characteristic: "FDD3", direction: .rx, bytes: Data(bytes),
            timestamp: calendar.date(from: DateComponents(year: 2026,month: 9,day: 26,hour: 20))!, timeZoneID: calendar.timeZone.identifier)
    }
    func testCapturedManualReferenceAndRawEvidence() throws {
        let original = try captured()
        let replay = PacketProcessor.reprocess(original)
        let hr = try XCTUnwrap(replay.samples.first { $0.metric == .heartRate && $0.value == 91 })
        let local = calendar.dateComponents([.year,.month,.day,.hour,.minute,.second], from: hr.timestamp)
        XCTAssertEqual(local, DateComponents(year: 2026,month: 9,day: 26,hour: 15,minute: 31,second: 30))
        XCTAssertEqual(hr.timestampEvidence?.rawBytesHex, "D274B76A")
        XCTAssertEqual(hr.timestampEvidence?.rawSeconds, 0x6AB774D2)
        XCTAssertEqual(hr.timestampEvidence?.adjustmentSeconds, 18000)
        XCTAssertEqual(hr.timestampEvidence?.basis, .capturedManualReference)
        XCTAssertEqual(Set(original.packets.map(\.id)).subtracting(Set(replay.packets.map(\.id))), [])
        XCTAssertEqual(replay.previousDecodes?.count, original.samples.count)
        for metric in [MetricKind.oxygen,.stress] {
            let sample = try XCTUnwrap(replay.samples.first { $0.metric == metric })
            XCTAssertEqual(sample.timestampEvidence?.basis, .sharedManualReferenceProvisional)
            XCTAssertNotNil(sample.timestampEvidence?.rawSeconds)
        }
        // The same instant renders differently when traveling; it is not corrected a second time.
        var utc = calendar; utc.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(utc.component(.hour, from: hr.timestamp), 12)
    }
    func testReferenceDoesNotLeakToOtherDevicesDatesOrPageHistories() throws {
        let original = try captured()
        let ref = try XCTUnwrap(ManualTimestampReference.september26Reference(in: original.packets).values.first)
        XCTAssertNil(ref.resolve(raw: ref.rawSeconds, feature: 9, deviceID: "other-device"))
        XCTAssertNil(ref.resolve(raw: ref.rawSeconds + 86400, feature: 9, deviceID: ref.deviceID))
        XCTAssertNil(ref.resolve(raw: ref.rawSeconds, feature: 0x10, deviceID: ref.deviceID))
        let p = packet(feature: 0x10, page: 2, values: [48: 11])
        let result = try X6Decoder.decode(X6Frame(p.bytes), packet: p, calendar: calendar, reference: ref)
        XCTAssertEqual(calendar.component(.hour, from: result[0].timestamp), 16)
        XCTAssertEqual(result[0].timestampEvidence?.adjustmentSeconds, 0)
        let live = RawPacket(deviceID: ref.deviceID, characteristic: "2A37", direction: .rx, bytes: Data([6,91]), timestamp: p.timestamp)
        XCTAssertEqual(try X6Decoder.heartRate(live)[0].timestamp, p.timestamp)
    }
    func testCapturedSyncAuditIdentifiesExactThreeFailuresWithoutInventedData() throws {
        let original = try captured()
        let audit = LegacySyncAudit.inspect(original)
        XCTAssertEqual(audit.filter { !$0.complete }.map(\.featureID), ["020F","0210","0216","020F","0210","0216"])
        for request in audit.filter({ !$0.complete }) {
            XCTAssertEqual(request.receivedPages, [0])
            XCTAssertEqual(request.responses.filter { $0.featureID == request.featureID }.map(\.sampleCount), [0])
            XCTAssertEqual(request.writes.count, 1)
        }
        XCTAssertNil(audit.first { $0.featureID == "0216" }?.elapsed)
        XCTAssertNil(audit.last?.elapsed) // original app did not record the final timer firing
        let replay = PacketProcessor.reprocess(original)
        XCTAssertFalse(replay.samples.contains { $0.metric == .hrv || $0.metric == .wristTemperature })
    }
    func testConstructedHRVAndTemperatureSequenceSurvivesEmptyDuplicateAndOutOfOrderPages() throws {
        for (feature,kind,values) in [(UInt8(0x10),MetricKind.hrv,[UInt16(11),14,12,13,10]), (UInt8(0x16),.wristTemperature,[363,362,364])] {
            var archive = LocalArchive(); var processor = PacketProcessor()
            let command: X6Command = feature == 0x10 ? .hrv : .temperature
            let first = packet(feature: feature, page: 0)
            var sync = SyncProgress(command: command, deviceID: first.deviceID, startedAt: first.timestamp)
            sync.wrote(command.bytes, at: first.timestamp)
            let valuePage = packet(feature: feature, page: 2, values: Dictionary(uniqueKeysWithValues: values.enumerated().map { ($0.offset,$0.element) }))
            for p in [first, valuePage, packet(feature: feature, page: 1, headerOnly: true), valuePage, packet(feature: feature, page: 3)] {
                let result = processor.process(p, archive: &archive)
                XCTAssertNil(result.error)
                result.receipts.forEach { sync.received($0) }
            }
            XCTAssertTrue(sync.isComplete)
            XCTAssertEqual(archive.samples.filter { $0.metric == kind }.map(\.value), values.map { Double($0)/(feature == 0x16 ? 10 : 1) })
            XCTAssertTrue(archive.samples.allSatisfy { $0.confidence == .provisionalLayout && $0.timestampEvidence?.page == 2 })
            let snapshot = ArchiveSnapshot(archive, now: first.timestamp, calendar: calendar)
            XCTAssertNotNil(snapshot.latest[kind])
            XCTAssertEqual(snapshot.charts[kind]?[.day]?.points.count, values.count)
            XCTAssertEqual(snapshot.charts[kind]?[.week]?.points.count, 1)
        }
    }
    func testContinuationRequestsOnlyMissingKnownVariantsAndCountsEmptyPages() throws {
        let first = packet(feature: 0x10, page: 0)
        var sync = SyncProgress(command: .hrv, deviceID: first.deviceID, startedAt: first.timestamp)
        sync.wrote(X6Command.hrv.bytes, at: first.timestamp)
        sync.received(FrameReceipt(packet: first, frame: try X6Frame(first.bytes), sampleCount: 0, error: nil))
        XCTAssertFalse(sync.isComplete)
        XCTAssertEqual(sync.continuation?.hex, "FDDA100802100001")
        sync.wrote(sync.continuation!, at: first.timestamp)
        XCTAssertEqual(sync.continuation?.hex, "FDDA100802100002")
        for page: UInt8 in [1,2,3] {
            let p = packet(feature: 0x10, page: page)
            sync.received(FrameReceipt(packet: p, frame: try X6Frame(p.bytes), sampleCount: 0, error: nil))
        }
        sync.finish(at: first.timestamp.addingTimeInterval(1))
        XCTAssertTrue(sync.diagnostic.complete)
        XCTAssertNil(sync.continuation)
        var hr = SyncProgress(command: .periodicHeartRate, deviceID: "test", startedAt: first.timestamp)
        let p = packet(feature: 0x0F, page: 0)
        hr.received(FrameReceipt(packet: p, frame: try X6Frame(p.bytes), sampleCount: 0, error: nil))
        XCTAssertNil(hr.continuation) // do not guess the meaning of its one-byte selector
    }
    func testFragmentedAndCoalescedHistoryIngestion() throws {
        let a = packet(feature: 0x10, page: 0)
        let b = packet(feature: 0x10, page: 1, values: [0: 11, 1: 14])
        let bytes = a.bytes + b.bytes
        for split in [1,7,80,152,190,303] {
            var archive = LocalArchive(); var processor = PacketProcessor()
            for fragment in [Data(bytes.prefix(split)), Data(bytes.dropFirst(split))] {
                let p = RawPacket(deviceID: a.deviceID, characteristic: "FDD3", direction: .rx, bytes: fragment, timestamp: a.timestamp, timeZoneID: calendar.timeZone.identifier)
                XCTAssertNil(processor.process(p, archive: &archive).error)
            }
            XCTAssertEqual(archive.samples.map(\.value), [11,14])
            XCTAssertEqual(archive.packets.filter { $0.characteristic == "FDD3" }.map(\.bytes).reduce(Data(), +), bytes)
        }
    }
    func testDayIntradayAndWeekDailyAggregationAcrossMissingDates() throws {
        let base = calendar.date(from: DateComponents(year: 2026,month: 9,day: 26))!
        let now = base.addingTimeInterval(20*3600)
        var records: [MetricSample] = []
        for (hour,value) in [(1,10.0),(4,14.0),(-47,20.0)] {
            records.append(MetricSample(metric: .hrv, value: value, timestamp: base.addingTimeInterval(Double(hour)*3600), method: .periodic, feature: "0210", deviceID: "test", packetID: UUID()))
        }
        let day = MetricQueries.series(.hrv, samples: records, packetDates: [:], range: .day, now: now, calendar: calendar)
        XCTAssertEqual(day.points.map(\.timestamp), [base.addingTimeInterval(3600),base.addingTimeInterval(14400)])
        let week = MetricQueries.series(.hrv, samples: records, packetDates: [:], range: .week, now: now, calendar: calendar)
        XCTAssertEqual(week.points.map(\.value), [20,12])
        XCTAssertEqual(week.points.last?.timestamp, base)
        XCTAssertEqual(week.start, calendar.date(byAdding: .day, value: -6, to: base))
        XCTAssertEqual(week.records.count, 3)
        XCTAssertEqual(MetricQueries.series(.hrv, samples: [], packetDates: [:], range: .week, now: now, calendar: calendar).points.count, 0)
    }
    func testDayBoundariesUseCalendarAcrossDST() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026,month: 3,day: 8,hour: 18))!
        let series = MetricQueries.series(.hrv, samples: [], packetDates: [:], range: .day, now: now, calendar: calendar)
        XCTAssertEqual(series.end.timeIntervalSince(series.start), 23*3600)
    }
    func testNonexistentDSTHistorySlotIsNotShiftedIntoAnotherSlot() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let receipt = calendar.date(from: DateComponents(year: 2026,month: 3,day: 8,hour: 18))!
        let page = packet(feature: 0x16, page: 0, values: [30: 363,36: 364]) // 02:30 does not exist; 03:00 does
        let p = RawPacket(deviceID: "test", characteristic: "FDD3", direction: .rx, bytes: page.bytes, timestamp: receipt,
                          timeZoneID: calendar.timeZone.identifier)
        let samples = try X6Decoder.decode(X6Frame(p.bytes), packet: p, calendar: calendar)
        XCTAssertEqual(samples.map(\.value), [36.4])
        XCTAssertEqual(samples.first?.timestampEvidence?.slot, 36)
        XCTAssertEqual(calendar.component(.hour, from: samples[0].timestamp), 3)
    }

}
