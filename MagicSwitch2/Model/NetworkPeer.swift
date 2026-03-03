import Foundation
import Network

struct NetworkPeer: Identifiable, Hashable {
    let id: String // hostname
    let name: String
    let endpoint: NWEndpoint
    var isOnline: Bool = false

    var displayName: String {
        name.isEmpty ? id : name
    }
}
