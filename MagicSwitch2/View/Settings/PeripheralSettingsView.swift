import SwiftUI

struct PeripheralSettingsView: View {
    @ObservedObject var deviceStore: BluetoothDeviceStore
    @State private var refreshTick = 0
    private let refreshTimer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

    var body: some View {
        let pairedDevices = {
            _ = refreshTick
            return deviceStore.pairedDevices()
        }()

        VStack(alignment: .leading, spacing: 12) {
            Text("Register Bluetooth peripherals to switch between Macs.")
                .font(.callout)
                .foregroundColor(.secondary)

            List {
                if pairedDevices.isEmpty {
                    Text("No paired Bluetooth devices found.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(pairedDevices)) { device in
                        let isConnected = device.isConnected
                        let isRegistered = deviceStore.isRegistered(device)

                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.displayName)
                                    .fontWeight(isRegistered ? .semibold : .regular)
                                    .foregroundStyle(isConnected ? .white : .primary)
                                Text(device.id)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if isConnected {
                                Text("Connected")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.green.opacity(0.14))
                                    .clipShape(Capsule())
                            }

                            if isRegistered {
                                Button {
                                    _ = deviceStore.connectPeripheral(device)
                                    refreshTick += 1
                                } label: {
                                    Label("Connect", systemImage: "link.circle")
                                }
                                .buttonStyle(.glass)
                                .disabled(isConnected)

                                Button {
                                    _ = deviceStore.reconnectPeripheral(device)
                                    refreshTick += 1
                                } label: {
                                    Image(systemName: "arrow.clockwise.circle")
                                }
                                .help("Reconnect")
                                .buttonStyle(.glass)

                                Button {
                                    _ = deviceStore.disconnectPeripheral(device)
                                    refreshTick += 1
                                } label: {
                                    Image(systemName: "xmark.circle")
                                }
                                .help("Disconnect")
                                .buttonStyle(.glass)

                                Button("Remove") {
                                    deviceStore.unregister(device)
                                    refreshTick += 1
                                }
                                .buttonStyle(.glass)
                            } else {
                                Button("Register") {
                                    deviceStore.register(device)
                                    refreshTick += 1
                                }
                                .buttonStyle(.glass)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            GlassEffectContainer {
                HStack {
                    Button("Refresh") {
                        refreshTick += 1
                    }
                    .buttonStyle(.glass)

                    Spacer()

                    Text("\(deviceStore.registeredPeripherals.count) registered")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .onReceive(refreshTimer) { _ in
            refreshTick += 1
        }
    }
}
