import Foundation
import IOBluetooth

struct BluetoothPeripheral: Identifiable, Codable, Hashable {
    let id: String // MAC address (e.g. "AA-BB-CC-DD-EE-FF")
    let name: String

    var isConnected: Bool {
        guard let device = IOBluetoothDevice(addressString: id) else { return false }
        return device.isConnected()
    }

    var isPaired: Bool {
        guard let device = IOBluetoothDevice(addressString: id) else { return false }
        return device.isPaired()
    }

    var displayName: String {
        name.isEmpty ? id : name
    }

    var systemImageName: String {
        let lowercasedName = displayName.lowercased()

        if lowercasedName.contains("keyboard") {
            return "keyboard"
        }

        if lowercasedName.contains("trackpad") {
            return "rectangle.and.hand.point.up.left.filled"
        }

        if lowercasedName.contains("mouse") {
            return "computermouse"
        }

        return "dot.radiowaves.left.and.right"
    }
}
