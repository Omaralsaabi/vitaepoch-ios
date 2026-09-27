import Foundation

public enum MetricKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case heartRate, hrv, oxygen, stress, wristTemperature, steps, distance, calories
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .heartRate: "Heart Rate"
        case .hrv: "HRV"
        case .oxygen: "SpO₂"
        case .stress: "Stress Score"
        case .wristTemperature: "Wrist Temperature"
        case .steps: "Steps"
        case .distance: "Distance"
        case .calories: "Calories"
        }
    }
    public var unit: String {
        switch self {
        case .heartRate: "bpm"
        case .hrv: "ms"
        case .oxygen: "%"
        case .stress: "points"
        case .wristTemperature: "°C"
        case .steps: "steps"
        case .distance: "m"
        case .calories: "kcal"
        }
    }
}

public enum SampleMethod: String, Codable, Sendable { case manual, periodic, dailySummary, live }
public enum MetricSource: String, Codable, Sendable { case x6 }
public enum MetricConfidence: String, Codable, Sendable { case deviceReported, provisionalLayout }

public struct MetricSample: Codable, Identifiable, Equatable, Sendable {
    public let metric: MetricKind
    public let value: Double
    public let timestamp: Date
    public let source: MetricSource
    public let method: SampleMethod
    public let confidence: MetricConfidence
    public let feature: String
    public let deviceID: String
    public let packetID: UUID
    public let decoderVersion: String
    public let timestampEvidence: TimestampEvidence?
    // A daily summary is a replaceable snapshot; manual and periodic readings are immutable slots.
    public var id: String { "\(deviceID)|\(source.rawValue)|\(feature)|\(metric.rawValue)|\(method.rawValue)|\(timestamp.timeIntervalSince1970)" }
    public init(metric: MetricKind, value: Double, timestamp: Date, method: SampleMethod,
                feature: String, deviceID: String, packetID: UUID, confidence: MetricConfidence = .deviceReported, timestampEvidence: TimestampEvidence? = nil) {
        self.metric = metric; self.value = value; self.timestamp = timestamp; self.method = method
        self.feature = feature; self.deviceID = deviceID; self.packetID = packetID
        self.confidence = confidence; source = .x6; decoderVersion = "x6-v0.2"
        self.timestampEvidence = timestampEvidence
    }
}

public struct RawPacket: Codable, Identifiable, Sendable {
    public enum Direction: String, Codable, Sendable { case tx, rx }
    public let id: UUID
    public let timestamp: Date
    public let deviceID: String
    public let characteristic: String
    public let direction: Direction
    public let bytes: Data
    public let timeZoneID: String?
    public init(deviceID: String, characteristic: String, direction: Direction, bytes: Data, timestamp: Date = Date(), timeZoneID: String = TimeZone.current.identifier) {
        id = UUID(); self.timestamp = timestamp; self.deviceID = deviceID
        self.characteristic = characteristic; self.direction = direction; self.bytes = bytes; self.timeZoneID = timeZoneID
    }
}

public extension Data {
    var hex: String { map { String(format: "%02X", $0) }.joined() }
    init?(hex: String) {
        let chars = Array(hex.filter { !$0.isWhitespace })
        guard chars.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8]()
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let b = UInt8(String(chars[i...i+1]), radix: 16) else { return nil }
            bytes.append(b)
        }
        self.init(bytes)
    }
}
