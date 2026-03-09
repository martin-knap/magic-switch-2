import SwiftUI

private struct PeripheralConnectionSwitch: View {
    let isConnected: Bool
    let onToggle: (Bool) -> Void

    @State private var isOn: Bool

    init(isConnected: Bool, onToggle: @escaping (Bool) -> Void) {
        self.isConnected = isConnected
        self.onToggle = onToggle
        _isOn = State(initialValue: isConnected)
    }

    var body: some View {
        Toggle("", isOn: Binding(
            get: { isOn },
            set: { newValue in
                isOn = newValue
                onToggle(newValue)
            }
        ))
        .toggleStyle(.switch)
        .labelsHidden()
        .tint(.blue)
        .onChange(of: isConnected) { _, newValue in
            isOn = newValue
        }
    }
}

struct PeripheralSettingsView: View {
    @ObservedObject var deviceStore: BluetoothDeviceStore
    @State private var refreshTick = 0
    @State private var lastOperationMessage: String?
    @State private var lastOperationSucceeded = true
    private let refreshTimer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

    var body: some View {
        let knownDevices = {
            _ = refreshTick
            return deviceStore.knownDevices()
        }()

        VStack(alignment: .leading, spacing: 16) {
            if let lastOperationMessage {
                Text(lastOperationMessage)
                    .font(.caption)
                    .foregroundColor(lastOperationSucceeded ? .green : .orange)
                    .padding(.horizontal)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if knownDevices.isEmpty {
                        Text("No known Bluetooth devices found.")
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    } else {
                        ForEach(Array(knownDevices)) { device in
                            HStack(spacing: 12) {
                                Image(systemName: device.systemImageName)
                                    .font(.title2)
                                    .foregroundStyle(.primary)
                                    .frame(width: 28)

                                Text(device.displayName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Spacer(minLength: 12)

                                PeripheralConnectionSwitch(isConnected: device.isConnected) { shouldConnect in
                                    let result: BluetoothOperationResult

                                    if shouldConnect {
                                        if !deviceStore.isRegistered(device) {
                                            deviceStore.register(device)
                                        }
                                        result = deviceStore.connectPeripheral(device)
                                    } else {
                                        result = deviceStore.disconnectPeripheral(device)
                                    }

                                    lastOperationMessage = result.message
                                    lastOperationSucceeded = result.success
                                    refreshTick += 1
                                }
                            }
                            .padding(16)
                            .background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                }
                .padding()
            }

            GlassEffectContainer {
                HStack {
                    Button("Refresh") {
                        refreshTick += 1
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .onReceive(refreshTimer) { _ in
            refreshTick += 1
        }
    }
}
