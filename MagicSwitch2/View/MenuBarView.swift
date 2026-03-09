import AppKit
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

private struct PeripheralMenuRow: View {
    let peripheral: BluetoothPeripheral
    let isConnected: Bool
    let onToggleConnection: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: peripheral.systemImageName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 22)

            Text(peripheral.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 12)

            PeripheralConnectionSwitch(
                isConnected: isConnected,
                onToggle: onToggleConnection
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 320, alignment: .leading)
    }
}

final class MenuBarView {
    private let deviceStore: BluetoothDeviceStore
    private let bluetoothManager: BluetoothManager

    var onSwitchClicked: ((NetworkPeer) -> Void)?
    var onSettingsClicked: (() -> Void)?
    var onQuitClicked: (() -> Void)?

    init(deviceStore: BluetoothDeviceStore, bluetoothManager: BluetoothManager) {
        self.deviceStore = deviceStore
        self.bluetoothManager = bluetoothManager
    }

    @MainActor
    func buildMenu() -> NSMenu {
        let menu = NSMenu()

        if deviceStore.registeredPeripherals.isEmpty {
            let noDevices = NSMenuItem(title: "  No devices registered", action: nil, keyEquivalent: "")
            noDevices.isEnabled = false
            menu.addItem(noDevices)
        } else {
            for peripheral in deviceStore.registeredPeripherals {
                let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                item.view = buildPeripheralInlineRow(for: peripheral, isConnected: peripheral.isConnected)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(AppDelegate.openSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = NSApp.delegate
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Quit MagicSwitch2",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        return menu
    }

    @MainActor
    private func buildPeripheralInlineRow(for peripheral: BluetoothPeripheral, isConnected: Bool) -> NSView {
        let view = PeripheralMenuRow(
            peripheral: peripheral,
            isConnected: isConnected,
            onToggleConnection: { [weak deviceStore] shouldConnect in
                guard let deviceStore else { return }
                if shouldConnect {
                    if !deviceStore.isRegistered(peripheral) {
                        deviceStore.register(peripheral)
                    }
                    _ = deviceStore.connectPeripheral(peripheral)
                } else {
                    _ = deviceStore.disconnectPeripheral(peripheral)
                }
            }
        )

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 54)
        return hostingView
    }
}
