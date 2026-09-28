import Foundation

public struct PacketProcessingResult: Sendable {
    public var receipts: [FrameReceipt] = []
    public var measuredHeartRate = false
    public var error: String?
}

/// Runs on the archive actor. No CoreBluetooth or UI dependencies.
public struct PacketProcessor: Sendable {
    private var assembler = X6FrameAssembler()
    public private(set) var references: [String: ManualTimestampReference] = [:]
    private var profiles: [String: VerifiedX6Profile] = [:]
    public init() {}
    public mutating func reset() { assembler.reset() }
    public mutating func setReferences(from packets: [RawPacket]) {
        references = ManualTimestampReference.september26Reference(in: packets)
        profiles = VerifiedX6Profile.profiles(in: packets)
    }
    public mutating func process(_ packet: RawPacket, archive: inout LocalArchive) -> PacketProcessingResult {
        archive.packets.append(packet)
        var result = PacketProcessingResult()
        guard packet.direction == .rx else { return result }
        if ["2A25", "2A28"].contains(packet.characteristic) || packet.captureEvidence?.deviceProfile != nil {
            setReferences(from: archive.packets)
        }
        var calendar = Calendar(identifier: .gregorian)
        // Older archives lack receipt timezone. Keep the reconstruction basis explicit.
        calendar.timeZone = TimeZone(identifier: packet.timeZoneID ?? references[packet.deviceID]?.timeZoneID ?? TimeZone.current.identifier) ?? .current
        do {
            switch packet.characteristic {
            case "FDD3":
                // A document transcript explicitly marks whole frame boundaries. Never borrow
                // missing bytes from its next line to make a malformed frame look complete.
                let frames = packet.captureEvidence?.kind == .physicalTranscription ? [packet.bytes] : assembler.append(packet.bytes)
                for bytes in frames {
                    let evidence: RawPacket
                    if bytes == packet.bytes { evidence = packet }
                    else {
                        evidence = RawPacket(deviceID: packet.deviceID, characteristic: "FDD3/reassembled", direction: .rx,
                            bytes: bytes, timestamp: packet.timestamp, timeZoneID: calendar.timeZone.identifier, captureEvidence: packet.captureEvidence)
                        archive.packets.append(evidence)
                    }
                    if [ManualTimestampReference.capturedHR, ManualTimestampReference.capturedSpO2].contains(bytes.hex) { setReferences(from: archive.packets) }
                    let frame = try X6Frame(bytes)
                    do {
                        if frame.group == 2 && frame.feature == 0x13 {
                            let positions = try MovementHistoryDecoder.decode(frame, packet: evidence, calendar: calendar)
                            archive.ingestMovement(positions)
                            result.receipts.append(FrameReceipt(packet: evidence, frame: frame,
                                sampleCount: positions.filter { $0.availability == .observedRawSignal }.count, error: nil))
                        } else {
                            let samples = try X6Decoder.decode(frame, packet: evidence, calendar: calendar,
                                reference: references[packet.deviceID], profile: profiles[packet.deviceID])
                            archive.ingest(samples)
                            result.receipts.append(FrameReceipt(packet: evidence, frame: frame, sampleCount: samples.count, error: nil))
                        }
                    } catch {
                        result.receipts.append(FrameReceipt(packet: evidence, frame: frame, sampleCount: 0, error: String(describing: error)))
                        if case ProtocolError.unsupportedFeature = error {} else { result.error = "Invalid \(String(format: "%02X%02X", frame.group, frame.feature)) payload; raw evidence retained." }
                    }
                }
            case "FDD1": archive.ingest(try X6Decoder.compactActivity(packet, calendar: calendar))
            case "2A37":
                let samples = try X6Decoder.heartRate(packet); archive.ingest(samples)
                result.measuredHeartRate = !samples.isEmpty
            default: break
            }
        } catch { result.error = "\(packet.characteristic): \(error). Raw evidence retained." }
        return result
    }

    public static func reprocess(_ original: LocalArchive) -> LocalArchive {
        var rebuilt = LocalArchive()
        rebuilt.lastSync = original.lastSync
        rebuilt.syncDiagnostics = original.syncDiagnostics ?? LegacySyncAudit.inspect(original)
        rebuilt.previousDecodes = (original.previousDecodes ?? []) + original.samples
        var processor = PacketProcessor(); processor.setReferences(from: original.packets)
        // Existing reassembled evidence is retained, but replay only original notifications
        // to avoid decoding the same fragments twice. New assembly evidence is also retained.
        for packet in original.packets where packet.characteristic != "FDD3/reassembled" {
            _ = processor.process(packet, archive: &rebuilt)
        }
        let replayedIDs = Set(rebuilt.packets.map(\.id))
        rebuilt.packets.append(contentsOf: original.packets.filter { !replayedIDs.contains($0.id) })
        let supported: Set<String> = ["0209","020B","0219","020D","020F","0210","0216","FDD1","2A37"]
        rebuilt.ingest(original.samples.filter { !supported.contains($0.feature) })
        let currentIDs = Set((rebuilt.movementSamples ?? []).map(\.id))
        rebuilt.ingestMovement((original.movementSamples ?? []).filter { !currentIDs.contains($0.id) })
        rebuilt.timestampReferences = Array(processor.references.values)
        return rebuilt
    }
}
