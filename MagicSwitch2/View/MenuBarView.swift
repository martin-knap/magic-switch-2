import AppKit

private final class HoverIconButton: NSButton {
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.activeInActiveApp, .inVisibleRect, .mouseEnteredAndExited]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
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
        let keyboardConnected = hasConnectedDevice(matching: ["keyboard"])
        let trackpadConnected = hasConnectedDevice(matching: ["trackpad"])

        let connectKeyboardItem = NSMenuItem(
            title: "Connect Keyboard",
            action: #selector(AppDelegate.connectKeyboard(_:)),
            keyEquivalent: "k"
        )
        connectKeyboardItem.target = NSApp.delegate
        connectKeyboardItem.isEnabled = !keyboardConnected
        menu.addItem(connectKeyboardItem)

        let connectTrackpadItem = NSMenuItem(
            title: "Connect Trackpad",
            action: #selector(AppDelegate.connectTrackpad(_:)),
            keyEquivalent: "t"
        )
        connectTrackpadItem.target = NSApp.delegate
        connectTrackpadItem.isEnabled = !trackpadConnected
        menu.addItem(connectTrackpadItem)

        menu.addItem(.separator())

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
                let isConnected = peripheral.isConnected
                let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                item.view = buildPeripheralInlineRow(for: peripheral, isConnected: isConnected)
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

    private func hasConnectedDevice(matching keywords: [String]) -> Bool {
        let normalizedKeywords = keywords.map { $0.lowercased() }
        return deviceStore.pairedDevices().contains { device in
            let name = device.displayName.lowercased()
            return device.isConnected && normalizedKeywords.contains { name.contains($0) }
        }
    }

    @MainActor
    private func buildPeripheralInlineRow(for peripheral: BluetoothPeripheral, isConnected: Bool) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 32))

        let nameField = NSTextField(labelWithString: peripheral.displayName)
        nameField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        nameField.textColor = NSColor.labelColor
        nameField.translatesAutoresizingMaskIntoConstraints = false

        let statusField = NSTextField(labelWithString: isConnected ? "Connected" : "Disconnected")
        statusField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        statusField.textColor = isConnected ? .systemGreen : .secondaryLabelColor
        statusField.translatesAutoresizingMaskIntoConstraints = false

        let connectButton = makeIconButton(
            symbol: "link.circle",
            action: #selector(AppDelegate.connectPeripheralFromMenu(_:)),
            toolTip: "Connect",
            peripheralID: peripheral.id,
            enabled: !isConnected
        )
        let reconnectButton = makeIconButton(
            symbol: "arrow.clockwise.circle",
            action: #selector(AppDelegate.reconnectPeripheralFromMenu(_:)),
            toolTip: "Reconnect",
            peripheralID: peripheral.id,
            enabled: true
        )
        let disconnectButton = makeIconButton(
            symbol: "xmark.circle",
            action: #selector(AppDelegate.disconnectPeripheralFromMenu(_:)),
            toolTip: "Disconnect",
            peripheralID: peripheral.id,
            enabled: isConnected
        )
        let removeButton = makeIconButton(
            symbol: "trash.circle",
            action: #selector(AppDelegate.removePeripheralFromMenu(_:)),
            toolTip: "Remove",
            peripheralID: peripheral.id,
            enabled: true
        )

        let buttonStack = NSStackView(views: [connectButton, reconnectButton, disconnectButton, removeButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 6
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(nameField)
        container.addSubview(statusField)
        container.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            nameField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            nameField.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            statusField.leadingAnchor.constraint(greaterThanOrEqualTo: nameField.trailingAnchor, constant: 12),
            statusField.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            buttonStack.leadingAnchor.constraint(equalTo: statusField.trailingAnchor, constant: 12),
            buttonStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            buttonStack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    @MainActor
    private func makeIconButton(
        symbol: String,
        action: Selector,
        toolTip: String,
        peripheralID: String,
        enabled: Bool
    ) -> NSButton {
        let button = HoverIconButton(frame: NSRect(x: 0, y: 0, width: 26, height: 22))
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip) ?? NSImage()
        button.target = NSApp.delegate
        button.action = action
        button.identifier = NSUserInterfaceItemIdentifier(peripheralID)
        button.setButtonType(.momentaryPushIn)
        button.bezelStyle = .texturedRounded
        button.isBordered = true
        button.showsBorderOnlyWhileMouseInside = true
        button.imagePosition = .imageOnly
        button.contentTintColor = enabled ? .white : .secondaryLabelColor
        button.toolTip = toolTip
        button.isEnabled = enabled
        _ = button.sendAction(on: [.leftMouseDown])
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 26),
            button.heightAnchor.constraint(equalToConstant: 22)
        ])
        return button
    }
}
