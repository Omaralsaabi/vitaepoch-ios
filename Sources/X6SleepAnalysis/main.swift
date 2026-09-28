import Foundation
import VitaEpochCore
import X6Research

@main
struct X6SleepAnalysisCLI {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count >= 3 else {
            print("Usage: swift run x6-sleep-analysis ARCHIVE.json SLEEP-REFERENCE.json OUTPUT-DIRECTORY [0211-CANDIDATES.json] [DEVICE-ID]")
            return
        }
        let archiveURL = URL(fileURLWithPath: args[0])
        guard FileManager.default.fileExists(atPath: archiveURL.path) else { throw CocoaError(.fileReadNoSuchFile) }
        let original = try LocalArchive.read(from: archiveURL)
        let archive = PacketProcessor.reprocess(original)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let reference = try decoder.decode(SleepReference.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let candidates = args.count > 3 ? try decoder.decode([OxygenCandidate].self, from: Data(contentsOf: URL(fileURLWithPath: args[3]))) : []
        let result = try SleepAlignment.align(archive: archive, reference: reference, candidates: candidates, deviceID: args.count > 4 ? args[4] : nil)
        let output = URL(fileURLWithPath: args[2], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(result).write(to: output.appending(path: "alignment.json"), options: .atomic)
        try encoder.encode(result.stages).write(to: output.appending(path: "statistics.json"), options: .atomic)
        let formatter = ISO8601DateFormatter(); formatter.timeZone = TimeZone(identifier: result.timeZone)
        func csv(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        func list(_ values: [Double]) -> String { values.map { String($0) }.joined(separator: ";") }
        var lines = ["minute,movementRaw,movementAvailability,heartRate,sdnn,spo2,groundTruthStage,spo2Status,movementPacketID"]
        for row in result.rows {
            lines.append([formatter.string(from: row.minute), row.movementRaw.map(String.init) ?? "", row.movementAvailability ?? "", list(row.heartRate), list(row.sdnn), list(row.spo2), row.groundTruthStage ?? "", row.spo2Status ?? "", row.movementPacketID?.uuidString ?? ""].map(csv).joined(separator: ","))
        }
        try (lines.joined(separator: "\n") + "\n").write(to: output.appending(path: "alignment.csv"), atomically: true, encoding: .utf8)
        var summary = "# One-night reference alignment\n\n\(result.source)\n\n\(result.caveat)\n\n\(result.rows.count) labeled/window minutes. Blank HR or oxygen means unavailable, not zero.\n\n| Stage | Minutes | Raw observations | Zero/uninterpreted | Raw 0x80 | Mean raw byte | SDNN points | Mean SDNN |\n|---|---:|---:|---:|---:|---:|---:|---:|\n"
        for stage in result.stages {
            summary += "| \(stage.stage) | \(stage.labeledMinutes) | \(stage.movementRaw.count) | \(stage.zeroUninterpretedMinutes) | \(stage.raw80Minutes) | \(stage.movementRaw.mean.map { String(format: "%.2f", $0) } ?? "—") | \(stage.sdnn.count) | \(stage.sdnn.mean.map { String(format: "%.2f", $0) } ?? "—") |\n"
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
