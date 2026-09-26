import SwiftUI
import Charts

extension MetricKind {
    var symbol: String {
        switch self {
        case .heartRate: "heart"
        case .hrv: "waveform.path.ecg"
        case .oxygen: "drop"
        case .stress: "leaf"
        case .wristTemperature: "thermometer.medium"
        case .steps: "figure.walk"
        case .distance: "point.bottomleft.forward.to.point.topright.scurvepath"
        case .calories: "flame"
        }
    }
    var explanation: String {
        switch self {
        case .heartRate: "Manual measurements and periodic readings are shown separately. The 30-minute history cannot establish your true maximum heart rate."
        case .hrv: "X6 reports these values in milliseconds. The underlying HRV statistic is unverified; these readings are excluded from age reference curves."
        case .oxygen: "Manual oxygen readings reported by your X6. This is a wearable measurement, not a medical assessment."
        case .stress: "A device-reported stress score. Qualitative thresholds have not been verified."
        case .wristTemperature: "Temperature at your wrist, not core body temperature. Personal trends are more useful than a single reading."
        case .steps: "Daily steps reported by X6. Activity snapshots are replaced as the day progresses."
        case .distance: "Device-reported distance. The conversion from raw data is provisional."
        case .calories: "Device-reported calories. The conversion from raw data is provisional."
        }
    }
    func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(self == .wristTemperature ? 1 : 0)))
    }
}

struct Surface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }
}
struct Page<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) { content }.padding(20) }
            .background(Color(uiColor: .systemGroupedBackground))
    }
}
struct DataConfidenceBadge: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.primary.opacity(0.05), in: Capsule())
    }
}
struct EmptyMetricState: View {
    let title: String
    let message: String
    var symbol: String = "waveform.path"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.teal).accessibilityHidden(true)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical, 8)
    }
}
struct MetricCard: View {
    let kind: MetricKind
    let sample: MetricSample?
    var body: some View {
        Surface {
            Label(kind.title, systemImage: kind.symbol).font(.subheadline).foregroundStyle(.secondary)
            if let sample {
                Text(kind.formatted(sample.value)).font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit()
                Text(kind.unit).font(.caption).foregroundStyle(.secondary)
                Text(sample.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("—").font(.largeTitle).foregroundStyle(.tertiary)
                Text("No data yet").font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
    }
}
struct MetricChartView: View {
    let kind: MetricKind
    let samples: [MetricSample]
    @State private var selection: Date?
    private var points: [(sample: MetricSample, segment: Int)] {
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        var segment = 0
        var previous: MetricSample?
        return sorted.map { sample in
            if let previous, sample.method != previous.method || sample.timestamp.timeIntervalSince(previous.timestamp) > (kind == .heartRate ? 1800 : 300) { segment += 1 }
            previous = sample
            return (sample, segment)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart {
                ForEach(points, id: \.sample.id) { point in
                    if point.sample.method == .dailySummary {
                        BarMark(x: .value("Date", point.sample.timestamp, unit: .day), y: .value(kind.unit, point.sample.value)).foregroundStyle(.teal)
                    } else if point.sample.method == .manual {
                        PointMark(x: .value("Time", point.sample.timestamp), y: .value(kind.unit, point.sample.value)).symbol(.diamond).foregroundStyle(.teal)
                    } else {
                        LineMark(x: .value("Time", point.sample.timestamp), y: .value(kind.unit, point.sample.value), series: .value("Segment", point.segment)).foregroundStyle(.teal)
                        PointMark(x: .value("Time", point.sample.timestamp), y: .value(kind.unit, point.sample.value)).symbolSize(12).foregroundStyle(.teal)
                    }
                }
                if let selection { RuleMark(x: .value("Selected", selection)).foregroundStyle(.secondary).lineStyle(StrokeStyle(dash: [4])) }
            }
            .frame(height: 210).chartXSelection(value: $selection)
            .accessibilityLabel("\(kind.title) chart, \(samples.count) readings")
            if let selection, let nearest = samples.min(by: { abs($0.timestamp.timeIntervalSince(selection)) < abs($1.timestamp.timeIntervalSince(selection)) }) {
                Text("\(kind.formatted(nearest.value)) \(kind.unit) · \(nearest.timestamp.formatted(date: .abbreviated, time: .shortened))").font(.caption)
            }
            if let low = samples.map(\.value).min(), let high = samples.map(\.value).max() {
                Text("\(samples.count) readings · \(kind.formatted(low))–\(kind.formatted(high)) \(kind.unit)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
