import Foundation
import Network
import os

final class ServiceBrowser: ObservableObject, @unchecked Sendable {
    @Published var peers: [NetworkPeer] = []

    private var browser: NWBrowser?
    private let logger = Logger(subsystem: "com.magicswitch2", category: "ServiceBrowser")

    func start() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: ServicePublisher.serviceType, domain: nil), using: parameters)

        browser?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.logger.info("Browser ready")
            case .failed(let error):
                self.logger.error("Browser failed: \(error)")
                self.browser?.cancel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    self.start()
                }
            default:
                break
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            self.updatePeers(from: results)
        }

        browser?.start(queue: .main)
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    private func updatePeers(from results: Set<NWBrowser.Result>) {
        let localHostName = Host.current().localizedName ?? ""

        peers = results.compactMap { result in
            // Extract service name from the result
            guard case .service(let name, let type, let domain, _) = result.endpoint else {
                return nil
            }

            // Skip self
            if name == localHostName {
                return nil
            }

            return NetworkPeer(
                id: "\(name).\(type)\(domain)",
                name: name,
                endpoint: result.endpoint,
                isOnline: true
            )
        }
    }
}
