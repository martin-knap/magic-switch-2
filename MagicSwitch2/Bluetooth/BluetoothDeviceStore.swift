import Foundation
import IOBluetooth
import Combine
import os

struct BluetoothOperationResult {
    let success: Bool
    let message: String
}

private final class BluetoothPairingObserver: NSObject, IOBluetoothDevicePairDelegate {
    private let deviceName: String
    private let logger: Logger

    var didFinish = false
    var error: IOReturn = kIOReturnSuccess
    var promptMessage: String?

    init(deviceName: String, logger: Logger) {
        self.deviceName = deviceName
        self.logger = logger
    }

    func devicePairingStarted(_ sender: Any!) {
        logger.info("Pairing started for \(self.deviceName, privacy: .public)")
    }

    func devicePairingConnecting(_ sender: Any!) {
        logger.info("Pairing connecting for \(self.deviceName, privacy: .public)")
    }

    func devicePairingConnected(_ sender: Any!) {
        logger.info("Pairing connected for \(self.deviceName, privacy: .public)")
    }

    func devicePairingPINCodeRequest(_ sender: Any!) {
        promptMessage = "If macOS prompts for a PIN, type it on \(deviceName) and confirm."
        logger.info("PIN code requested for \(self.deviceName, privacy: .public)")
    }

    func devicePairingUserConfirmationRequest(_ sender: Any!, numericValue: BluetoothNumericValue) {
        promptMessage = "Confirm code \(numericValue) for \(deviceName) if macOS asks."
        logger.info("User confirmation requested for \(self.deviceName, privacy: .public) with code \(numericValue)")
        (sender as? IOBluetoothDevicePair)?.replyUserConfirmation(true)
    }

    func devicePairingUserPasskeyNotification(_ sender: Any!, passkey: BluetoothPasskey) {
        promptMessage = "Type passkey \(String(format: "%06u", passkey)) on \(deviceName), then press Return."
        logger.info("Passkey notification for \(self.deviceName, privacy: .public)")
    }

    func devicePairingFinished(_ sender: Any!, error: IOReturn) {
        self.error = error
        didFinish = true
        logger.info("Pairing finished for \(self.deviceName, privacy: .public) with error \(error)")
    }

    func deviceSimplePairingComplete(_ sender: Any!, status: BluetoothHCIEventStatus) {
        logger.info("Simple pairing completed for \(self.deviceName, privacy: .public) with status \(status)")
    }
}

private final class BluetoothInquiryObserver: NSObject, IOBluetoothDeviceInquiryDelegate {
    private let targetPeripheral: BluetoothPeripheral
    private let logger: Logger

    var foundDevices: [IOBluetoothDevice] = []
    var didComplete = false
    var error: IOReturn = kIOReturnSuccess

    init(targetPeripheral: BluetoothPeripheral, logger: Logger) {
        self.targetPeripheral = targetPeripheral
        self.logger = logger
    }

    func deviceInquiryStarted(_ sender: IOBluetoothDeviceInquiry) {
        logger.info("Inquiry started for \(self.targetPeripheral.displayName, privacy: .public)")
    }

    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry, device: IOBluetoothDevice) {
        foundDevices.append(device)
        logger.info("Inquiry found device \(device.name ?? device.addressString ?? "unknown", privacy: .public)")
    }

    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry, error: IOReturn, aborted: Bool) {
        self.error = error
        didComplete = true
        logger.info("Inquiry completed for \(self.targetPeripheral.displayName, privacy: .public) with error \(error), aborted: \(aborted)")
    }

    func bestMatch() -> IOBluetoothDevice? {
        let targetName = targetPeripheral.displayName.lowercased()
        let targetAddress = targetPeripheral.id.lowercased()

        if let exactAddress = foundDevices.first(where: { ($0.addressString ?? "").lowercased() == targetAddress }) {
            return exactAddress
        }

        if let exactName = foundDevices.first(where: { ($0.name ?? "").lowercased() == targetName }) {
            return exactName
        }

        let fallbackKeywords = inferredKeywords(from: targetName)
        if fallbackKeywords.isEmpty == false {
            return foundDevices.first {
                let name = ($0.name ?? "").lowercased()
                return fallbackKeywords.allSatisfy { name.contains($0) }
            } ?? foundDevices.first {
                let name = ($0.name ?? "").lowercased()
                return fallbackKeywords.contains { name.contains($0) }
            }
        }

        return nil
    }

    private func inferredKeywords(from targetName: String) -> [String] {
        if targetName.contains("keyboard") {
            return ["keyboard"]
        }

        if targetName.contains("trackpad") {
            return ["trackpad"]
        }

        if targetName.contains("mouse") {
            return ["mouse"]
        }

        return []
    }
}

final class BluetoothDeviceStore: ObservableObject {
    @Published var registeredPeripherals: [BluetoothPeripheral] = []

    private let logger = Logger(subsystem: "com.magicswitch2", category: "BluetoothDeviceStore")
    private let storageKey = "registeredPeripherals"
    private let recoveryDelay: TimeInterval = 0.75
    private let pairingTimeout: TimeInterval = 20.0
    private let inquiryTimeout: TimeInterval = 8.0
    private let pollingInterval: TimeInterval = 0.2

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

    func knownDevices() -> [BluetoothPeripheral] {
        var devicesByID: [String: BluetoothPeripheral] = [:]

        for peripheral in registeredPeripherals {
            devicesByID[peripheral.id] = peripheral
        }

        for peripheral in pairedDevices() {
            if let existing = devicesByID[peripheral.id], existing.name.isEmpty == false, peripheral.name.isEmpty {
                continue
            }
            devicesByID[peripheral.id] = peripheral
        }

        return devicesByID.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
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
            allSuccess = connectPeripheral(peripheral).success && allSuccess
        }
        return allSuccess
    }

    /// Connect first matching peripheral by name keywords (case-insensitive).
    func connectFirst(matching keywords: [String]) -> BluetoothOperationResult {
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
            return BluetoothOperationResult(
                success: false,
                message: "No matching Bluetooth device found for \(keywords.joined(separator: ", "))"
            )
        }

        return connectPeripheral(candidate)
    }

    func connectPeripheral(_ peripheral: BluetoothPeripheral) -> BluetoothOperationResult {
        guard bluetoothIsPoweredOn else {
            return failureResult("Bluetooth is turned off on this Mac")
        }

        guard let storedDevice = bluetoothDevice(for: peripheral) else {
            logger.error("Failed to create device for \(peripheral.id)")
            return failureResult("Failed to access \(peripheral.displayName)")
        }

        if storedDevice.isConnected() {
            return successResult("\(peripheral.displayName) is already connected")
        }

        let device = preferredDeviceReference(for: peripheral, fallback: storedDevice)

        if device.isPaired() == false {
            let discoveredDevice = discoverDeviceForPairing(peripheral) ?? device
            return pairAndConnectPeripheral(peripheral, device: discoveredDevice)
        }

        let directResult = device.openConnection()
        if isSuccessfulConnectionResult(directResult, device: device) {
            logger.info("Connected \(peripheral.displayName) directly")
            return successResult("\(peripheral.displayName) connected")
        }

        logger.error("Direct connect failed for \(peripheral.displayName): \(directResult)")
        return performRecoveryConnect(for: peripheral, device: device, initialResult: directResult)
    }

    func disconnectPeripheral(_ peripheral: BluetoothPeripheral) -> BluetoothOperationResult {
        guard bluetoothIsPoweredOn else {
            return failureResult("Bluetooth is turned off on this Mac")
        }

        guard let device = bluetoothDevice(for: peripheral) else {
            logger.error("Failed to create device for \(peripheral.id)")
            return failureResult("Failed to access \(peripheral.displayName)")
        }

        let result = device.closeConnection()
        if result != kIOReturnSuccess {
            logger.error("Failed to disconnect \(peripheral.displayName): \(result)")
            return failureResult("Failed to disconnect \(peripheral.displayName) (\(result))")
        }

        logger.info("Disconnected \(peripheral.displayName)")
        return successResult("\(peripheral.displayName) disconnected")
    }

    func reconnectPeripheral(_ peripheral: BluetoothPeripheral) -> BluetoothOperationResult {
        _ = disconnectPeripheral(peripheral)
        waitForBluetoothStatePropagation()
        return connectPeripheral(peripheral)
    }

    func forgetPeripheral(_ peripheral: BluetoothPeripheral, unregisterFromApp: Bool = false) -> BluetoothOperationResult {
        guard bluetoothIsPoweredOn else {
            return failureResult("Bluetooth is turned off on this Mac")
        }

        guard let device = bluetoothDevice(for: peripheral) else {
            logger.error("Failed to create device for \(peripheral.id)")
            return failureResult("Failed to access \(peripheral.displayName)")
        }

        let disconnectResult = device.closeConnection()
        if disconnectResult == kIOReturnSuccess {
            logger.info("Closed connection before forgetting \(peripheral.displayName)")
        }

        guard removePairing(for: peripheral, device: device) else {
            return failureResult("Failed to forget \(peripheral.displayName) on this Mac")
        }

        if unregisterFromApp {
            unregister(peripheral)
            return successResult("\(peripheral.displayName) forgotten and unregistered")
        }

        return successResult("\(peripheral.displayName) forgotten. Turn the device off and on, then click Connect to pair it again.")
    }

    /// Unregister (remove pairing) all registered peripherals using private API
    func unregisterAll() -> Bool {
        logger.info("Unregistering all registered peripherals...")
        var allSuccess = true
        for peripheral in registeredPeripherals {
            guard let device = bluetoothDevice(for: peripheral) else {
                logger.error("Failed to create device for \(peripheral.id)")
                allSuccess = false
                continue
            }
            if removePairing(for: peripheral, device: device) == false {
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

    private func bluetoothDevice(for peripheral: BluetoothPeripheral) -> IOBluetoothDevice? {
        IOBluetoothDevice(addressString: peripheral.id)
    }

    private var bluetoothIsPoweredOn: Bool {
        IOBluetoothHostController.default().powerState != kBluetoothHCIPowerStateOFF
    }

    private func isSuccessfulConnectionResult(_ result: IOReturn, device: IOBluetoothDevice) -> Bool {
        result == kIOReturnSuccess || device.isConnected()
    }

    private func performRecoveryConnect(
        for peripheral: BluetoothPeripheral,
        device: IOBluetoothDevice,
        initialResult: IOReturn
    ) -> BluetoothOperationResult {
        let disconnectResult = device.closeConnection()
        if disconnectResult == kIOReturnSuccess {
            logger.info("Closed stale connection before recovery for \(peripheral.displayName)")
        }

        waitForBluetoothStatePropagation()

        if let rediscoveredDevice = discoverDeviceForPairing(peripheral) {
            let reconnectResult = rediscoveredDevice.openConnection()
            if isSuccessfulConnectionResult(reconnectResult, device: rediscoveredDevice) {
                logger.info("Recovered connection for \(peripheral.displayName) after rediscovery")
                return successResult("\(peripheral.displayName) connected")
            }

            logger.error("Rediscovered connect failed for \(peripheral.displayName): \(reconnectResult)")
        } else {
            logger.error("Recovery rediscovery failed for \(peripheral.displayName)")
        }

        return failureResult(
            "Failed to connect \(peripheral.displayName) (\(initialResult)). If it is still attached to another Mac, disconnect it there first. Power-cycling the device should only be a last resort."
        )
    }

    private func preferredDeviceReference(
        for peripheral: BluetoothPeripheral,
        fallback: IOBluetoothDevice
    ) -> IOBluetoothDevice {
        if let discoveredDevice = discoverDeviceForPairing(peripheral) {
            return discoveredDevice
        }

        return fallback
    }

    private func pairAndConnectPeripheral(
        _ peripheral: BluetoothPeripheral,
        device: IOBluetoothDevice
    ) -> BluetoothOperationResult {
        guard let devicePair = IOBluetoothDevicePair(device: device) else {
            logger.error("Failed to initialize pairing for \(peripheral.displayName)")
            return failureResult("Failed to initialize pairing for \(peripheral.displayName)")
        }

        let observer = BluetoothPairingObserver(deviceName: peripheral.displayName, logger: logger)
        devicePair.delegate = observer

        let pairResult = devicePair.start()
        guard pairResult == kIOReturnSuccess else {
            logger.error("Failed to start pairing for \(peripheral.displayName): \(pairResult)")
            return failureResult(
                "Could not start pairing for \(peripheral.displayName). Turn the device off and on so it enters pairing mode, then click Connect again."
            )
        }

        let paired = waitUntil(timeout: pairingTimeout) {
            observer.didFinish || device.isPaired()
        }

        guard paired else {
            logger.error("Pairing timed out for \(peripheral.displayName)")
            if let promptMessage = observer.promptMessage {
                return failureResult(promptMessage)
            }
            return failureResult(
                "Pairing timed out for \(peripheral.displayName). Turn the device off and on and try Connect again."
            )
        }

        if observer.error != kIOReturnSuccess && device.isPaired() == false {
            logger.error("Pairing failed for \(peripheral.displayName): \(observer.error)")
            if observer.error == kBluetoothHCIErrorHostTimeout {
                return failureResult(
                    "Pairing with \(peripheral.displayName) timed out at the Bluetooth host. Turn the device off and on, wait for it to become discoverable, then click Connect again."
                )
            }

            if let promptMessage = observer.promptMessage {
                return failureResult(promptMessage)
            }

            return failureResult("Pairing failed for \(peripheral.displayName) (\(observer.error))")
        }

        let connectResult = device.openConnection()
        if isSuccessfulConnectionResult(connectResult, device: device) {
            logger.info("Paired and connected \(peripheral.displayName)")
            return successResult("\(peripheral.displayName) paired and connected")
        }

        logger.error("Pairing succeeded but connect failed for \(peripheral.displayName): \(connectResult)")
        return failureResult(
            "\(peripheral.displayName) paired, but connection did not complete. Toggle the device power once and click Connect again."
        )
    }

    private func discoverDeviceForPairing(_ peripheral: BluetoothPeripheral) -> IOBluetoothDevice? {
        let observer = BluetoothInquiryObserver(targetPeripheral: peripheral, logger: logger)
        guard let inquiry = IOBluetoothDeviceInquiry(delegate: observer) else {
            logger.error("Failed to create inquiry for \(peripheral.displayName)")
            return nil
        }

        inquiry.inquiryLength = 6
        inquiry.updateNewDeviceNames = true

        let startResult = inquiry.start()
        guard startResult == kIOReturnSuccess else {
            logger.error("Failed to start inquiry for \(peripheral.displayName): \(startResult)")
            return nil
        }

        _ = waitUntil(timeout: inquiryTimeout) {
            observer.didComplete
        }

        _ = inquiry.stop()

        if let matchedDevice = observer.bestMatch() {
            logger.info("Matched inquiry device for \(peripheral.displayName)")
            return matchedDevice
        }

        logger.error("No discoverable device match found for \(peripheral.displayName)")
        return nil
    }

    private func removePairing(for peripheral: BluetoothPeripheral, device: IOBluetoothDevice) -> Bool {
        let selector = Selector(("remove"))
        guard device.responds(to: selector) else {
            logger.error("Device does not respond to remove selector: \(peripheral.displayName)")
            return false
        }

        _ = device.perform(selector)
        logger.info("Removed pairing for \(peripheral.displayName)")
        return true
    }

    private func waitForBluetoothStatePropagation() {
        let until = Date().addingTimeInterval(recoveryDelay)
        while Date() < until {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(pollingInterval))
        }
    }

    @discardableResult
    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }

            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(pollingInterval))
        }

        return condition()
    }

    private func successResult(_ message: String) -> BluetoothOperationResult {
        BluetoothOperationResult(success: true, message: message)
    }

    private func failureResult(_ message: String) -> BluetoothOperationResult {
        BluetoothOperationResult(success: false, message: message)
    }
}
