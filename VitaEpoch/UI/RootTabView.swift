import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            NavigationStack { TodayView() }.tabItem { Label("Today", systemImage: "heart.text.square") }
            NavigationStack { TrendsView() }.tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
            NavigationStack { AgeView() }.tabItem { Label("Age", systemImage: "hourglass") }
            NavigationStack { DeviceView() }.tabItem { Label("Device", systemImage: "sensor.tag.radiowaves.forward") }
        }
    }
}

struct TodayView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var ble: X6CentralManager
    @Environment(\.dynamicTypeSize) private var typeSize
    private let metrics: [MetricKind] = [.hrv, .heartRate, .oxygen, .stress, .wristTemperature, .steps]
    var body: some View {
        Page {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Date.now, format: .dateTime.weekday(.wide).month(.abbreviated).day()).font(.subheadline).foregroundStyle(.secondary)
                    if ble.syncing { Text("Syncing…").font(.caption) }
                    else if let date = store.archive.lastSync { Text("Synced \(date.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary) }
                    else { Text("Your health, in perspective").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Label(ble.battery.map { "X6 · \($0)%" } ?? "X6", systemImage: ble.ready ? "checkmark.circle" : "circle.dotted").font(.caption).foregroundStyle(.secondary)
            }
            NavigationLink { AgeView() } label: { AgeProgressCard() }.buttonStyle(.plain)
            if store.archive.samples.isEmpty {
                Surface {
                    EmptyMetricState(title: "Begin with your X6", message: "Connect your band to bring heart rate, activity, and wrist temperature into one place.", symbol: "sensor.tag.radiowaves.forward")
                    NavigationLink("Connect your band") { DeviceView() }.buttonStyle(.borderedProminent).controlSize(.large)
                    Text("Your readings stay on this iPhone by default.").font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Your metrics").font(.title2.bold())
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                    ForEach(metrics) { kind in
                        NavigationLink { MetricDetailView(kind: kind) } label: { MetricCard(kind: kind, sample: store.latest(kind)) }.buttonStyle(.plain)
                    }
                }
            }
            Surface {
                Label("Recovery", systemImage: "sparkle").font(.headline)
                Text("Building the foundations").font(.subheadline)
                Text("A recovery score will appear once its model and required inputs are available.").font(.caption).foregroundStyle(.secondary)
            }
            if let error = store.storageError { Text(error).font(.caption).foregroundStyle(.orange) }
        }.navigationTitle("Today")
    }
}

struct AgeProgressCard: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        Surface {
            HStack { Label("VitaEpoch Age", systemImage: "hourglass").font(.headline); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
            Text("Every day adds\nperspective.").font(.system(.largeTitle, design: .rounded, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            Text("Building your baseline").font(.subheadline).foregroundStyle(.secondary)
            ProgressView(value: Double(min(store.observedDays, 7)), total: 7).tint(.teal)
            Text("\(store.observedDays) days with heart data · 7 recommended to begin").font(.caption).foregroundStyle(.secondary)
            DataConfidenceBadge(text: "Insufficient data · model pending")
        }
    }
}

struct AgeView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        Page {
            AgeProgressCard()
            Text("A longer view of your wellbeing").font(.title2.bold())
            Text("VitaEpoch Age will describe a wearable fitness estimate. It is not a clinical biological-age measurement.").foregroundStyle(.secondary)
            Surface {
                Text("Model inputs").font(.headline)
                input("Heart rate & activity", detail: store.archive.samples.isEmpty ? "Waiting for X6 readings" : "Device readings available; quality review required", symbol: "heart")
                Divider()
                input("HRV age component", detail: "Excluded — X6 metric type unverified", symbol: "waveform.path.ecg")
                Divider()
                input("VO₂ max", detail: "Unavailable — HealthKit bridge planned", symbol: "lungs")
                Divider()
                input("Sleep", detail: "Not available on this device yet", symbol: "moon")
            }
            Surface {
                DisclosureGroup("How this will be calculated") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Model status: not calibrated. No age number is calculated in this build.")
                        Text("A versioned, Pulse-inspired model will report its included inputs, exclusions, contributors, and confidence.")
                        Text("7–13 valid days: provisional. 14–29: moderate maturity. 30+: longer baseline. Coverage and source quality still determine confidence.")
                        Text("Days with readings are shown above; they are not yet validated as complete observation days.")
                    }.font(.subheadline).foregroundStyle(.secondary).padding(.top, 12)
                }
            }
        }.navigationTitle("Age")
    }
    private func input(_ title: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.medium))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}
