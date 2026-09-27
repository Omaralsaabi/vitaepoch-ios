import Foundation

/// Reconstructs what the old build received. It cannot recover an unrecorded timer firing;
/// boundaries are explicitly labeled as inferred, and the final elapsed time stays unknown.
public enum LegacySyncAudit {
    public static func inspect(_ archive: LocalArchive) -> [SyncDiagnostic] {
        var diagnostics: [SyncDiagnostic] = []
        var progress: SyncProgress?
        var processor = PacketProcessor()
        var scratch = LocalArchive()
        for packet in archive.packets where packet.characteristic != "FDD3/reassembled" {
            if packet.direction == .tx, let command = X6Command.matching(packet.bytes) {
                if var previous = progress {
                    previous.finish(at: packet.timestamp)
                    var diagnostic = previous.diagnostic
                    diagnostic.reason = "Archived replay: " + (previous.isComplete ? "valid response sequence" : "missing pages \(previous.missingPages.map { String(format: "00%02X", $0) }.joined(separator: ", ")); timeout inferred from next TX (timer not recorded)")
                    if command == .activity {
                        diagnostic.endedAt = nil
                        diagnostic.reason = "Archived replay: prior sync ended without a stored completion/timer event; missing pages " + previous.missingPages.map { String(format: "00%02X", $0) }.joined(separator: ", ")
                    }
                    diagnostics.append(diagnostic)
                }
                processor.reset()
                progress = SyncProgress(command: command, deviceID: packet.deviceID, startedAt: packet.timestamp)
                progress?.wrote(packet.bytes, at: packet.timestamp)
            }
            let result = processor.process(packet, archive: &scratch)
            for receipt in result.receipts { progress?.received(receipt) }
        }
        if var progress {
            progress.finish(at: archive.packets.last?.timestamp ?? progress.diagnostic.startedAt)
            var diagnostic = progress.diagnostic
            diagnostic.endedAt = nil
            diagnostic.reason = "Archived replay ends: " + (progress.isComplete ? "valid response sequence" : "missing pages \(progress.missingPages.map { String(format: "00%02X", $0) }.joined(separator: ", ")); timer/completion event not recorded")
            diagnostics.append(diagnostic)
        }
        return diagnostics
    }
}
