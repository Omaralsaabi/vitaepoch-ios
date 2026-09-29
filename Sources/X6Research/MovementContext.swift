import Foundation
import VitaEpochCore

/// Unlabeled, captured context for offline features. Does not create health samples.
public struct ResearchMovementPoint: Codable, Sendable {
    public let minute: Date
    public let rawValue: UInt8
    public let availability: MinuteMovementSample.Availability
    public let packetID: UUID
    public let selector: String?
}

public enum MovementContext {
    public static func points(archive: LocalArchive, reference: SleepReference) throws -> [ResearchMovementPoint] {
        try reference.validate()
        guard Set(archive.packets.map(\.deviceID)).count <= 1 else { throw AnalysisError.multipleDevices }
        // Session start -30 min needs another 29 prior minutes for a trailing 30m feature.
        let start = reference.intervals.first!.start.addingTimeInterval(-59 * 60)
        let end = reference.intervals.last!.end.addingTimeInterval(30 * 60)
        let packets = Dictionary(archive.packets.map { ($0.id, $0) }, uniquingKeysWith: { old, _ in old })
        return (archive.movementSamples ?? []).compactMap { sample -> ResearchMovementPoint? in
            guard let minute = sample.localMinute, minute >= start, minute <= end else { return nil }
            return ResearchMovementPoint(minute: minute, rawValue: sample.rawValue, availability: sample.availability,
                packetID: sample.packetID, selector: packets[sample.packetID].flatMap { sample.selector(from: $0)?.hex })
        }.sorted { $0.minute < $1.minute }
    }
}
