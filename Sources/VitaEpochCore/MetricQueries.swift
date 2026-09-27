import Foundation

public enum ChartRange: Int, CaseIterable, Sendable, Identifiable {
    case day = 1, week = 7, month = 30, threeMonths = 90, sixMonths = 180, year = 365
    public var id: Int { rawValue }
    public var aggregatesByDay: Bool { self != .day }
}
public struct ChartPoint: Identifiable, Equatable, Sendable {
    public let timestamp: Date
    public let value: Double
    public let sampleCount: Int
    public let method: SampleMethod
    public let key: String
    public var id: String { key }
}
public struct MetricSeries: Sendable {
    public let points: [ChartPoint]
    public let records: [MetricSample]
    public let range: ChartRange
    public let start: Date
    public let end: Date
    public let calendar: Calendar
}

public enum MetricQueries {
    public static func series(_ metric: MetricKind, samples: [MetricSample], packetDates: [UUID: Date],
                              range: ChartRange, now: Date, calendar: Calendar) -> MetricSeries {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let start = calendar.date(byAdding: .day, value: -(range.rawValue-1), to: calendar.startOfDay(for: now))!
        let records = samples.filter { $0.metric == metric && $0.timestamp >= start && $0.timestamp <= now }.sorted { $0.timestamp < $1.timestamp }
        let activity = [.steps, .distance, .calories].contains(metric)
        let points: [ChartPoint]
        if range.aggregatesByDay || activity {
            points = Dictionary(grouping: records, by: { calendar.startOfDay(for: $0.timestamp) }).map { date, dayRecords in
                let value: Double
                if activity {
                    // Cumulative observations are alternatives, never summed, including across devices.
                    value = dayRecords.max { (packetDates[$0.packetID] ?? $0.timestamp) < (packetDates[$1.packetID] ?? $1.timestamp) }!.value
                } else {
                    // Equal-weight daily median of available readings. Never impute missing days.
                    let sorted = dayRecords.map(\.value).sorted()
                    value = sorted.count.isMultiple(of: 2) ? (sorted[sorted.count/2-1] + sorted[sorted.count/2])/2 : sorted[sorted.count/2]
                }
                return ChartPoint(timestamp: date, value: value, sampleCount: dayRecords.count,
                                  method: .dailySummary, key: "\(metric.rawValue)-\(date.timeIntervalSince1970)")
            }.sorted { $0.timestamp < $1.timestamp }
        } else {
            points = records.map { ChartPoint(timestamp: $0.timestamp, value: $0.value, sampleCount: 1, method: $0.method, key: $0.id) }
        }
        return MetricSeries(points: points, records: records, range: range, start: start, end: end, calendar: calendar)
    }
}

public struct ArchiveSnapshot: Sendable {
    public let archive: LocalArchive
    public let samples: [MetricKind: [MetricSample]]
    public let latest: [MetricKind: MetricSample]
    public let charts: [MetricKind: [ChartRange: MetricSeries]]
    public let observedDays: Int
    public init(_ archive: LocalArchive, now: Date = Date(), calendar: Calendar = .current) {
        self.archive = archive
        let grouped = Dictionary(grouping: archive.samples, by: \.metric)
        samples = grouped
        let dates = Dictionary(archive.packets.map { ($0.id, $0.timestamp) }, uniquingKeysWith: { _, new in new })
        latest = grouped.mapValues { values in
            values.max {
                if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
                return (dates[$0.packetID] ?? $0.timestamp) < (dates[$1.packetID] ?? $1.timestamp)
            }!
        }
        charts = Dictionary(uniqueKeysWithValues: MetricKind.allCases.map { kind in
            (kind, Dictionary(uniqueKeysWithValues: ChartRange.allCases.map { range in
                (range, MetricQueries.series(kind, samples: grouped[kind] ?? [], packetDates: dates, range: range, now: now, calendar: calendar))
            }))
        })
        observedDays = Set(archive.samples.filter { [.heartRate,.hrv].contains($0.metric) }.map { calendar.startOfDay(for: $0.timestamp) }).count
    }
}
