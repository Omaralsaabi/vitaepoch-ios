import Foundation

public enum HRVStatistic: String, Codable, Sendable { case sdnn, unknown }
public enum SemanticStatus: String, Codable, Sendable { case confirmed, strongInference, provisional, unknown }
public struct SemanticEvidence: Codable, Equatable, Sendable {
    public let status: SemanticStatus
    public let sourceID: String
    public let description: String
    public let firmware: String?
    public let serial: String?
}

/// Applies only to the identified device/firmware and vendor-export path in the handoff.
/// A vendor's SDNN designation confirms the statistic label, not clinical accuracy.
public struct VerifiedX6Profile: Codable, Equatable, Sendable {
    public let serial: String
    public let firmware: String
    public var confirmsSDNN: Bool { serial == "EDA75689" && firmware == "MOY-I4E3-1.1.6" }
    public var sdnnEvidence: SemanticEvidence? {
        guard confirmsSDNN else { return nil }
        return SemanticEvidence(status: .confirmed, sourceID: "da-halo-health-export-2026-09-27-hrv-sdnn",
            description: "Da Halo export: HKQuantityTypeIdentifierHeartRateVariabilitySDNN, ms; values matched X6 0210. Reported in the 27 Sep handoff.",
            firmware: firmware, serial: serial)
    }
    public static func profiles(in packets: [RawPacket]) -> [String: Self] {
        var result: [String: Self] = [:]
        for (device, packets) in Dictionary(grouping: packets, by: \.deviceID) {
            let serial = packets.last { $0.characteristic == "2A25" }.flatMap { String(data: $0.bytes, encoding: .utf8) }
            let firmware = packets.last { $0.characteristic == "2A28" }.flatMap { String(data: $0.bytes, encoding: .utf8) }
            // Imported captures can carry explicit profile metadata, without invented BLE reads.
            let captured = packets.compactMap { $0.captureEvidence?.deviceProfile }.last
            if let serial, let firmware { result[device] = Self(serial: serial, firmware: firmware) }
            else if let captured { result[device] = captured }
        }
        return result
    }
}

public struct CaptureEvidence: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case physicalTranscription, physicalArchive, constructed }
    public let kind: Kind
    public let sourceID: String
    public let note: String
    public let deviceProfile: VerifiedX6Profile?
}
