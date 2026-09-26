import Foundation
import Combine

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var archive: LocalArchive
    @Published var storageError: String?
    private let url: URL
    private var writable = true

    init(url: URL? = nil) {
        self.url = url ?? URL.applicationSupportDirectory.appending(path: "VitaEpoch/archive.json")
        do {
            archive = FileManager.default.fileExists(atPath: self.url.path) ? try LocalArchive.read(from: self.url) : LocalArchive()
        } catch {
            archive = LocalArchive()
            storageError = "Saved data could not be read. The original file has been preserved. \(error.localizedDescription)"
            writable = false
        }
    }
    func record(_ packet: RawPacket) { archive.packets.append(packet); save() }
    func ingest(_ samples: [MetricSample]) { archive.ingest(samples); save() }
    func synced() { archive.lastSync = Date(); save() }
    private func save() {
        guard writable else { return }
        do { try archive.write(to: url); storageError = nil }
        catch { storageError = "Unable to save device data: \(error.localizedDescription)" }
    }
    func samples(_ kind: MetricKind) -> [MetricSample] { archive.samples.filter { $0.metric == kind } }
    func latest(_ kind: MetricKind) -> MetricSample? {
        samples(kind).max { a, b in
            if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
            let dates = Dictionary(archive.packets.map { ($0.id, $0.timestamp) }, uniquingKeysWith: { _, new in new })
            return (dates[a.packetID] ?? a.timestamp) < (dates[b.packetID] ?? b.timestamp)
        }
    }
    var observedDays: Int { Set(archive.samples.filter { [.heartRate, .hrv].contains($0.metric) }.map { Calendar.current.startOfDay(for: $0.timestamp) }).count }
}

extension AppStore {
    func chartSamples(_ kind: MetricKind, days: Int) -> [MetricSample] {
        let start = Calendar.current.date(byAdding: .day, value: -(days-1), to: Calendar.current.startOfDay(for: Date()))!
        let values = samples(kind).filter { $0.timestamp >= start && $0.timestamp <= Date() }
        guard [.steps, .distance, .calories].contains(kind) else { return values }
        let dates = Dictionary(archive.packets.map { ($0.id, $0.timestamp) }, uniquingKeysWith: { _, new in new })
        // FDD1 and 020D are alternative cumulative snapshots, never additive totals.
        return Dictionary(grouping: values, by: { Calendar.current.startOfDay(for: $0.timestamp) }).values.compactMap {
            $0.max { (dates[$0.packetID] ?? $0.timestamp) < (dates[$1.packetID] ?? $1.timestamp) }
        }.sorted { $0.timestamp < $1.timestamp }
    }
}
