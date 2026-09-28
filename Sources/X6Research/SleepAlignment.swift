import Foundation
import VitaEpochCore

/// Imported vendor reference labels for offline research only. This target is NOT linked
/// into VitaEpoch.app. No classifier or stage inference is implemented.
public struct SleepReference: Codable, Sendable {
    public struct Interval: Codable, Sendable {
        public let start: Date
        public let end: Date
        public let stage: String
    }
    public let source: String
    public let role: String
    public let timeZone: String
    public let intervals: [Interval]
    public func validate() throws {
        guard !intervals.isEmpty else { throw AnalysisError.invalidReference }
        var end: Date?
        for interval in intervals {
            guard ["Core","REM","Deep","Awake"].contains(interval.stage), interval.start < interval.end,
                  interval.end.timeIntervalSince(interval.start).truncatingRemainder(dividingBy: 60) == 0,
                  end == nil || interval.start >= end! else { throw AnalysisError.invalidReference }
            end = interval.end
        }
    }
}
public enum AnalysisError: Error { case invalidReference, multipleDevices, invalidCandidate }
public struct OxygenCandidate: Codable, Sendable {
    public let timestamp: Date
    public let value: Double
    public let featureID: String
    public let interpretation: String
}
public struct AlignmentRow: Codable, Sendable {
    public let minute: Date
    public let movementRaw: UInt8?
    public let movementAvailability: String?
    public let movementPacketID: UUID?
    public let heartRate: [Double]
    public let sdnn: [Double]
    public let spo2: [Double]
    public let spo2Status: String?
    public let groundTruthStage: String?
}
public struct DescriptiveStatistics: Codable, Sendable {
    public let count: Int
    public let minimum: Double?
    public let maximum: Double?
    public let mean: Double?
    public let median: Double?
    public init(_ values: [Double]) {
        let sorted = values.sorted(); count = sorted.count
        minimum = sorted.first; maximum = sorted.last
        mean = sorted.isEmpty ? nil : sorted.reduce(0,+)/Double(sorted.count)
        median = sorted.isEmpty ? nil : sorted.count.isMultiple(of: 2) ? (sorted[sorted.count/2-1] + sorted[sorted.count/2])/2 : sorted[sorted.count/2]
    }
}
public struct StageStatistics: Codable, Sendable {
    public let stage: String
    public let labeledMinutes: Int
    public let missingMovementMinutes: Int
    public let zeroUninterpretedMinutes: Int
    public let futureMinutes: Int
    public let raw80Minutes: Int
    public let movementRaw: DescriptiveStatistics
    public let heartRate: DescriptiveStatistics
    public let sdnn: DescriptiveStatistics
    public let spo2Candidates: DescriptiveStatistics
}
public struct AlignmentResult: Codable, Sendable {
    public let source: String
    public let caveat: String
    public let timeZone: String
    public let rows: [AlignmentRow]
    public let stages: [StageStatistics]
}
public enum SleepAlignment {
    public static func align(archive: LocalArchive, reference: SleepReference,
                             candidates: [OxygenCandidate] = [], deviceID: String? = nil) throws -> AlignmentResult {
        try reference.validate()
        guard candidates.allSatisfy({ $0.featureID == "0211" && !$0.interpretation.isEmpty }) else { throw AnalysisError.invalidCandidate }
        let devices = Set(archive.packets.map(\.deviceID))
        guard deviceID != nil || devices.count <= 1 else { throw AnalysisError.multipleDevices }
        let chosen = deviceID ?? devices.first
        let movements = (archive.movementSamples ?? []).filter { $0.deviceID == chosen }
        let samples = archive.samples.filter { $0.deviceID == chosen }
        // Keep sparse readings at their actual minute; do not carry or interpolate them.
        func bucket(_ date: Date) -> Int { Int(floor(date.timeIntervalSince1970 / 60)) }
        let movementByMinute = Dictionary(movements.compactMap { sample -> (Int, MinuteMovementSample)? in
            sample.localMinute.map { (bucket($0), sample) }
        }, uniquingKeysWith: { old, new in new.availability == .observedRawSignal ? new : old })
        let metricByMinute = Dictionary(grouping: samples, by: { bucket($0.timestamp) })
        let candidatesByMinute = Dictionary(grouping: candidates, by: { bucket($0.timestamp) })
        let first = reference.intervals.first!.start, last = reference.intervals.last!.end
        var rows: [AlignmentRow] = []
        var date = first
        while date < last {
            let interval = reference.intervals.first { $0.start <= date && date < $0.end }
            let movement = movementByMinute[bucket(date)]
            let readings = metricByMinute[bucket(date)] ?? []
            let oxygen = candidatesByMinute[bucket(date)] ?? []
            rows.append(AlignmentRow(minute: date, movementRaw: movement?.rawValue,
                movementAvailability: movement?.availability.rawValue, movementPacketID: movement?.packetID,
                heartRate: readings.filter { $0.feature == "020F" && $0.metric == .heartRate }.map(\.value),
                sdnn: readings.filter { $0.feature == "0210" && $0.resolvedHRVStatistic == .sdnn }.map(\.value),
                spo2: oxygen.map(\.value), spo2Status: oxygen.isEmpty ? nil : "0211 candidate; " + oxygen.map(\.interpretation).joined(separator: "; "),
                groundTruthStage: interval?.stage))
            date = date.addingTimeInterval(60)
        }
        let stages = ["Core","REM","Deep","Awake"].map { stage in
            let group = rows.filter { $0.groundTruthStage == stage }
            let observed = group.filter { $0.movementAvailability == MinuteMovementSample.Availability.observedRawSignal.rawValue }
            return StageStatistics(stage: stage, labeledMinutes: group.count,
                missingMovementMinutes: group.filter { $0.movementRaw == nil }.count,
                zeroUninterpretedMinutes: group.filter { $0.movementAvailability == "zeroUninterpreted" }.count,
                futureMinutes: group.filter { $0.movementAvailability == "future" }.count,
                raw80Minutes: observed.filter { $0.movementRaw == 0x80 }.count,
                movementRaw: DescriptiveStatistics(observed.compactMap { $0.movementRaw.map(Double.init) }),
                heartRate: DescriptiveStatistics(group.flatMap(\.heartRate)), sdnn: DescriptiveStatistics(group.flatMap(\.sdnn)),
                spo2Candidates: DescriptiveStatistics(group.flatMap(\.spo2)))
        }
        return AlignmentResult(source: reference.source,
            caveat: "Vendor-labeled intervals for reverse engineering only; not an independently validated clinical ground truth. No sleep stage inferred. Raw amplitudes have unknown meaning. Zero/future/missing positions are excluded from amplitude statistics. Sparse HR/SDNN/0211 candidates are not imputed.",
            timeZone: reference.timeZone, rows: rows, stages: stages)
    }
}
