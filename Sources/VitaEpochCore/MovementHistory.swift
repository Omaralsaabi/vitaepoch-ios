import Foundation

/// Bounded DDPP selector. Only 0100 and 0107 were physically observed for day 1;
/// the remaining day-1 pages use the supported selector structure, not new evidence.
public struct MovementSelector: Equatable, Hashable, Sendable {
    public let dayOffset: UInt8
    public let page: UInt8
    public init(dayOffset: UInt8, page: UInt8) throws {
        guard dayOffset <= 1, page < 8 else { throw ProtocolError.invalidPage }
        self.dayOffset = dayOffset; self.page = page
    }
    public var hex: String { String(format: "%02X%02X", dayOffset, page) }
    public var request: Data { Data([0xFD,0xDA,0x10,8,2,0x13,dayOffset,page]) }
    public var physicallyObserved: Bool { dayOffset == 0 || page == 0 || page == 7 }
}

/// Diagnostics/research data only. No physical units, activity score or sleep-stage mapping.
public struct MinuteMovementSample: Codable, Identifiable, Equatable, Sendable {
    public enum Availability: String, Codable, Sendable { case observedRawSignal, zeroUninterpreted, future, unrepresentableLocalTime }
    public let day: Date
    public let localMinute: Date?
    public let minuteOffset: Int
    public let rawValue: UInt8
    public let page: UInt8
    public let indexInPage: UInt16
    public let deviceID: String
    public let source: MetricSource
    public let packetID: UUID
    public let decoderVersion: String
    public let timeZoneID: String
    public let semanticEvidence: SemanticEvidence
    public let availability: Availability
    public var id: String { "\(deviceID)|0213|\(day.timeIntervalSince1970)|\(minuteOffset)" }
    /// Recover explicit DDPP evidence from the stored packet instead of duplicating
    /// persisted fields. Works with schema-3 records, including pre-change samples.
    public func selector(from packet: RawPacket) -> MovementSelector? {
        guard packet.id == packetID, packet.deviceID == deviceID,
              let frame = try? X6Frame(packet.bytes), frame.group == 2, frame.feature == 0x13,
              frame.payload.count == 182, frame.payload[1] == page else { return nil }
        return try? MovementSelector(dayOffset: frame.payload[0], page: page)
    }
}

public enum MovementHistoryDecoder {
    public static func decode(_ frame: X6Frame, packet: RawPacket, calendar: Calendar) throws -> [MinuteMovementSample] {
        guard frame.group == 2, frame.feature == 0x13 else { throw ProtocolError.unsupportedFeature(frame.feature) }
        guard frame.payload.count == 182 else { throw ProtocolError.invalidPayload }
        let selector = try MovementSelector(dayOffset: frame.payload[0], page: frame.payload[1])
        let page = selector.page
        guard let day = calendar.date(byAdding: .day, value: -Int(selector.dayOffset), to: calendar.startOfDay(for: packet.timestamp)) else { throw ProtocolError.invalidPayload }
        return (0..<180).map { slot in
            let minute = Int(page)*180 + slot
            let candidate = calendar.date(bySettingHour: minute/60, minute: minute%60, second: 0, of: day)
            let date = candidate.flatMap { date in
                calendar.isDate(date, inSameDayAs: day) && calendar.component(.hour, from: date) == minute/60 && calendar.component(.minute, from: date) == minute%60 ? date : nil
            }
            let raw = frame.payload[2+slot]
            let availability: MinuteMovementSample.Availability
            if let date {
                availability = date > packet.timestamp ? .future : raw == 0 ? .zeroUninterpreted : .observedRawSignal
            } else { availability = .unrepresentableLocalTime }
            return MinuteMovementSample(day: day, localMinute: date, minuteOffset: minute, rawValue: raw,
                page: page, indexInPage: UInt16(slot), deviceID: packet.deviceID, source: .x6, packetID: packet.id,
                decoderVersion: "x6-movement-v0.2", timeZoneID: calendar.timeZone.identifier,
                semanticEvidence: SemanticEvidence(status: .strongInference, sourceID: selector.dayOffset == 1 ? "x6-0213-2026-09-28-previous-day" : "x6-0213-2026-09-27-minute-growth",
                    description: "Selector \(selector.hex), day offset \(selector.dayOffset). 180 raw minute positions/page; movement-like signal with unknown amplitude meaning. Not sleep stages.",
                    firmware: packet.captureEvidence?.deviceProfile?.firmware, serial: packet.captureEvidence?.deviceProfile?.serial),
                availability: availability)
        }
    }
}
