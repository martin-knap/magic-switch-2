import Foundation
import Network
import os

enum Command: String {
    case healthCheck = "HEALTH_CHECK"
    case connectAll = "CONNECT_ALL"
    case unregisterAll = "UNREGISTER_ALL"
}

enum Response: String {
    case opSuccess = "OP_SUCCESS"
    case opFailed = "OP_FAILED"
}

final class ConnectionManager: ObservableObject, @unchecked Sendable {
    private enum ConnectionError: Error {
        case invalidUTF8
        case connectionClosed
    }

    private let logger = Logger(subsystem: "com.magicswitch2", category: "ConnectionManager")

    var onCommandReceived: ((Command, @escaping (Response) -> Void) -> Void)?

    // MARK: - Send command to peer

    func send(command: Command, to endpoint: NWEndpoint, completion: @escaping @Sendable (Response?) -> Void) {
        let connection: NWConnection

        // If it's a service endpoint from Bonjour, connect directly to it
        connection = NWConnection(to: endpoint, using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.logger.info("Connected to peer, sending \(command.rawValue)")
                self.sendData(command.rawValue, on: connection) { [weak self] in
                    self?.receiveResponse(on: connection, completion: completion)
                }
            case .failed(let error):
                self.logger.error("Connection failed: \(error)")
                completion(nil)
                connection.cancel()
            default:
                break
            }
        }

        connection.start(queue: .main)
    }

    // MARK: - Handle incoming connection

    func handleIncomingConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveCommand(on: connection)
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    // MARK: - Private helpers

    private func sendData(_ string: String, on connection: NWConnection, completion: @escaping @Sendable () -> Void) {
        let data = Data((string + "\n").utf8)
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.logger.error("Send error: \(error)")
            }
            completion()
        })
    }

    private func receiveResponse(on connection: NWConnection, completion: @escaping @Sendable (Response?) -> Void) {
        receiveLine(on: connection) { [weak self] result in
            defer { connection.cancel() }

            guard case .success(let message) = result,
                  let response = Response(rawValue: message) else {
                if case .failure(let error) = result {
                    self?.logger.error("Receive error: \(error)")
                }
                completion(nil)
                return
            }

            completion(response)
        }
    }

    private func receiveCommand(on connection: NWConnection) {
        receiveLine(on: connection) { [weak self] result in
            guard let self else {
                connection.cancel()
                return
            }

            guard case .success(let message) = result,
                  let command = Command(rawValue: message) else {
                if case .failure(let error) = result {
                    self.logger.error("Receive error: \(error)")
                }
                connection.cancel()
                return
            }

            self.logger.info("Received command: \(command.rawValue)")

            self.onCommandReceived?(command) { [weak self] response in
                self?.sendData(response.rawValue, on: connection) {
                    connection.cancel()
                }
            }
        }
    }

    private func receiveLine(on connection: NWConnection, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        var buffer = Data()

        func readNextChunk() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, isComplete, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                if let data, !data.isEmpty {
                    buffer.append(data)
                    if let line = self.extractLine(from: &buffer) {
                        completion(.success(line))
                        return
                    }
                }

                if isComplete {
                    if let line = self.extractLine(from: &buffer) {
                        completion(.success(line))
                    } else if !buffer.isEmpty {
                        guard let message = String(data: buffer, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                            !message.isEmpty else {
                            completion(.failure(ConnectionError.invalidUTF8))
                            return
                        }
                        completion(.success(message))
                    } else {
                        completion(.failure(ConnectionError.connectionClosed))
                    }
                    return
                }

                readNextChunk()
            }
        }

        readNextChunk()
    }

    private func extractLine(from buffer: inout Data) -> String? {
        guard let newlineIndex = buffer.firstIndex(of: 0x0A) else {
            return nil
        }

        let lineData = buffer.prefix(upTo: newlineIndex)
        buffer.removeSubrange(...newlineIndex)

        guard let line = String(data: lineData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !line.isEmpty else {
            return nil
        }

        return line
    }
}
