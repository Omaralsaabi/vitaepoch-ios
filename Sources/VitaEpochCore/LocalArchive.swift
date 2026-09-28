import Foundation

/// Atomic, local JSON archive for the initial device-validation build. All raw notifications
/// and reassembled frames survive decoder changes. No silent packet retention cutoff.
public struct LocalArchive: Codable, Sendable {
    public var samples: [MetricSample] = []
    public var packets: [RawPacket] = []
    public var lastSync: Date?
    public var schemaVersion: Int? = 3
    public var previousDecodes: [MetricSample]?
    public var timestampReferences: [ManualTimestampReference]?
    public var movementSamples: [MinuteMovementSample]?
    public var syncDiagnostics: [SyncDiagnostic]?
    public init() {}
    public mutating func ingest(_ incoming: [MetricSample]) {
        var byID = Dictionary(samples.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for sample in incoming { byID[sample.id] = sample }
        samples = byID.values.sorted { $0.timestamp < $1.timestamp }
    }
    public mutating func ingestMovement(_ incoming: [MinuteMovementSample]) {
        var byID = Dictionary((movementSamples ?? []).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for sample in incoming {
            // Repeated future/zero placeholders cannot erase previously observed raw signal.
            if let previous = byID[sample.id], previous.availability == .observedRawSignal,
               sample.availability != .observedRawSignal { continue }
            byID[sample.id] = sample
        }
        movementSamples = byID.values.sorted { $0.id < $1.id }
    }
    public static func read(from url: URL) throws -> Self {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
