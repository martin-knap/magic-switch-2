import AppKit
import SwiftUI
import UserNotifications
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, @unchecked Sendable {
    private var statusItem: NSStatusItem!
    private var menuBarView: MenuBarView!
    private var settingsWindowController: NSWindowController?

    let bluetoothManager = BluetoothManager()
    let deviceStore = BluetoothDeviceStore()
    let servicePublisher = ServicePublisher()
    let serviceBrowser = ServiceBrowser()
    let connectionManager = ConnectionManager()

    private let logger = Logger(subsystem: "com.magicswitch2", category: "AppDelegate")

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupNetworking()
        setupCommandHandler()
        requestNotificationPermission()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "MagicSwitch2")
            button.image?.size = NSSize(width: 18, height: 18)
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        menuBarView = MenuBarView(
            deviceStore: deviceStore,
            bluetoothManager: bluetoothManager
        )
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        showStatusMenu()
    }

    private func showStatusMenu() {
        let menu = menuBarView.buildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Networking

    private func setupNetworking() {
        servicePublisher.onConnectionReceived = { [weak self] connection in
            self?.connectionManager.handleIncomingConnection(connection)
        }
        servicePublisher.start()
        serviceBrowser.start()
    }

    // MARK: - Command Handler

    private func setupCommandHandler() {
        connectionManager.onCommandReceived = { [weak self] command, respond in
            guard let self else { return }
            switch command {
            case .healthCheck:
                respond(.opSuccess)
            case .connectAll:
                let success = self.deviceStore.connectAll()
                respond(success ? .opSuccess : .opFailed)
                if success {
                    self.showNotification(title: "MagicSwitch2", body: "Devices connected to this Mac")
                }
            case .unregisterAll:
                let success = self.deviceStore.unregisterAll()
                respond(success ? .opSuccess : .opFailed)
            }
        }
    }

    // MARK: - Switch Action

    @objc func connectKeyboard(_ sender: NSMenuItem) {
        let result = deviceStore.connectFirst(matching: ["keyboard"])
        showNotification(title: "MagicSwitch2", body: result.message)
    }

    @objc func connectTrackpad(_ sender: NSMenuItem) {
        let result = deviceStore.connectFirst(matching: ["trackpad"])
        showNotification(title: "MagicSwitch2", body: result.message)
    }

    @objc func noopMenuAction(_ sender: NSMenuItem) {
        // Keeps informational menu rows enabled for proper text styling.
    }

    @objc func connectPeripheralFromMenu(_ sender: Any?) {
        guard let peripheral = peripheralFromSender(sender) else { return }
        let result = deviceStore.connectPeripheral(peripheral)
        showNotification(title: "MagicSwitch2", body: result.message)
    }

    @objc func reconnectPeripheralFromMenu(_ sender: Any?) {
        guard let peripheral = peripheralFromSender(sender) else { return }
        let result = deviceStore.reconnectPeripheral(peripheral)
        showNotification(title: "MagicSwitch2", body: result.message)
    }

    @objc func disconnectPeripheralFromMenu(_ sender: Any?) {
        guard let peripheral = peripheralFromSender(sender) else { return }
        let result = deviceStore.disconnectPeripheral(peripheral)
        showNotification(title: "MagicSwitch2", body: result.message)
    }

    @objc func removePeripheralFromMenu(_ sender: Any?) {
        guard let peripheral = peripheralFromSender(sender) else { return }
        let result = deviceStore.forgetPeripheral(peripheral)
        showNotification(title: "MagicSwitch2", body: result.message)
    }

    private func peripheralFromSender(_ sender: Any?) -> BluetoothPeripheral? {
        if let item = sender as? NSMenuItem,
           let peripheral = item.representedObject as? BluetoothPeripheral {
            return peripheral
        }

        if let button = sender as? NSButton,
           let peripheralID = button.identifier?.rawValue {
            if let registered = deviceStore.registeredPeripherals.first(where: { $0.id == peripheralID }) {
                return registered
            }
            return deviceStore.pairedDevices().first(where: { $0.id == peripheralID })
        }

        return nil
    }

    @objc func switchToPeer(_ sender: NSMenuItem) {
        guard let peer = sender.representedObject as? NetworkPeer else { return }
        performSwitch(to: peer)
    }

    private func performSwitch(to peer: NetworkPeer) {
        logger.info("Switching to peer: \(peer.displayName)")

        // First, health check the peer
        connectionManager.send(command: .healthCheck, to: peer.endpoint) { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard response == .opSuccess else {
                    self.showNotification(title: "MagicSwitch2", body: "Peer \(peer.displayName) is not responding")
                    return
                }

                if self.deviceStore.hasConnectedPeripherals {
                    // Devices are connected locally — unregister here and connect on peer
                    self.switchFromLocal(to: peer)
                } else {
                    // Devices not connected locally — unregister on peer and connect here
                    self.switchToLocal(from: peer)
                }
            }
        }
    }

    private func switchFromLocal(to peer: NetworkPeer) {
        logger.info("Unregistering locally and connecting on peer")
        let unregistered = deviceStore.unregisterAll()
        guard unregistered else {
            showNotification(title: "MagicSwitch2", body: "Failed to unregister local devices")
            return
        }

        // Give Bluetooth a moment to process the removal
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            Task { @MainActor [weak self] in
                self?.connectionManager.send(command: .connectAll, to: peer.endpoint) { [weak self] response in
                    Task { @MainActor [weak self] in
                        if response == .opSuccess {
                            self?.showNotification(title: "MagicSwitch2", body: "Devices switched to \(peer.displayName)")
                        } else {
                            self?.showNotification(title: "MagicSwitch2", body: "Failed to connect on \(peer.displayName)")
                        }
                    }
                }
            }
        }
    }

    private func switchToLocal(from peer: NetworkPeer) {
        logger.info("Unregistering on peer and connecting locally")
        connectionManager.send(command: .unregisterAll, to: peer.endpoint) { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard response == .opSuccess else {
                    self.showNotification(title: "MagicSwitch2", body: "Failed to unregister on \(peer.displayName)")
                    return
                }

                // Give Bluetooth a moment to process the removal
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let connected = self.deviceStore.connectAll()
                        if connected {
                            self.showNotification(title: "MagicSwitch2", body: "Devices switched to this Mac")
                        } else {
                            self.showNotification(title: "MagicSwitch2", body: "Failed to connect devices locally")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Settings

    @objc func openSettings(_ sender: Any?) {
        logger.info("Opening settings window")

        if let window = settingsWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            deviceStore: deviceStore,
            serviceBrowser: serviceBrowser,
            connectionManager: connectionManager
        )

        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "MagicSwitch2 Settings"
        window.setContentSize(NSSize(width: 780, height: 520))
        window.minSize = NSSize(width: 700, height: 460)
        window.styleMask.insert(.resizable)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == settingsWindowController?.window else { return }
        settingsWindowController = nil
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        logger.info("\(title): \(body)")
    }
}
