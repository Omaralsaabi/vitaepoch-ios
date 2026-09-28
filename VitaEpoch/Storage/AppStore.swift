import Foundation
import Combine

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var archive = LocalArchive()
    @Published private(set) var storageError: String?
    @Published private(set) var loading = true
    private let queryDate: Date?
    private let worker: ArchiveWorker
    private var queue: Task<Void, Never>?
    private var refresh: Task<Void, Never>?
    private var snapshot: ArchiveSnapshot?

    init(url: URL? = nil, fixture: Data? = nil, queryDate: Date? = nil) {
        self.queryDate = queryDate
        worker = ArchiveWorker(url: url ?? URL.applicationSupportDirectory.appending(path: "VitaEpoch/archive.json"))
        queue = Task { [weak self, worker] in
            let error = await worker.load(fixture: fixture)
            guard let self else { return }
            self.storageError = error
            self.apply(await worker.snapshot(now: self.queryDate ?? Date())); self.loading = false
        }
    }
    // A task chain maintains callback order across actor hops (including reset/flush).
    func receive(_ packet: RawPacket, completion: @escaping @MainActor (PacketProcessingResult) -> Void = { _ in }) {
        enqueue { [weak self, worker] in
            let result = await worker.process(packet)
            completion(result)
            self?.scheduleRefresh()
        }
    }
    func diagnostic(_ value: SyncDiagnostic) {
        enqueue { [weak self, worker] in await worker.diagnostic(value); self?.scheduleRefresh() }
    }
    func resetSession() { enqueue { [worker] in await worker.resetSession() } }
    func synced() { enqueue { [weak self, worker] in await worker.synced(at: Date()); self?.scheduleRefresh() } }
    func flush() {
        enqueue { [weak self, worker] in
            await worker.flush()
            self?.apply(await worker.snapshot(now: self?.queryDate ?? Date()))
            self?.storageError = await worker.error()
        }
    }
    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task { await previous?.value; await operation() }
    }
    private func scheduleRefresh() {
        guard refresh == nil else { return }
        refresh = Task { [weak self, worker] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self else { return }
            self.apply(await worker.snapshot(now: self.queryDate ?? Date()))
            self.storageError = await worker.error()
            self.refresh = nil
        }
    }
    private func apply(_ value: ArchiveSnapshot) { snapshot = value; archive = value.archive }
    func samples(_ kind: MetricKind) -> [MetricSample] { snapshot?.samples[kind] ?? [] }
    func latest(_ kind: MetricKind) -> MetricSample? { snapshot?.latest[kind] }
    var observedDays: Int { snapshot?.observedDays ?? 0 }
    func chartSeries(_ kind: MetricKind, range: ChartRange) -> MetricSeries {
        snapshot?.charts[kind]?[range] ?? MetricQueries.series(kind, samples: [], packetDates: [:], range: range, now: Date(), calendar: .current)
    }
}
