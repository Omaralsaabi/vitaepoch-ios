import SwiftUI

struct DeviceView: View {
    @EnvironmentObject private var ble: X6CentralManager
    @EnvironmentObject private var store: AppStore
    @State private var confirmForget = false
    var body: some View {
        Page {
            Surface {
                Image(systemName: "sensor.tag.radiowaves.forward").font(.system(size: 38)).foregroundStyle(.teal).accessibilityHidden(true)
                Text("X6").font(.largeTitle.bold())
                Text(ble.status).foregroundStyle(.secondary)
                if let battery = ble.battery { Label("Battery \(battery)%", systemImage: "battery.75percent").font(.subheadline) }
                if !ble.ready {
                    Button(ble.scanning ? "Scanning…" : "Find my band") { ble.scan() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(ble.scanning)
                    Text("Keep X6 nearby. Disconnect it from Da Halo if pairing does not complete.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button(ble.syncing ? "Syncing…" : "Sync now") { ble.sync() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(ble.syncing || ble.measuring)
                }
                Text(ble.syncSummary).font(.caption).foregroundStyle(.secondary)
            }
            if !ble.devices.isEmpty && !ble.ready {
                Surface {
                    Text("Nearby bands").font(.headline)
                    ForEach(ble.devices) { device in
                        Button { ble.connect(device.id) } label: {
                            HStack { Label(device.name, systemImage: "radiowaves.left.and.right"); Spacer(); Text("\(device.rssi) dBm").font(.caption) }.frame(minHeight: 44)
                        }
                    }
                }
            }
            if let issue = ble.issue { Label(issue, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.orange) }
            Surface {
                LabeledContent("Firmware", value: ble.info["2A28"] ?? "Not read yet")
                LabeledContent("Manufacturer", value: ble.info["2A29"] ?? "Not read yet")
                LabeledContent("Serial", value: ble.info["2A25"] ?? "Not read yet")
            }.font(.subheadline)
            Surface {
                Button("Reconnect", systemImage: "arrow.clockwise") { ble.reconnect() }.frame(minHeight: 44).disabled(ble.ready)
                Button("Forget device", systemImage: "xmark.circle", role: .destructive) { confirmForget = true }.frame(minHeight: 44)
            }
            Surface {
                Label("On this iPhone", systemImage: "lock.shield").font(.headline)
                Text("Your X6 readings and diagnostic packets are stored locally. No account or server is required.").font(.subheadline).foregroundStyle(.secondary)
                Text("Apple Health integration is planned. This build does not request HealthKit access.").font(.caption).foregroundStyle(.secondary)
            }
            #if DEBUG
            NavigationLink("Developer diagnostics") { DiagnosticsView() }.font(.subheadline)
            #endif
            if let error = store.storageError { Text(error).foregroundStyle(.orange).font(.caption) }
        }.navigationTitle("Device")
            .confirmationDialog("Forget this X6? Saved readings will remain on your iPhone.", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Forget device", role: .destructive) { ble.forget() }
            }
    }
}

#if DEBUG
struct DiagnosticsView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        List {
            Section("Archive") {
                LabeledContent("Packets", value: "\(store.archive.packets.count)")
                LabeledContent("Decoded records", value: "\(store.archive.samples.count)")
                Text("x6-v0.1 · Unknown frames are saved without decoding. FDD5 is never written.").font(.caption)
            }
            Section("Latest 100 packets") {
                ForEach(Array(store.archive.packets.suffix(100).reversed())) { packet in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(packet.direction.rawValue.uppercased()) · \(packet.characteristic) · \(packet.timestamp.formatted(date: .omitted, time: .standard))").font(.caption.bold())
                        Text(packet.bytes.hex).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
        }.navigationTitle("Diagnostics")
    }
}
#endif
