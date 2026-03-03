import Foundation
import Network
import os

final class ServicePublisher: ObservableObject, @unchecked Sendable {
    private var listener: NWListener?
    private let logger = Logger(subsystem: "com.magicswitch2", category: "ServicePublisher")

    static let serviceType = "_magicswitch2._tcp"
    @Published var port: UInt16 = 0

    var onConnectionReceived: ((NWConnection) -> Void)?

    func start() {
        do {
            let parameters = NWParameters.tcp
            listener = try NWListener(using: parameters)
            listener?.service = NWListener.Service(type: ServicePublisher.serviceType)

            listener?.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    if let port = self.listener?.port?.rawValue {
                        self.port = port
                        self.logger.info("Listener ready on port \(port)")
                    }
                case .failed(let error):
                    self.logger.error("Listener failed: \(error)")
                    self.listener?.cancel()
                    // Retry after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        self.start()
                    }
                default:
                    break
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.logger.info("New connection from \(String(describing: connection.endpoint))")
                self?.onConnectionReceived?(connection)
            }

            listener?.start(queue: .main)
        } catch {
            logger.error("Failed to create listener: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}
