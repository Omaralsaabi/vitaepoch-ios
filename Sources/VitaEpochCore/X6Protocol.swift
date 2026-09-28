import Foundation

public enum ProtocolError: Error, Equatable { case malformedFrame, invalidPayload, unsupportedFeature(UInt8), invalidPage }

public struct X6Frame: Sendable {
    public let group: UInt8
    public let feature: UInt8
    public let payload: [UInt8]
    public init(_ data: Data) throws {
        let b = Array(data)
        guard b.count >= 6, b[0...2] == [0xFD, 0xDA, 0x10][...], Int(b[3]) == b.count else {
            throw ProtocolError.malformedFrame
        }
        group = b[4]; feature = b[5]; payload = Array(b.dropFirst(6))
    }
}

/// Reassembles fragments and coalesced frames. An incomplete frame is retained until the
/// next notification; reset on connection changes so bytes from different sessions never mix.
public struct X6FrameAssembler: Sendable {
    private var buffer: [UInt8] = []
    public init() {}
    public var bufferedByteCount: Int { buffer.count }
    public mutating func reset() { buffer.removeAll() }
    public mutating func append(_ data: Data) -> [Data] {
        buffer.append(contentsOf: data)
        var frames: [Data] = []
        while buffer.count >= 4 {
            guard buffer[0] == 0xFD, buffer[1] == 0xDA, buffer[2] == 0x10, buffer[3] >= 6 else {
                buffer.removeFirst(); continue
            }
            let length = Int(buffer[3])
            guard buffer.count >= length else { break }
            frames.append(Data(buffer.prefix(length)))
            buffer.removeFirst(length)
        }
        return frames
    }
}

public enum X6Command: CaseIterable, Sendable {
    case activity, manualHeartRate, oxygen, stress, periodicHeartRate, hrv, temperature, movement, startHeartRate, stopHeartRate
    public var bytes: Data {
        switch self {
        case .activity: Data([0xFD,0xDA,0x10,7,2,0x0D,0])
        case .manualHeartRate: Data([0xFD,0xDA,0x10,7,2,9,0])
        case .oxygen: Data([0xFD,0xDA,0x10,7,2,0x0B,0])
        case .stress: Data([0xFD,0xDA,0x10,8,2,0x19,0,0])
        case .periodicHeartRate: Data([0xFD,0xDA,0x10,7,2,0x0F,0])
        case .hrv: Data([0xFD,0xDA,0x10,8,2,0x10,0,0])
        case .temperature: Data([0xFD,0xDA,0x10,8,2,0x16,0,0])
        case .movement: Data([0xFD,0xDA,0x10,8,2,0x13,0,0])
        case .startHeartRate: Data([0xFD,0xDA,0x10,7,1,9,1])
        case .stopHeartRate: Data([0xFD,0xDA,0x10,7,1,9,0])
        }
    }
    public static var sync: [X6Command] { [.activity, .manualHeartRate, .oxygen, .stress, .periodicHeartRate, .hrv, .temperature] }
}

public enum X6Decoder {
    public static func decode(_ frame: X6Frame, packet: RawPacket, calendar: Calendar = .current, reference: ManualTimestampReference? = nil, profile: VerifiedX6Profile? = nil) throws -> [MetricSample] {
        guard frame.group == 2 else { throw ProtocolError.unsupportedFeature(frame.feature) }
        let b = frame.payload
        let feature = String(format: "02%02X", frame.feature)
        func sample(_ metric: MetricKind, _ value: Double, _ date: Date, _ method: SampleMethod,
                    _ confidence: MetricConfidence = .deviceReported, _ evidence: TimestampEvidence? = nil) -> MetricSample {
            MetricSample(metric: metric, value: value, timestamp: date, method: method, feature: feature,
                         deviceID: packet.deviceID, packetID: packet.id, confidence: confidence, timestampEvidence: evidence,
                         hrvStatistic: metric == .hrv ? (profile?.confirmsSDNN == true ? .sdnn : .unknown) : nil,
                         semanticEvidence: metric == .hrv ? profile?.sdnnEvidence : metric == .wristTemperature ?
                            SemanticEvidence(status: .provisional, sourceID: "x6-0216-physical-captures",
                                description: "Little-endian tenths interpreted as wrist temperature; no independent temperature ground truth.",
                                firmware: profile?.firmware, serial: profile?.serial) : nil)
        }
        switch frame.feature {
        case 9, 0x0B, 0x19:
            guard let count = b.first, b.count == 1 + Int(count) * 5 else { throw ProtocolError.invalidPayload }
            let kind: MetricKind = frame.feature == 9 ? .heartRate : frame.feature == 0x0B ? .oxygen : .stress
            return stride(from: 1, to: b.count, by: 5).compactMap { i in
                guard kind == .stress || b[i] != 0 else { return nil }
                let raw = u32(b, i+1)
                let resolved = reference?.resolve(raw: raw, feature: frame.feature, deviceID: packet.deviceID)
                var evidence = resolved?.1 ?? TimestampEvidence(basis: .unixUnverified, rawSeconds: raw,
                    timeZoneID: calendar.timeZone.identifier)
                evidence.rawBytesHex = Data(b[(i+1)...(i+4)]).hex
                return sample(kind, Double(b[i]), resolved?.0 ?? Date(timeIntervalSince1970: Double(raw)), .manual,
                              .deviceReported, evidence)
            }
        case 0x0D:
            guard b.count == 17 else { throw ProtocolError.invalidPayload }
            let date = try day(b[0], packet.timestamp, calendar)
            let evidence = TimestampEvidence(basis: .localDaySlotProvisional, dayOffset: b[0], timeZoneID: calendar.timeZone.identifier)
            return [sample(.steps, Double(u32(b,1)), date, .dailySummary, .provisionalLayout, evidence),
                    sample(.calories, Double(u32(b,5))/10000, date, .dailySummary, .provisionalLayout, evidence),
                    sample(.distance, Double(u32(b,13))/100, date, .dailySummary, .provisionalLayout, evidence)]
        case 0x0F, 0x10, 0x16:
            // A header-only page is an explicit empty page; arbitrary short bodies are not
            // assigned invented slot offsets. Full all-zero pages are valid too.
            guard b.count == 2 || b.count == 146 else { throw ProtocolError.invalidPayload }
            let isHR = frame.feature == 0x0F
            guard b[1] < (isHR ? 2 : 4) else { throw ProtocolError.invalidPage }
            if b.count == 2 { return [] }
            let base = try day(b[0], packet.timestamp, calendar)
            let slots = isHR ? 24 : 72
            let interval = isHR ? 30 : 5
            let kind: MetricKind = isHR ? .heartRate : frame.feature == 0x10 ? .hrv : .wristTemperature
            return (0..<slots).compactMap { slot in
                let raw = u16(b, 2 + slot * (isHR ? 6 : 2))
                guard raw != 0 else { return nil }
                let minute = (Int(b[1]) * slots + slot) * interval
                // Device slots describe local wall-clock time, not elapsed seconds across DST.
                guard let date = calendar.date(bySettingHour: minute/60, minute: minute%60, second: 0, of: base),
                      calendar.isDate(date, inSameDayAs: base),
                      calendar.component(.hour, from: date) == minute/60,
                      calendar.component(.minute, from: date) == minute%60 else {
                    // A nonexistent DST wall-clock slot must not silently become a different
                    // slot. The raw page remains available for a later timezone interpretation.
                    return nil
                }
                return sample(kind, Double(raw)/(kind == .wristTemperature ? 10 : 1), date, .periodic, .provisionalLayout,
                              TimestampEvidence(basis: .localDaySlotProvisional, dayOffset: b[0], page: b[1], slot: slot,
                                                timeZoneID: calendar.timeZone.identifier))
            }
        default: throw ProtocolError.unsupportedFeature(frame.feature)
        }
    }

    public static func heartRate(_ packet: RawPacket) throws -> [MetricSample] {
        let b = Array(packet.bytes)
        guard let flags = b.first, b.count >= (flags & 1 == 0 ? 2 : 3) else { throw ProtocolError.invalidPayload }
        var offset = flags & 1 == 0 ? 2 : 3
        if flags & 8 != 0 { offset += 2 }
        guard b.count >= offset, flags & 16 == 0 || (b.count > offset && (b.count-offset).isMultiple(of: 2)) else {
            throw ProtocolError.invalidPayload
        }
        let value = flags & 1 == 0 ? UInt16(b[1]) : u16(b,1)
        guard value > 0 else { return [] }
        return [MetricSample(metric: .heartRate, value: Double(value), timestamp: packet.timestamp,
                             method: .manual, feature: "2A37", deviceID: packet.deviceID, packetID: packet.id,
                             timestampEvidence: TimestampEvidence(basis: .receiptTime, timeZoneID: packet.timeZoneID ?? TimeZone.current.identifier))]
    }

    public static func compactActivity(_ packet: RawPacket, calendar: Calendar = .current) throws -> [MetricSample] {
        let b = Array(packet.bytes)
        guard b.count == 9 else { throw ProtocolError.invalidPayload }
        return [(MetricKind.steps,0),(.distance,3),(.calories,6)].map { kind, offset in
            MetricSample(metric: kind, value: Double(u16(b,offset)), timestamp: calendar.startOfDay(for: packet.timestamp),
                         method: .dailySummary, feature: "FDD1", deviceID: packet.deviceID, packetID: packet.id,
                         confidence: .provisionalLayout,
                         timestampEvidence: TimestampEvidence(basis: .localDaySlotProvisional, dayOffset: 0,
                                                              timeZoneID: calendar.timeZone.identifier))
        }
    }
    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i+1]) << 8 }
    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i+1]) << 8 | UInt32(b[i+2]) << 16 | UInt32(b[i+3]) << 24
    }
    private static func day(_ offset: UInt8, _ date: Date, _ calendar: Calendar) throws -> Date {
        guard let day = calendar.date(byAdding: .day, value: -Int(offset), to: calendar.startOfDay(for: date)) else {
            throw ProtocolError.invalidPage
        }
        return day
    }
}
