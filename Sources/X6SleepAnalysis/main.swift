import Foundation
import VitaEpochCore
import X6Research

@main
struct X6SleepAnalysisCLI {
    static func main() throws {
        var args = Array(CommandLine.arguments.dropFirst())
        let exportContext = args.contains("--export-movement-context")
        args.removeAll { $0 == "--export-movement-context" }
        var movementPath: String?
        if let index = args.firstIndex(of: "--movement-evidence") {
            guard index + 1 < args.count else { throw AnalysisError.invalidCandidate }
            movementPath = args[index+1]; args.removeSubrange(index...index+1)
        }
        var vendorPath: String?
        if let index = args.firstIndex(of: "--vendor-observations") {
            guard index + 1 < args.count else { throw AnalysisError.invalidCandidate }
            vendorPath = args[index+1]; args.removeSubrange(index...index+1)
        }
        guard args.count >= 3 else {
            print("Usage: swift run x6-sleep-analysis ARCHIVE.json SLEEP-REFERENCE.json OUTPUT-DIRECTORY [0211-CANDIDATES.json] [DEVICE-ID] [--vendor-observations FILE.json] [--movement-evidence ARCHIVE.json] [--export-movement-context]")
            return
        }
        let archiveURL = URL(fileURLWithPath: args[0])
        guard FileManager.default.fileExists(atPath: archiveURL.path) else { throw CocoaError(.fileReadNoSuchFile) }
        var original = try LocalArchive.read(from: archiveURL)
        if let movementPath {
            let url = URL(fileURLWithPath: movementPath)
            guard FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileReadNoSuchFile) }
            let additional = try LocalArchive.read(from: url)
            guard additional.packets.allSatisfy({ packet in
                guard let frame = try? X6Frame(packet.bytes) else { return false }
                return packet.direction == .rx && packet.characteristic == "FDD3" && frame.group == 2 && frame.feature == 0x13
            }) else { throw AnalysisError.invalidCandidate }
            original.packets.append(contentsOf: additional.packets)
        }
        let archive = PacketProcessor.reprocess(original)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let reference = try decoder.decode(SleepReference.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let candidates = args.count > 3 ? try decoder.decode([OxygenCandidate].self, from: Data(contentsOf: URL(fileURLWithPath: args[3]))) : []
        let vendor = try vendorPath.map { try decoder.decode([VendorObservation].self, from: Data(contentsOf: URL(fileURLWithPath: $0))) } ?? []
        let result = try SleepAlignment.align(archive: archive, reference: reference, candidates: candidates, deviceID: args.count > 4 ? args[4] : nil, vendorObservations: vendor)
        let output = URL(fileURLWithPath: args[2], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        if exportContext {
            try encoder.encode(MovementContext.points(archive: archive, reference: reference))
                .write(to: output.appending(path: "movement-context.json"), options: .atomic)
        }
        try encoder.encode(result).write(to: output.appending(path: "alignment.json"), options: .atomic)
        try encoder.encode(result.stages).write(to: output.appending(path: "statistics.json"), options: .atomic)
        let formatter = ISO8601DateFormatter(); formatter.timeZone = TimeZone(identifier: result.timeZone)
        func csv(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        func list(_ values: [Double]) -> String { values.map { String($0) }.joined(separator: ";") }
        var lines = ["minute,movementRaw,movementAvailability,heartRate,sdnn,spo2,groundTruthStage,spo2Status,movementPacketID"]
        if vendorPath != nil { lines[0] += ",vendorHeartRate,vendorSDNN,vendorOxygen,vendorRecordIDs" }
        for row in result.rows {
            var values = [formatter.string(from: row.minute), row.movementRaw.map(String.init) ?? "", row.movementAvailability ?? "", list(row.heartRate), list(row.sdnn), list(row.spo2), row.groundTruthStage ?? "", row.spo2Status ?? "", row.movementPacketID?.uuidString ?? ""]
            if vendorPath != nil {
                let observations = row.vendorObservations ?? []
                for metric: VendorObservation.Metric in [.heartRate, .sdnn, .oxygen] { values.append(list(observations.filter { $0.metric == metric }.map(\.value))) }
                values.append(observations.map(\.recordID).joined(separator: ";"))
            }
            lines.append(values.map(csv).joined(separator: ","))
        }
        try (lines.joined(separator: "\n") + "\n").write(to: output.appending(path: "alignment.csv"), atomically: true, encoding: .utf8)
        var summary = "# One-night reference alignment\n\n\(result.source)\n\n\(result.caveat)\n\n\(result.rows.count) labeled/window minutes. Blank HR or oxygen means unavailable, not zero.\n\n| Stage | Minutes | Raw observations | Zero/uninterpreted | Raw 0x80 | Mean raw byte | SDNN points | Mean SDNN |\n|---|---:|---:|---:|---:|---:|---:|---:|\n"
        for stage in result.stages {
            summary += "| \(stage.stage) | \(stage.labeledMinutes) | \(stage.movementRaw.count) | \(stage.zeroUninterpretedMinutes) | \(stage.raw80Minutes) | \(stage.movementRaw.mean.map { String(format: "%.2f", $0) } ?? "—") | \(stage.sdnn.count) | \(stage.sdnn.mean.map { String(format: "%.2f", $0) } ?? "—") |\n"
        }
        if vendorPath != nil {
            let transitions = SleepAlignment.transitions(in: result)
            try encoder.encode(transitions).write(to: output.appending(path: "transitions.json"), options: .atomic)
            func stats(_ s: DescriptiveStatistics) -> String {
                [String(s.count), s.minimum.map { String(format: "%.2f", $0) } ?? "—", s.maximum.map { String(format: "%.2f", $0) } ?? "—", s.mean.map { String(format: "%.2f", $0) } ?? "—", s.median.map { String(format: "%.2f", $0) } ?? "—"].joined(separator: " / ")
            }
            summary += "\n## Export observations and coverage\n\nVendor HR/SDNN are separate offline export observations, not raw 020F/0210 packets. Each export interval contributes one point at its start; no interval expansion or interpolation. The JSON retains source file, record ID and interval end. Empty oxygen columns mean no exported series was available.\n\n| Stage | Missing / future / zero | Raw 0x80 fraction (observed denominator) | Raw count/min/max/mean/median | Vendor HR count/min/max/mean/median | Vendor SDNN count/min/max/mean/median | 0211 / vendor oxygen points |\n|---|---|---|---|---|---|---|\n"
            for s in result.stages {
                summary += "| \(s.stage) | \(s.missingMovementMinutes) / \(s.futureMinutes) / \(s.zeroUninterpretedMinutes) | \(s.raw80Fraction.map { String(format: "%.4f", $0) } ?? "—") | \(stats(s.movementRaw)) | \(stats(s.vendorHeartRate ?? DescriptiveStatistics([]))) | \(stats(s.vendorSDNN ?? DescriptiveStatistics([]))) | \(s.spo2Candidates.count) / \(s.vendorOxygen?.count ?? 0) |\n"
            }
            summary += "\n### Stage boundaries\n\n\(transitions.method)\n\n\(transitions.observedTransitions) of \(transitions.labeledTransitions) boundaries have two observed movement positions. Boundary change count/min/max/mean/median: \(stats(transitions.transitionAbsoluteChange)); within-stage change: \(stats(transitions.nontransitionAbsoluteChange)). These descriptive comparisons do not establish a sleep-stage rule.\n"
        }
        summary += "\nNo classifier was trained. Reference labels are copied only into offline alignment rows. They never become VitaEpoch sleep results.\n\n## Frame integrity\n\n"
        for packet in original.packets where packet.characteristic == "FDD3" {
            do { _ = try X6Frame(packet.bytes) }
            catch { summary += "- Packet \(packet.id): \(packet.bytes.count) bytes, declared \(packet.bytes.count > 3 ? Int(Array(packet.bytes)[3]) : 0). Rejected without padding; raw bytes retained.\n" }
        }
        try summary.write(to: output.appending(path: "summary.md"), atomically: true, encoding: .utf8)
        print(summary)
    }
}
