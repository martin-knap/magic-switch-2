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
            guard let device = IOBluetoothDevice(addressString: peripheral.id) else {
                logger.error("Failed to create device for \(peripheral.id)")
                allSuccess = false
                continue
            }
            let result = device.openConnection()
            if result != kIOReturnSuccess {
                logger.error("Failed to connect \(peripheral.displayName): \(result)")
                allSuccess = false
            } else {
                logger.info("Connected \(peripheral.displayName)")
            }
        }
        return allSuccess
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
}
