import SwiftUI

struct PeerSettingsView: View {
    @ObservedObject var serviceBrowser: ServiceBrowser
    let connectionManager: ConnectionManager
    @State private var healthResults: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Discovered peer Macs on the local network.")
                .font(.callout)
                .foregroundColor(.secondary)

            List {
                if serviceBrowser.peers.isEmpty {
                    Text("No peers discovered. Make sure MagicSwitch2 is running on another Mac on the same network.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(serviceBrowser.peers) { peer in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(peer.displayName)
                                    .fontWeight(.medium)
                                Text(String(describing: peer.endpoint))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if let result = healthResults[peer.id] {
                                Text(result)
                                    .font(.caption)
                                    .foregroundColor(result == "OK" ? .green : .red)
                            }

                            Button("Health Check") {
                                checkHealth(peer: peer)
                            }
                            .buttonStyle(.glass)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            HStack {
                Spacer()
                Text("\(serviceBrowser.peers.count) peer(s) found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    private func checkHealth(peer: NetworkPeer) {
        healthResults[peer.id] = "Checking..."
        connectionManager.send(command: .healthCheck, to: peer.endpoint) { response in
            DispatchQueue.main.async {
                healthResults[peer.id] = response == .opSuccess ? "OK" : "Failed"
            }
        }
    }
}
