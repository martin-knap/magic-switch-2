import AppKit

final class MenuBarView {
    private let deviceStore: BluetoothDeviceStore
    private let serviceBrowser: ServiceBrowser
    private let bluetoothManager: BluetoothManager

    var onSwitchClicked: ((NetworkPeer) -> Void)?
    var onSettingsClicked: (() -> Void)?
    var onQuitClicked: (() -> Void)?

    init(deviceStore: BluetoothDeviceStore, serviceBrowser: ServiceBrowser, bluetoothManager: BluetoothManager) {
        self.deviceStore = deviceStore
        self.serviceBrowser = serviceBrowser
        self.bluetoothManager = bluetoothManager
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Bluetooth status
        let btStatus = bluetoothManager.isPoweredOn ? "Bluetooth: On" : "Bluetooth: Off"
        let btItem = NSMenuItem(title: btStatus, action: nil, keyEquivalent: "")
        btItem.isEnabled = false
        menu.addItem(btItem)

        menu.addItem(.separator())

        // Registered peripherals
        let peripheralsHeader = NSMenuItem(title: "Peripherals", action: nil, keyEquivalent: "")
        peripheralsHeader.isEnabled = false
        menu.addItem(peripheralsHeader)

        if deviceStore.registeredPeripherals.isEmpty {
            let noDevices = NSMenuItem(title: "  No devices registered", action: nil, keyEquivalent: "")
            noDevices.isEnabled = false
            menu.addItem(noDevices)
        } else {
            for peripheral in deviceStore.registeredPeripherals {
                let status = peripheral.isConnected ? "Connected" : "Disconnected"
                let dot = peripheral.isConnected ? "\u{25CF}" : "\u{25CB}" // ● or ○
                let item = NSMenuItem(
                    title: "  \(dot) \(peripheral.displayName) — \(status)",
                    action: nil,
                    keyEquivalent: ""
                )
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        // Peers
        let peersHeader = NSMenuItem(title: "Peers", action: nil, keyEquivalent: "")
        peersHeader.isEnabled = false
        menu.addItem(peersHeader)

        if serviceBrowser.peers.isEmpty {
            let noPeers = NSMenuItem(title: "  No peers found", action: nil, keyEquivalent: "")
            noPeers.isEnabled = false
            menu.addItem(noPeers)
        } else {
            for peer in serviceBrowser.peers {
                let item = NSMenuItem(
                    title: "  Switch to \(peer.displayName)",
                    action: #selector(AppDelegate.switchToPeer(_:)),
                    keyEquivalent: ""
                )
                item.representedObject = peer
                item.target = NSApp.delegate
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(AppDelegate.openSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = NSApp.delegate
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // Quit
        menu.addItem(NSMenuItem(
            title: "Quit MagicSwitch2",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        return menu
    }
}
