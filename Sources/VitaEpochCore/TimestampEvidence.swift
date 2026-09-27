import Foundation

public struct TimestampEvidence: Codable, Equatable, Sendable {
    public enum Basis: String, Codable, Sendable {
        case unixUnverified, capturedManualReference, sharedManualReferenceProvisional
        case localDaySlotProvisional, receiptTime
    }
    public var basis: Basis
    public var rawSeconds: UInt32?
    public var rawBytesHex: String?
    public var dayOffset: UInt8?
    public var page: UInt8?
    public var slot: Int?
    public var timeZoneID: String
    public var adjustmentSeconds: Double
    public var referenceID: String?
    public init(basis: Basis, rawSeconds: UInt32? = nil, rawBytesHex: String? = nil,
                dayOffset: UInt8? = nil, page: UInt8? = nil, slot: Int? = nil,
                timeZoneID: String, adjustmentSeconds: Double = 0, referenceID: String? = nil) {
        self.basis = basis; self.rawSeconds = rawSeconds; self.rawBytesHex = rawBytesHex
        self.dayOffset = dayOffset; self.page = page; self.slot = slot; self.timeZoneID = timeZoneID
        self.adjustmentSeconds = adjustmentSeconds; self.referenceID = referenceID
    }
}

/// A capture-specific calibration, not a universal epoch/timezone rule.
/// The known reference identifies wall-clock minutes; the captured seconds are retained.
public struct ManualTimestampReference: Codable, Equatable, Sendable {
    public let id: String
    public let deviceID: String
    public let rawSeconds: UInt32
    public let expectedInstant: Date
    public let timeZoneID: String
    public let rawDayStart: Date
    public let rawDayEnd: Date
    public var adjustment: TimeInterval { expectedInstant.timeIntervalSince1970 - Double(rawSeconds) }

    public static let capturedHR = "FDDA102A02090740B86DB76A4A356EB76A56A16EB76A4A1370B76A4BBB70B76A4A5C74B76A5BD274B76A"

    public static func september26Reference(in packets: [RawPacket]) -> [String: Self] {
        var references: [String: Self] = [:]
        let grouped = Dictionary(grouping: packets, by: \.deviceID)
        for (deviceID, packets) in grouped {
            // Match this device's identity and exact captured history, not a BPM coincidence.
            guard packets.contains(where: { $0.characteristic == "2A25" && $0.bytes == Data("EDA75689".utf8) }),
                  packets.contains(where: { $0.characteristic == "2A28" && $0.bytes == Data("MOY-I4E3-1.1.6".utf8) }),
                  packets.contains(where: { $0.direction == .rx && $0.bytes.hex == capturedHR }) else { continue }
            var local = Calendar(identifier: .gregorian)
            local.timeZone = TimeZone(identifier: "Asia/Amman")!
            let expected = local.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 15, minute: 31, second: 30))!
            var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
            let start = utc.date(from: DateComponents(year: 2026, month: 9, day: 26))!
            references[deviceID] = Self(id: "x6-EDA75689-20260926-91bpm", deviceID: deviceID,
                rawSeconds: 0x6AB774D2, expectedInstant: expected, timeZoneID: local.timeZone.identifier,
                rawDayStart: start, rawDayEnd: start.addingTimeInterval(86400))
        }
        return references
    }

    public func resolve(raw: UInt32, feature: UInt8, deviceID: String) -> (Date, TimestampEvidence)? {
        let instant = Date(timeIntervalSince1970: Double(raw))
        guard self.deviceID == deviceID, [9, 0x0B, 0x19].contains(feature),
              instant >= rawDayStart, instant < rawDayEnd else { return nil }
        let evidence = TimestampEvidence(
            basis: feature == 9 ? .capturedManualReference : .sharedManualReferenceProvisional,
            rawSeconds: raw, timeZoneID: timeZoneID, adjustmentSeconds: adjustment, referenceID: id)
        return (instant.addingTimeInterval(adjustment), evidence)
    }
}
