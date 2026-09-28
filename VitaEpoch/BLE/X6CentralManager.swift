import Foundation
import CoreBluetooth
import Combine

@MainActor
final class X6CentralManager: NSObject, ObservableObject {
    struct Device: Identifiable { let id: UUID; let name: String; let rssi: Int }
    @Published private(set) var status = "Not connected"
    @Published private(set) var devices: [Device] = []
    @Published private(set) var ready = false
    @Published private(set) var scanning = false
    @Published private(set) var syncing = false
    @Published private(set) var measuring = false
    @Published private(set) var battery: Int?
    @Published private(set) var info: [String: String] = [:]
    @Published private(set) var issue: String?
    @Published private(set) var syncSummary = "No sync yet"
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var discovered: [UUID: CBPeripheral] = [:]
    private var writer: CBCharacteristic?
    private var sessionID = UUID()
    private var requestDeadline: Task<Void, Never>?
    private var continuationTask: Task<Void, Never>?
    private var pending: [X6Command] = []
    private var active: SyncProgress?
    private var incompleteIDs: [String] = []
    private var connectionTimeout: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var scanTimeout: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var measurementTimeout: Task<Void, Never>?
    private var reconnectAttempts = 0
    private var userDisconnected = false
    private var responseSubscribed = false
    private var pendingControl: X6Command?
    private let store: AppStore
    private let rememberedKey = "x6.peripheralID"

    init(store: AppStore) { self.store = store; super.init() }
    func scan() {
        userDisconnected = false
        guard let central else {
            self.central = CBCentralManager(delegate: self, queue: .main)
            return
        }
        guard central.state == .poweredOn else { status = "Bluetooth unavailable"; return }
        devices = []; discovered = [:]; issue = nil
        scanning = true; status = "Looking for X6…"
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanTimeout?.cancel()
        scanTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self else { return }
            self.central?.stopScan(); self.scanning = false
            if self.peripheral == nil { self.status = self.devices.isEmpty ? "No X6 found. Keep the band nearby." : "Choose your X6" }
        }
    }
    func connect(_ id: UUID) {
        guard let device = discovered[id] else { return }
        guard peripheral == nil || peripheral?.state == .disconnected else { return }
        userDisconnected = false; central?.stopScan(); scanning = false; scanTimeout?.cancel()
        clearConnection(); peripheral = device; device.delegate = self; status = "Connecting…"
        central?.connect(device)
        connectionTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, !self.ready else { return }
            self.userDisconnected = true
            self.central?.cancelPeripheralConnection(device)
            self.clearConnection(); self.peripheral = nil
            self.status = "Connection timed out"
            self.issue = "Check that X6 is nearby and disconnected from other apps, then retry."
        }
    }
    func reconnect() {
        userDisconnected = false; reconnectAttempts = 0
        guard let central, central.state == .poweredOn else { scan(); return }
        if let value = UserDefaults.standard.string(forKey: rememberedKey), let id = UUID(uuidString: value),
           let device = central.retrievePeripherals(withIdentifiers: [id]).first {
            discovered[id] = device; connect(id)
        } else { scan() }
    }
    func forget() {
        userDisconnected = true; reconnectTask?.cancel(); scanTimeout?.cancel()
        central?.stopScan(); scanning = false
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        UserDefaults.standard.removeObject(forKey: rememberedKey)
        clearConnection(); peripheral = nil; devices = []; status = "Device forgotten. Saved readings remain available."
    }
    private func clearConnection() {
        connectionTimeout?.cancel(); timeout?.cancel(); measurementTimeout?.cancel(); continuationTask?.cancel(); requestDeadline?.cancel()
        if var progress = active {
            progress.finish(at: Date(), interrupted: "Connection ended before request completion")
            store.diagnostic(progress.diagnostic)
        }
        active = nil; pending = []; sessionID = UUID()
        ready = false; syncing = false; measuring = false; writer = nil; responseSubscribed = false
        store.resetSession(); battery = nil; info = [:]; pendingControl = nil
    }
    func sync() {
        guard ready, !syncing, !measuring, pendingControl == nil else { return }
        incompleteIDs = []; issue = nil; syncing = true; syncSummary = "Syncing…"
        pending = X6Command.sync; sendNext()
    }
    #if DEBUG
    func captureMovement() {
        guard ready, !syncing, !measuring, pendingControl == nil else { return }
        incompleteIDs = []; issue = nil; syncing = true; syncSummary = "Capturing 0213…"
        pending = [.movement]; sendNext()
    }
    #endif
    private func sendNext() {
        guard active == nil, let peripheral, peripheral.canSendWriteWithoutResponse else { return }
        guard !pending.isEmpty else {
            syncing = false
            if incompleteIDs.isEmpty { store.synced(); syncSummary = "Synced now" }
            else { syncSummary = "Partial sync — incomplete: " + incompleteIDs.joined(separator: ", "); store.flush() }
            return
        }
        let command = pending.removeFirst()
        active = SyncProgress(command: command, deviceID: peripheral.identifier.uuidString, startedAt: Date())
        writeSync(command.bytes)
        if command == .movement { advanceMovement(); return }
        requestDeadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(40))
            guard !Task.isCancelled else { return }
            self?.finishRequest()
        }
    }
    private func writeSync(_ bytes: Data) {
        guard peripheral?.canSendWriteWithoutResponse == true else { return }
        active?.wrote(bytes, at: Date())
        if let active { store.diagnostic(active.diagnostic) }
        writeBytes(bytes)
        if active?.command != .movement { armTimeout() }
    }
    private func advanceMovement() {
        continuationTask?.cancel()
        guard let progress = active, progress.command == .movement else { return }
        let now = Date()
        switch progress.movementAction(at: now) {
        case .finish: finishRequest()
        case .write(let bytes):
            if peripheral?.canSendWriteWithoutResponse == true {
                writeSync(bytes)
                advanceMovement()
            } else {
                // Wait for CoreBluetooth capacity; retain the original capture deadline.
                waitForMovement(until: now.addingTimeInterval(0.2))
            }
        case .wait(let until): waitForMovement(until: until)
        }
    }
    private func waitForMovement(until date: Date) {
        continuationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0.01, date.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.advanceMovement()
        }
    }
    private func finishRequest() {
        guard var progress = active else { return }
        timeout?.cancel(); continuationTask?.cancel(); requestDeadline?.cancel()
        progress.finish(at: Date())
        store.diagnostic(progress.diagnostic)
        if !progress.isComplete { incompleteIDs.append(progress.diagnostic.featureID) }
        active = nil
        sendNext()
    }
    private func armTimeout() {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self else { return }
            // Probe each documented day/page variant at most once, only after a valid page.
            if let next = self.active?.continuation, self.peripheral?.canSendWriteWithoutResponse == true {
                self.writeSync(next)
            } else { self.finishRequest() }
        }
    }
    private func scheduleContinuation() {
        continuationTask?.cancel()
        continuationTask = Task { [weak self] in
            // Give automatic multi-notification responses a quiet window before an explicit
            // page request. Empty pages count as received and never terminate the sequence.
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self, let next = self.active?.continuation,
                  self.peripheral?.canSendWriteWithoutResponse == true else { return }
            self.writeSync(next)
        }
    }
    private func write(_ command: X6Command) { writeBytes(command.bytes) }
    private func writeBytes(_ bytes: Data) {
        guard let peripheral, let writer else { return }
        store.receive(RawPacket(deviceID: peripheral.identifier.uuidString, characteristic: "FDD2", direction: .tx, bytes: bytes))
        peripheral.writeValue(bytes, for: writer, type: .withoutResponse)
    }
    func measureHeartRate() {
        guard ready, !syncing, !measuring, pendingControl == nil, peripheral?.canSendWriteWithoutResponse == true else { return }
        measuring = true; write(.startHeartRate)
        measurementTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled, let self else { return }
            self.stopMeasurement(); self.issue = "Measurement timed out. Adjust the band and try again."
        }
    }
    func stopMeasurement() {
        measurementTimeout?.cancel()
        if measuring {
            if peripheral?.canSendWriteWithoutResponse == true { write(.stopHeartRate) }
            else { pendingControl = .stopHeartRate }
        }
        measuring = false
    }
    private func updateReady() {
        guard writer != nil, responseSubscribed, !ready else { return }
        connectionTimeout?.cancel()
        ready = true; status = "Connected"; reconnectAttempts = 0
        if let peripheral { UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: rememberedKey) }
        sync()
    }
    private func receive(_ result: PacketProcessingResult) {
        if let error = result.error { issue = error }
        if result.measuredHeartRate { stopMeasurement() }
        for receipt in result.receipts {
            guard active != nil else { continue }
            active?.received(receipt)
            if let active { store.diagnostic(active.diagnostic) }
            if active?.command == .movement { advanceMovement(); continue }
            if active?.isComplete == true { finishRequest() }
            else if receipt.frame.group == 2 && String(format: "02%02X", receipt.frame.feature) == active?.diagnostic.featureID {
                if receipt.error == nil { armTimeout() }
                scheduleContinuation()
            }
        }
    }

}

// CoreBluetooth delegates are delivered on the .main queue configured above.
extension X6CentralManager: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn { scanning = false; scanTimeout?.cancel() }
        switch central.state {
        case .poweredOn: if !userDisconnected { scan() }
        case .unauthorized: clearConnection(); status = "Bluetooth permission denied. Enable it in Settings."
        case .poweredOff: clearConnection(); status = "Bluetooth is off"
        case .unsupported: clearConnection(); status = "Bluetooth is unavailable on this device"
        default: status = "Preparing Bluetooth…"
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        guard name.uppercased() == "X6" else { return }
        discovered[peripheral.identifier] = peripheral
        if !devices.contains(where: { $0.id == peripheral.identifier }) {
            devices.append(Device(id: peripheral.identifier, name: name, rssi: RSSI.intValue))
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = "Discovering services…"
        peripheral.discoverServices([CBUUID(string: "FDDA"), CBUUID(string: "180D"), CBUUID(string: "180F"), CBUUID(string: "180A")])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        clearConnection(); status = "Connection failed"; issue = error?.localizedDescription
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        clearConnection(); self.peripheral = nil
        guard !userDisconnected else { return }
        status = "Disconnected — saved data is available"
        guard reconnectAttempts < 3 else { issue = "Reconnect to try again."; return }
        reconnectAttempts += 1
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, !self.userDisconnected, self.central?.state == .poweredOn else { return }
            self.discovered[peripheral.identifier] = peripheral; self.connect(peripheral.identifier)
        }
    }
}

extension X6CentralManager: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { issue = error?.localizedDescription; return }
        guard peripheral.services?.contains(where: { $0.uuid == CBUUID(string: "FDDA") }) == true else {
            issue = "This device does not expose the expected X6 service."; return
        }
        for service in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: service) }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { issue = error?.localizedDescription; return }
        for c in service.characteristics ?? [] {
            let id = c.uuid.uuidString
            if id == "FDD2", c.properties.contains(.writeWithoutResponse) { writer = c }
            if ["FDD1", "FDD3", "2A37", "2A19"].contains(id), c.properties.contains(.notify) { peripheral.setNotifyValue(true, for: c) }
            if ["2A19", "2A25", "2A28", "2A29", "FDD4"].contains(id), c.properties.contains(.read) { peripheral.readValue(for: c) }
        }
        updateReady()
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error { issue = "Notification subscription failed: \(error.localizedDescription)"; return }
        if characteristic.uuid == CBUUID(string: "FDD3") { responseSubscribed = characteristic.isNotifying }
        updateReady()
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        if let command = pendingControl { pendingControl = nil; write(command) }
        if syncing { sendNext() }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { issue = error.localizedDescription; return }
        guard let data = characteristic.value else { return }
        let id = characteristic.uuid.uuidString
        let packet = RawPacket(deviceID: peripheral.identifier.uuidString, characteristic: id, direction: .rx, bytes: data)
        let session = sessionID
        store.receive(packet) { [weak self] result in
            guard let self, self.sessionID == session else { return }
            self.receive(result)
        }
        // Small standard device-information values only; all frame parsing and archive I/O
        // are handled by ArchiveWorker, off MainActor.
        switch id {
        case "2A19": if let level = data.first, level <= 100 { battery = Int(level) }
        case "2A25", "2A28", "2A29": info[id] = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
        case "FDD4": info[id] = data.hex
        default: break
        }
    }
}
