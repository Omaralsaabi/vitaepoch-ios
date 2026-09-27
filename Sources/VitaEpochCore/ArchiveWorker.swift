import Foundation

/// All parsing, replay, query preparation and file I/O are actor isolated away from MainActor.
/// A debounce coalesces bursts, while the two-second maximum interval prevents continuous
/// traffic from postponing persistence indefinitely. Flush at sync end/background/disconnect.
public actor ArchiveWorker {
    private let url: URL
    private var archive = LocalArchive()
    private var processor = PacketProcessor()
    private var writable = true
    private var dirty = false
    private var debounce: Task<Void, Never>?
    private var maximumDelay: Task<Void, Never>?
    private var lastError: String?
    public private(set) var writeCount = 0
    public init(url: URL) { self.url = url }

    public func load(fixture: Data? = nil) -> String? {
        do {
            if let fixture, !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fixture.write(to: url, options: .atomic)
            }
            let loaded = try LocalArchive.read(from: url)
            if loaded.schemaVersion != 2 {
                let backup = url.deletingLastPathComponent().appending(path: "archive.before-v2.json")
                if !FileManager.default.fileExists(atPath: backup.path) {
                    try FileManager.default.copyItem(at: url, to: backup)
                }
                archive = PacketProcessor.reprocess(loaded)
                dirty = true; flush()
            } else { archive = loaded }
            processor.setReferences(from: archive.packets)
        } catch {
            // Do not overwrite corrupt or incompatible evidence with an empty archive.
            writable = false
            lastError = "Saved data could not be read. Original file preserved: \(error.localizedDescription)"
        }
        return lastError
    }
    public func process(_ packet: RawPacket) -> PacketProcessingResult {
        let result = processor.process(packet, archive: &archive)
        archive.timestampReferences = Array(processor.references.values)
        scheduleWrite()
        return result
    }
    public func resetSession() { processor.reset(); flush() }
    public func diagnostic(_ diagnostic: SyncDiagnostic) {
        if archive.syncDiagnostics == nil { archive.syncDiagnostics = [] }
        if let index = archive.syncDiagnostics?.firstIndex(where: { $0.id == diagnostic.id }) {
            archive.syncDiagnostics?[index] = diagnostic
        } else { archive.syncDiagnostics?.append(diagnostic) }
        scheduleWrite()
    }
    public func synced(at date: Date) { archive.lastSync = date; dirty = true; flush() }
    public func snapshot(now: Date = Date(), calendar: Calendar = .current) -> ArchiveSnapshot {
        ArchiveSnapshot(archive, now: now, calendar: calendar)
    }
    public func error() -> String? { lastError }
    private func scheduleWrite() {
        dirty = true
        debounce?.cancel()
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            await self?.flush()
        }
        if maximumDelay == nil {
            maximumDelay = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                await self?.flush()
            }
        }
    }
    public func flush() {
        debounce?.cancel(); debounce = nil; maximumDelay?.cancel(); maximumDelay = nil
        guard writable, dirty else { return }
        do { try archive.write(to: url); dirty = false; writeCount += 1; lastError = nil }
        catch { lastError = "Unable to save device data: \(error.localizedDescription)" }
    }
}
