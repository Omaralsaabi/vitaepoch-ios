import Foundation

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
}

public enum MovementHistoryDecoder {
    public static func decode(_ frame: X6Frame, packet: RawPacket, calendar: Calendar) throws -> [MinuteMovementSample] {
        guard frame.group == 2, frame.feature == 0x13 else { throw ProtocolError.unsupportedFeature(frame.feature) }
        guard frame.payload.count == 182 else { throw ProtocolError.invalidPayload }
        // Only current-day 00xx is supported by the supplied physical burst.
        guard frame.payload[0] == 0, frame.payload[1] < 8 else { throw ProtocolError.invalidPage }
        let page = frame.payload[1]
        let day = calendar.startOfDay(for: packet.timestamp)
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
                decoderVersion: "x6-movement-v0.1", timeZoneID: calendar.timeZone.identifier,
                semanticEvidence: SemanticEvidence(status: .strongInference, sourceID: "x6-0213-2026-09-27-minute-growth",
                    description: "180 raw minute positions/page; movement-like signal with unknown amplitude meaning. Not sleep stages.",
                    firmware: packet.captureEvidence?.deviceProfile?.firmware, serial: packet.captureEvidence?.deviceProfile?.serial),
                availability: availability)
        }
    }
}
