import Foundation
import IOBluetooth

struct BluetoothPeripheral: Identifiable, Codable, Hashable {
    let id: String // MAC address (e.g. "AA-BB-CC-DD-EE-FF")
    let name: String

    var isConnected: Bool {
        guard let device = IOBluetoothDevice(addressString: id) else { return false }
        return device.isConnected()
    }

    var displayName: String {
        name.isEmpty ? id : name
    }
}
