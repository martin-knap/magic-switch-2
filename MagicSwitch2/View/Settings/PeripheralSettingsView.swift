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
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.displayName)
                                    .fontWeight(deviceStore.isRegistered(device) ? .semibold : .regular)
                                Text(device.id)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if device.isConnected {
                                Text("Connected")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }

                            if deviceStore.isRegistered(device) {
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
                                .buttonStyle(.glassProminent)
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
