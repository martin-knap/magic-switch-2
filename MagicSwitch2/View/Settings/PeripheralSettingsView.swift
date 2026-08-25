import SwiftUI

private struct PeripheralConnectionSwitch: View {
    let isConnected: Bool
    let resetToken: Int
    let onToggle: (Bool) -> Void

    @State private var isOn: Bool

    init(isConnected: Bool, resetToken: Int = 0, onToggle: @escaping (Bool) -> Void) {
        self.isConnected = isConnected
        self.resetToken = resetToken
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
        .onChange(of: resetToken) { _, _ in
            isOn = isConnected
        }
    }
}

struct PeripheralSettingsView: View {
    @ObservedObject var deviceStore: BluetoothDeviceStore
    @State private var refreshTick = 0
    @State private var lastOperationMessage: String?
    @State private var lastOperationSucceeded = true
    @State private var activeDeviceIDs: Set<String> = []
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

                                if activeDeviceIDs.contains(device.id) {
                                    ProgressView()
                                        .controlSize(.small)
                                }

                                PeripheralConnectionSwitch(
                                    isConnected: device.isConnected,
                                    resetToken: refreshTick
                                ) { shouldConnect in
                                    activeDeviceIDs.insert(device.id)
                                    if shouldConnect {
                                        if !deviceStore.isRegistered(device) {
                                            deviceStore.register(device)
                                        }
                                        deviceStore.connectPeripheralAsync(device) { result in
                                            finishOperation(result, for: device)
                                        }
                                    } else {
                                        deviceStore.releasePeripheralAsync(device) { result in
                                            finishOperation(result, for: device)
                                        }
                                    }
                                }
                                .disabled(activeDeviceIDs.contains(device.id))
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

    private func finishOperation(_ result: BluetoothOperationResult, for device: BluetoothPeripheral) {
        lastOperationMessage = result.message
        lastOperationSucceeded = result.success
        activeDeviceIDs.remove(device.id)
        refreshTick += 1
    }
}
