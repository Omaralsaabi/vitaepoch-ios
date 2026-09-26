import SwiftUI

struct MetricDetailView: View {
    let kind: MetricKind
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var ble: X6CentralManager
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize = 48
    @State private var days = 7
    private var samples: [MetricSample] { store.chartSamples(kind, days: days) }
    private var ranges: [Int] {
        let age = Date.now.timeIntervalSince(store.samples(kind).first?.timestamp ?? Date()) / 86400
        return [1,7,30,180,365].filter { $0 == 1 || $0 == 7 || age >= Double($0) }
    }
    var body: some View {
        Page {
            Surface {
                if let sample = store.latest(kind) {
                    Text(kind.formatted(sample.value)).font(.system(size: heroSize, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(kind.unit).foregroundStyle(.secondary)
                    Text(sample.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                    DataConfidenceBadge(text: "X6 · \(sample.method.rawValue)\(sample.confidence == .provisionalLayout ? " · provisional layout" : "")")
                    if Date.now.timeIntervalSince(sample.timestamp) > 86400 { Label("Saved reading — may be stale", systemImage: "clock").font(.caption).foregroundStyle(.secondary) }
                } else {
                    EmptyMetricState(title: "No \(kind.title.lowercased()) readings yet", message: "Connect and sync your X6 to see your measurements.", symbol: kind.symbol)
                }
            }
            if kind == .steps {
                HStack {
                    NavigationLink("Distance") { MetricDetailView(kind: .distance) }
                    Spacer()
                    NavigationLink("Calories") { MetricDetailView(kind: .calories) }
                }.buttonStyle(.bordered).controlSize(.large)
            }
            if kind == .heartRate {
                Button(ble.measuring ? "Stop measurement" : "Measure heart rate", systemImage: "heart") {
                    if ble.measuring { ble.stopMeasurement() } else { ble.measureHeartRate() }
                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!ble.ready || ble.syncing)
            }
            if !store.samples(kind).isEmpty {
                Picker("Time range", selection: $days) {
                    ForEach(ranges, id: \.self) { Text($0 == 1 ? "Day" : $0 == 7 ? "Week" : $0 == 30 ? "Month" : $0 == 180 ? "6M" : "Year").tag($0) }
                }.pickerStyle(.segmented)
                Surface {
                    if samples.isEmpty { EmptyMetricState(title: "No readings in this window", message: "Choose a longer time range to view saved data.") }
                    else { MetricChartView(kind: kind, samples: samples) }
                }
            }
            Surface {
                Text("About this metric").font(.headline)
                Text(kind.explanation).font(.subheadline).foregroundStyle(.secondary)
                if kind == .wristTemperature { Text("A personal deviation will be shown once the temperature baseline is established.").font(.caption).foregroundStyle(.secondary) }
            }
            if !samples.isEmpty {
                Text("Recent readings").font(.title2.bold())
                Surface {
                    ForEach(Array(samples.suffix(10).reversed())) { sample in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sample.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.subheadline)
                                Text("X6 · \(sample.method.rawValue)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(kind.formatted(sample.value)) \(kind.unit)").monospacedDigit().font(.subheadline.weight(.medium))
                        }.accessibilityElement(children: .combine)
                    }
                }
            }
        }.navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
    }
}

struct TrendsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var days = 7
    private let kinds: [MetricKind] = [.hrv, .heartRate, .stress, .steps, .wristTemperature]
    var body: some View {
        Page {
            Text("See what changes over time.").font(.title3).foregroundStyle(.secondary)
            if store.archive.samples.isEmpty {
                Surface { EmptyMetricState(title: "Your story starts with a sync", message: "As readings arrive, your trends will appear here. Gaps stay visible, and each metric keeps its own scale.", symbol: "chart.xyaxis.line") }
            } else {
                Picker("Trend window", selection: $days) { Text("7D").tag(7); Text("30D").tag(30); Text("3M").tag(90); Text("6M").tag(180) }.pickerStyle(.segmented)
                ForEach(kinds) { kind in
                    let samples = store.chartSamples(kind, days: days)
                    if !samples.isEmpty {
                        Surface {
                            NavigationLink { MetricDetailView(kind: kind) } label: { Label(kind.title, systemImage: kind.symbol).font(.headline) }
                            MetricChartView(kind: kind, samples: samples)
                        }
                    }
                }
            }
        }.navigationTitle("Trends")
    }
}
