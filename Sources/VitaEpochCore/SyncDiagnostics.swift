import Foundation

public struct SyncWrite: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let bytesHex: String
    public let variantHex: String
}
public struct SyncResponse: Codable, Equatable, Sendable {
    public let packetID: UUID
    public let elapsed: Double
    public let featureID: String
    public let prefixHex: String
    public let byteCount: Int
    public let sampleCount: Int
    public let status: String
}
public struct SyncDiagnostic: Codable, Identifiable, Sendable {
    public var id = UUID()
    public let deviceID: String
    public let featureID: String
    public let startedAt: Date
    public var endedAt: Date?
    public var writes: [SyncWrite] = []
    public var responses: [SyncResponse] = []
    public var receivedPages: [UInt8] = []
    public var expectedPages: [UInt8]
    public var reason = "Awaiting response"
    public var complete = false
    public var elapsed: Double? { endedAt.map { $0.timeIntervalSince(startedAt) } }
    /// Derived from persisted TX/RX timing; does not claim causal attribution of a late burst.
    public func acquisition(for response: SyncResponse) -> String {
        guard featureID == "0213", response.featureID == featureID else { return "" }
        let receivedAt = startedAt.addingTimeInterval(response.elapsed)
        let explicit = writes.dropFirst().contains { $0.variantHex == response.prefixHex && $0.timestamp <= receivedAt }
        return explicit ? "after explicit fallback" : "automatic after initial request"
    }
}

public enum MovementAcquisitionAction: Equatable, Sendable {
    case wait(until: Date)
    case write(Data)
    case finish
}

public struct FrameReceipt: Sendable {
    public let packet: RawPacket
    public let frame: X6Frame
    public let sampleCount: Int
    public let error: String?
}

public struct SyncProgress: Sendable {
    public let command: X6Command
    public private(set) var diagnostic: SyncDiagnostic
    private var receivedReply = false
    public init(command: X6Command, deviceID: String, startedAt: Date) {
        self.command = command
        diagnostic = SyncDiagnostic(deviceID: deviceID, featureID: command.featureID, startedAt: startedAt,
                                    expectedPages: command == .movement ? Array(0...7) : command == .periodicHeartRate ? [0,1] : [.hrv,.temperature].contains(command) ? [0,1,2,3] : [])
    }
    public mutating func wrote(_ bytes: Data, at date: Date) {
        diagnostic.writes.append(SyncWrite(timestamp: date, bytesHex: bytes.hex, variantHex: Data(bytes.dropFirst(6)).hex))
    }
    public mutating func received(_ receipt: FrameReceipt) {
        let frame = receipt.frame
        let matches = receipt.packet.deviceID == diagnostic.deviceID && frame.group == 2 && frame.feature == Array(command.bytes)[5]
        diagnostic.responses.append(SyncResponse(packetID: receipt.packet.id,
            elapsed: receipt.packet.timestamp.timeIntervalSince(diagnostic.startedAt),
            featureID: String(format: "%02X%02X", frame.group, frame.feature),
            prefixHex: Data(frame.payload.prefix(2)).hex, byteCount: receipt.packet.bytes.count,
            sampleCount: receipt.sampleCount,
            status: receipt.error ?? (matches ? (receipt.sampleCount == 0 ? "Valid empty response" : "Decoded") : "Unrelated response")))
        guard matches, receipt.error == nil else { return }
        if diagnostic.expectedPages.isEmpty { receivedReply = true; return }
        guard frame.payload.count >= 2, frame.payload[0] == 0, diagnostic.expectedPages.contains(frame.payload[1]) else { return }
        // Completion follows protocol pages, never the presence of nonzero samples.
        if !diagnostic.receivedPages.contains(frame.payload[1]) { diagnostic.receivedPages.append(frame.payload[1]) }
    }
    public var isComplete: Bool {
        diagnostic.expectedPages.isEmpty ? receivedReply : Set(diagnostic.expectedPages).isSubset(of: Set(diagnostic.receivedPages))
    }
    public var missingPages: [UInt8] { diagnostic.expectedPages.filter { !diagnostic.receivedPages.contains($0) } }
    public var continuation: Data? {
        // Only the two-byte day/page variants documented for 0210/0216 are used.
        // 020F has a one-byte selector of unresolved meaning; do not invent its variant.
        guard [.hrv,.temperature].contains(command), !diagnostic.receivedPages.isEmpty else { return nil }
        for page in missingPages {
            let variant = String(format: "00%02X", page)
            if !diagnostic.writes.contains(where: { $0.variantHex == variant }) {
                var bytes = Array(command.bytes); bytes[7] = page
                return Data(bytes)
            }
        }
        return nil
    }
    /// Current-day selectors 0001...0007 observed in nRF on 28 Sep. Wait for the
    /// initial burst, then serialize missing selectors with an 8-second reply bound.
    /// All decisions use injected time so the exact live policy is regression-tested.
    public func movementAction(at now: Date) -> MovementAcquisitionAction {
        precondition(command == .movement)
        let deadline = diagnostic.startedAt.addingTimeInterval(72)
        guard !isComplete, now < deadline, let lastWrite = diagnostic.writes.last else { return .finish }
        let page = UInt8(lastWrite.variantHex.suffix(2), radix: 16)
        let replyDeadline = lastWrite.timestamp.addingTimeInterval(8)
        if let page, !diagnostic.receivedPages.contains(page), now < replyDeadline {
            return .wait(until: min(replyDeadline, deadline))
        }
        let latestResponse = diagnostic.responses.filter {
            $0.featureID == "0213" && ["Decoded", "Valid empty response"].contains($0.status)
        }.map { diagnostic.startedAt.addingTimeInterval($0.elapsed) }.max()
        // Duplicate notifications cannot postpone progress beyond a per-write bound.
        let quietUntil = min((latestResponse ?? lastWrite.timestamp).addingTimeInterval(0.8), replyDeadline)
        if now < quietUntil { return .wait(until: min(quietUntil, deadline)) }
        for page in missingPages where page > 0 {
            let variant = String(format: "00%02X", page)
            if !diagnostic.writes.contains(where: { $0.variantHex == variant }) {
                var bytes = Array(command.bytes); bytes[7] = page
                return .write(Data(bytes))
            }
        }
        return .finish
    }
    public mutating func finish(at date: Date, interrupted: String? = nil) {
        diagnostic.endedAt = date
        diagnostic.complete = isComplete && interrupted == nil
        if let interrupted { diagnostic.reason = interrupted }
        else if isComplete { diagnostic.reason = diagnostic.expectedPages.isEmpty ? "Valid response received" : "All requested pages received (empty pages included)" }
        else if !diagnostic.expectedPages.isEmpty {
            diagnostic.reason = "Timed out; missing " + missingPages.map { String(format: "00%02X", $0) }.joined(separator: ", ")
            if command == .periodicHeartRate { diagnostic.reason += "; continuation selector not validated" }
        } else { diagnostic.reason = "Timed out without a valid matching response" }
    }
}

public extension X6Command {
    var featureID: String { String(format: "%02X%02X", Array(bytes)[4], Array(bytes)[5]) }
    static func matching(_ bytes: Data) -> Self? { (sync + [.movement]).first { $0.bytes == bytes } }
}
