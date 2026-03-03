import Foundation
import IOBluetooth
import Combine
import os

final class BluetoothDeviceStore: ObservableObject {
    @Published var registeredPeripherals: [BluetoothPeripheral] = []

    private let logger = Logger(subsystem: "com.magicswitch2", category: "BluetoothDeviceStore")
    private let storageKey = "registeredPeripherals"

    init() {
        loadPeripherals()
    }

    // MARK: - Paired Devices (system-level)

    func pairedDevices() -> [BluetoothPeripheral] {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }
        return devices.compactMap { device in
            guard let address = device.addressString else { return nil }
            return BluetoothPeripheral(
                id: address,
                name: device.name ?? ""
            )
        }
    }

    // MARK: - Registration

    func register(_ peripheral: BluetoothPeripheral) {
        guard !registeredPeripherals.contains(where: { $0.id == peripheral.id }) else { return }
        registeredPeripherals.append(peripheral)
        savePeripherals()
    }

    func unregister(_ peripheral: BluetoothPeripheral) {
        registeredPeripherals.removeAll { $0.id == peripheral.id }
        savePeripherals()
    }

    func isRegistered(_ peripheral: BluetoothPeripheral) -> Bool {
        registeredPeripherals.contains { $0.id == peripheral.id }
    }

    // MARK: - Bluetooth Operations

    /// Connect all registered peripherals
    func connectAll() -> Bool {
        logger.info("Connecting all registered peripherals...")
        var allSuccess = true
        for peripheral in registeredPeripherals {
            allSuccess = connectPeripheral(peripheral) && allSuccess
        }
        return allSuccess
    }

    /// Connect first matching peripheral by name keywords (case-insensitive).
    func connectFirst(matching keywords: [String]) -> Bool {
        let normalizedKeywords = keywords.map { $0.lowercased() }

        let candidate = registeredPeripherals.first {
            let name = $0.displayName.lowercased()
            return normalizedKeywords.contains { name.contains($0) }
        } ?? pairedDevices().first {
            let name = $0.displayName.lowercased()
            return normalizedKeywords.contains { name.contains($0) }
        }

        guard let candidate else {
            logger.error("No matching peripheral found for keywords: \(keywords.joined(separator: ","))")
            return false
        }

        return connectPeripheral(candidate)
    }

    func connectPeripheral(_ peripheral: BluetoothPeripheral) -> Bool {
        performConnect(peripheral)
    }

    func disconnectPeripheral(_ peripheral: BluetoothPeripheral) -> Bool {
        guard let device = IOBluetoothDevice(addressString: peripheral.id) else {
            logger.error("Failed to create device for \(peripheral.id)")
            return false
        }

        let result = device.closeConnection()
        if result != kIOReturnSuccess {
            logger.error("Failed to disconnect \(peripheral.displayName): \(result)")
            return false
        }

        logger.info("Disconnected \(peripheral.displayName)")
        return true
    }

    func reconnectPeripheral(_ peripheral: BluetoothPeripheral) -> Bool {
        let _ = disconnectPeripheral(peripheral)
        return connectPeripheral(peripheral)
    }

    /// Unregister (remove pairing) all registered peripherals using private API
    func unregisterAll() -> Bool {
        logger.info("Unregistering all registered peripherals...")
        var allSuccess = true
        for peripheral in registeredPeripherals {
            guard let device = IOBluetoothDevice(addressString: peripheral.id) else {
                logger.error("Failed to create device for \(peripheral.id)")
                allSuccess = false
                continue
            }
            let selector = Selector(("remove"))
            if device.responds(to: selector) {
                device.perform(selector)
                logger.info("Unregistered \(peripheral.displayName)")
            } else {
                logger.error("Device does not respond to remove selector: \(peripheral.displayName)")
                allSuccess = false
            }
        }
        return allSuccess
    }

    /// Check if any registered peripheral is currently connected
    var hasConnectedPeripherals: Bool {
        registeredPeripherals.contains { $0.isConnected }
    }

    // MARK: - Persistence

    private func savePeripherals() {
        guard let data = try? JSONEncoder().encode(registeredPeripherals) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadPeripherals() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let peripherals = try? JSONDecoder().decode([BluetoothPeripheral].self, from: data) else {
            return
        }
        registeredPeripherals = peripherals
    }

    private func performConnect(_ peripheral: BluetoothPeripheral) -> Bool {
        guard let device = IOBluetoothDevice(addressString: peripheral.id) else {
            logger.error("Failed to create device for \(peripheral.id)")
            return false
        }

        let result = device.openConnection()
        if result != kIOReturnSuccess {
            logger.error("Failed to connect \(peripheral.displayName): \(result)")
            return false
        }

        logger.info("Connected \(peripheral.displayName)")
        return true
    }
}
