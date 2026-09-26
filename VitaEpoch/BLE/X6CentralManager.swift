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
    private var assembler = X6FrameAssembler()
    private var pending: [X6Command] = []
    private var active: X6Command?
    private var pages: Set<UInt8> = []
    private var connectionTimeout: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var scanTimeout: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var measurementTimeout: Task<Void, Never>?
    private var failures = 0
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
        connectionTimeout?.cancel(); timeout?.cancel(); measurementTimeout?.cancel(); active = nil; pending = []; pages = []
        ready = false; syncing = false; measuring = false; writer = nil; responseSubscribed = false
        assembler.reset(); battery = nil; info = [:]; pendingControl = nil
    }
    func sync() {
        guard ready, !syncing, !measuring, pendingControl == nil else { return }
        failures = 0; issue = nil; syncing = true; syncSummary = "Syncing…"
        pending = X6Command.sync; sendNext()
    }
    private func sendNext() {
        guard active == nil, let peripheral, peripheral.canSendWriteWithoutResponse else { return }
        guard !pending.isEmpty else {
            syncing = false
            if failures == 0 { store.synced(); syncSummary = "Synced now" }
            else { syncSummary = "Partial sync — \(failures) request(s) incomplete" }
            return
        }
        let command = pending.removeFirst(); active = command; pages = []
        write(command)
        armTimeout()
    }
    private func armTimeout() {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self else { return }
            self.failures += 1; self.active = nil; self.sendNext()
        }
    }
    private func write(_ command: X6Command) {
        guard let peripheral, let writer else { return }
        store.record(RawPacket(deviceID: peripheral.identifier.uuidString, characteristic: "FDD2", direction: .tx, bytes: command.bytes))
        peripheral.writeValue(command.bytes, for: writer, type: .withoutResponse)
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
    private func receiveFrame(_ data: Data, packet: RawPacket) {
        do {
            let frame = try X6Frame(data)
            let samples = try X6Decoder.decode(frame, packet: packet)
            store.ingest(samples)
            guard let active, frame.group == 2, frame.feature == Array(active.bytes)[5] else { return }
            if [.periodicHeartRate, .hrv, .temperature].contains(active) {
                // Only requested day zero counts toward completion; preserve other days if received.
                guard frame.payload[0] == 0 else { return }
                pages.insert(frame.payload[1])
                if pages.count < (active == .periodicHeartRate ? 2 : 4) { armTimeout(); return }
            }
            timeout?.cancel(); self.active = nil; sendNext()
        } catch ProtocolError.unsupportedFeature { /* Evidence is retained; unknown frames are not interpreted. */ }
        catch { issue = "A device packet could not be decoded. Raw data was saved for diagnostics." }
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
        store.record(packet)
        do {
            switch id {
            case "FDD3":
                for frame in assembler.append(data) {
                    let evidence = frame == data ? packet : RawPacket(deviceID: packet.deviceID, characteristic: "FDD3/reassembled", direction: .rx, bytes: frame, timestamp: packet.timestamp)
                    if evidence.id != packet.id { store.record(evidence) }
                    receiveFrame(frame, packet: evidence)
                }
            case "FDD1": store.ingest(try X6Decoder.compactActivity(packet))
            case "2A37":
                let samples = try X6Decoder.heartRate(packet)
                store.ingest(samples)
                if !samples.isEmpty { stopMeasurement() }
            case "2A19": if let level = data.first, level <= 100 { battery = Int(level) }
            case "2A25", "2A28", "2A29": info[id] = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
            case "FDD4": info[id] = data.hex
            default: break
            }
        } catch { issue = "A device packet could not be decoded. Raw data was saved." }
    }
}
