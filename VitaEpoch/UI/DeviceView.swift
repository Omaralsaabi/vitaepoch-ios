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
                            HStack { Label(device.name, systemImage: "antenna.radiowaves.left.and.right"); Spacer(); Text("\(device.rssi) dBm").font(.caption) }.frame(minHeight: 44)
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
    @EnvironmentObject private var ble: X6CentralManager
    @EnvironmentObject private var store: AppStore
    var body: some View {
        List {
            Section("Archive") {
                LabeledContent("Packets", value: "\(store.archive.packets.count)")
                LabeledContent("Decoded records", value: "\(store.archive.samples.count)")
                Text("x6-v0.3 · Unknown frames are saved without decoding. FDD5 is never written.").font(.caption)
            }
            Section("0213 raw movement capture") {
                Button("Capture current-day movement burst") { ble.captureMovement() }
                    .disabled(!ble.ready || ble.syncing || ble.measuring)
                LabeledContent("Minute positions", value: "\((store.archive.movementSamples ?? []).count)")
                Text("Starts with 0000; allows an automatic burst, then requests each missing 0001–0007 once. Raw movement-like bytes only. No sleep-stage inference.").font(.caption)
                Button("Capture previous-day 0100 (00:00–02:59)") { ble.capturePreviousMovement(page: 0) }
                    .disabled(!ble.ready || ble.syncing || ble.measuring)
                Button("Capture previous-day 0107 (21:00–23:59)") { ble.capturePreviousMovement(page: 7) }
                    .disabled(!ble.ready || ble.syncing || ble.measuring)
                Text("Previous-day requests fetch one page only. Only 0100 and 0107 have been physically observed; other 01PP pages remain unvalidated.").font(.caption)
            }
            Section("Sync request history") {
                ForEach(Array((store.archive.syncDiagnostics ?? []).reversed())) { request in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(request.featureID).font(.headline.monospaced())
                        Text(request.reason).font(.caption)
                        if request.featureID == "0213" {
                            Text("Received pages: " + request.receivedSelectors.joined(separator: ", ")).font(.caption)
                            Text("Positions represented in this capture: \(request.receivedPages.count * 180)").font(.caption)
                        }
                        Text(request.elapsed.map { String(format: "Elapsed %.3f s", $0) } ?? "Elapsed: not recorded").font(.caption)
                        ForEach(Array(request.writes.enumerated()), id: \.offset) { _, write in
                            Text("TX \(write.bytesHex) · variant \(write.variantHex)").font(.system(.caption2, design: .monospaced))
                        }
                        ForEach(Array(request.responses.enumerated()), id: \.offset) { index, response in
                            Text("#\(index+1) +\(String(format: "%.3f", response.elapsed))s · \(response.featureID) \(response.prefixHex) · \(response.byteCount) bytes · \(response.sampleCount) records · \(response.status) \(request.acquisition(for: response))")
                                .font(.system(.caption2, design: .monospaced))
                        }
                    }.textSelection(.enabled)
                }
            }
            Section("Timestamp references") {
                Text("Manual 0209: captured 26 Sep reference. Four captured 020B times: independently confirmed by Da Halo export. 0219: provisional. Live 2A37: receipt time. Page histories: local day/slot; no manual correction.").font(.caption)
                ForEach(store.archive.timestampReferences ?? [], id: \.id) { reference in
                    Text("\(reference.id) · \(reference.timeZoneID) · adjustment \(Int(reference.adjustment))s; capture day only").font(.caption)
                }
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
