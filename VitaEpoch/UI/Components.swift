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
    func title(for sample: MetricSample?) -> String {
        self == .hrv && sample?.resolvedHRVStatistic == .sdnn ? "HRV · SDNN" : title
    }
    func explanation(for sample: MetricSample?) -> String {
        if self == .hrv && sample?.resolvedHRVStatistic == .sdnn {
            return "HRV SDNN (ms), confirmed by Da Halo HealthKit export for this X6/firmware path. This confirms the vendor statistic label, not clinical accuracy."
        }
        return explanation
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
            // Native TabView supplies its own safe area; reserve additional breathing room
            // for its floating presentation without overlaying content or ignoring safe areas.
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 24) }
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
            Label(kind.title(for: sample), systemImage: kind.symbol).font(.subheadline).foregroundStyle(.secondary)
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
    let series: MetricSeries
    @State private var selection: Date?
    private var points: [(point: ChartPoint, segment: Int)] {
        var segment = 0
        var previous: ChartPoint?
        return series.points.map { point in
            if let previous {
                let gap: Bool
                if series.range.aggregatesByDay {
                    gap = (series.calendar.dateComponents([.day], from: previous.timestamp, to: point.timestamp).day ?? 0) > 1
                } else { gap = point.timestamp.timeIntervalSince(previous.timestamp) > (kind == .heartRate ? 1800 : 300) }
                if gap || point.method != previous.method { segment += 1 }
            }
            previous = point
            return (point, segment)
        }
    }
    private var yDomain: ClosedRange<Double> {
        let low = series.points.map(\.value).min() ?? 0
        let high = series.points.map(\.value).max() ?? 1
        let margin = max(1, (high-low) * 0.1)
        return max(0, low-margin)...(high+margin)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Avoid constructing a render surface during transient zero-width layout passes.
            // The outer frame supplies a nonzero height even before data/layout settle.
            GeometryReader { geometry in
                if geometry.size.width > 1 && geometry.size.height > 1 && !series.points.isEmpty {
                    chart.frame(width: geometry.size.width, height: geometry.size.height)
                }
            }.frame(height: 230)
            .accessibilityLabel("\(kind.title) chart, \(series.points.count) \(series.range.aggregatesByDay ? "daily summaries" : "readings")")
            .accessibilityIdentifier("metric-chart")
            Text(series.range.aggregatesByDay ? ([MetricKind.steps,.distance,.calories].contains(kind) ? "Daily totals" : "Daily median") : "Intraday readings")
                .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("chart-granularity")
            if let selection, let nearest = series.points.min(by: { abs($0.timestamp.timeIntervalSince(selection)) < abs($1.timestamp.timeIntervalSince(selection)) }) {
                Text("\(kind.formatted(nearest.value)) \(kind.unit) · \(nearest.timestamp.formatted(date: .abbreviated, time: series.range.aggregatesByDay ? .omitted : .shortened))")
                    .font(.caption)
            }
            if let low = series.points.map(\.value).min(), let high = series.points.map(\.value).max() {
                Text("\(series.records.count) readings · \(kind.formatted(low))–\(kind.formatted(high)) \(kind.unit)").font(.caption).foregroundStyle(.secondary)
            }
        }.onChange(of: series.range) { _, _ in selection = nil }
    }
    private var chart: some View {
        Chart {
            ForEach(points, id: \.point.id) { item in
                if [MetricKind.steps,.distance,.calories].contains(kind) {
                    BarMark(x: .value("Date", item.point.timestamp, unit: .day), y: .value(kind.unit, item.point.value)).foregroundStyle(.teal)
                } else if !series.range.aggregatesByDay && item.point.method == .manual {
                    PointMark(x: .value("Time", item.point.timestamp), y: .value(kind.unit, item.point.value)).symbol(.diamond).foregroundStyle(.teal)
                } else {
                    LineMark(x: .value("Date", item.point.timestamp), y: .value(kind.unit, item.point.value), series: .value("Segment", item.segment)).foregroundStyle(.teal)
                    PointMark(x: .value("Date", item.point.timestamp), y: .value(kind.unit, item.point.value)).symbolSize(18).foregroundStyle(.teal)
                }
            }
            if let selection { RuleMark(x: .value("Selected", selection)).foregroundStyle(.secondary).lineStyle(StrokeStyle(dash: [4])) }
        }
        .chartXScale(domain: series.start...series.end)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            if series.range.aggregatesByDay {
                AxisMarks(values: .stride(by: .day, count: max(1, series.range.rawValue/6))) { _ in
                    AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            } else {
                AxisMarks(values: .stride(by: .hour, count: 4)) { _ in
                    AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
        }
        .chartXSelection(value: $selection)
    }
}
