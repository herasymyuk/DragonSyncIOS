//
//  SerialConsoleViewModel.swift
//  WarDragon
//
//  Created by Luke on 2/18/25.
//

import Foundation
import Network

class SerialConsoleViewModel: ObservableObject {
    @Published var messages: [SerialConsoleView.SerialMessage] = []
    private var multicastConnection: NWConnection?
    private var zmqHandler: ZMQHandler?
    private var cotListener: NWListener?
    private let listenerQueue = DispatchQueue(label: "com.wardragon.serial")
    let mcPort = Settings.shared.serialConsoleMulticastPort
    let zmqPort = Settings.shared.serialConsoleZMQPort
    private var isSubscribed = false
    
    struct SerialData: Codable {
        let type: String
        let timestamp: String
        let data: String
    }
    
    // Notification name for serial messages
    static let serialMessageNotification = Notification.Name("SerialMessageReceived")
    
    // Subscribe to messages from the main connection
    func startListening() {
        if isSubscribed {
            return
        }
        
        // Subscribe to notifications for serial messages
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSerialMessageNotification),
            name: Self.serialMessageNotification,
            object: nil
        )
        
        isSubscribed = true
    }
    
    func startListening(port: UInt16) {
        stopListening() // Cleanup
        if Settings.shared.connectionMode == .multicast {
            startMulticastListening()
        } else {
            startZMQListening(port: UInt16(zmqPort))
        }
    }
    
    private func startMulticastListening() {
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        parameters.prohibitedInterfaceTypes = [.cellular]
        parameters.requiredInterfaceType = .wifi
        
        do {
            // Create the port
            let port = NWEndpoint.Port(integerLiteral: UInt16(mcPort))
            
            // Create listener with the specific port
            cotListener = try NWListener(using: parameters, on: port)
            
            cotListener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("Multicast listener ready on port \(port)")
                case .failed(let error):
                    print("Multicast listener failed: \(error)")
                    // Potentially implement reconnection logic
                    self?.handleListenerFailure(error)
                case .cancelled:
                    print("Multicast listener cancelled")
                default:
                    break
                }
            }
            
            cotListener?.newConnectionHandler = { [weak self] connection in
                print("New connection received")
                connection.start(queue: self?.listenerQueue ?? .main)
                self?.receiveMessages(from: connection)
            }
            
            // Start the listener
            cotListener?.start(queue: listenerQueue)
            
        } catch {
            print("Failed to create multicast listener: \(error)")
        }
    }

    private func handleListenerFailure(_ error: Error) {
        print("Listener encountered a critical error: \(error)")
        
        // Optional: Attempt to restart after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.startListening(port: UInt16(self?.mcPort ?? 6970))
        }
    }

    
    private func startZMQListening(port: UInt16) {
        zmqHandler = ZMQHandler()
        zmqHandler?.connect(
            host: Settings.shared.zmqHost,
            zmqTelemetryPort: port,
            zmqStatusPort: port,
            onTelemetry: { [weak self] message in
                self?.handleSerialMessage(message)
            },
            onStatus: { [weak self] message in
                self?.handleSerialMessage(message)
            }
        )
    }
    
    private func receiveMessages(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            defer {
                if !isComplete {
                    self.receiveMessages(from: connection)
                } else {
                    connection.cancel()
                }
            }
            
            if let error = error {
                print("Error receiving data: \(error.localizedDescription)")
                return
            }
            
            guard let data = data, !data.isEmpty, let message = String(data: data, encoding: .utf8) else {
                print("No valid data received.")
                return
            }
            
            DispatchQueue.main.async {
                if let jsonData = message.data(using: .utf8),
                   let serialData = try? JSONDecoder().decode(SerialData.self, from: jsonData) {
                    self.messages.append(
                        SerialConsoleView.SerialMessage(
                            timestamp: Date(),
                            content: serialData.data,
                            type: .output
                        )
                    )
                } else {
                    let trimmedContent = message.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedContent.isEmpty {
                        self.messages.append(
                            SerialConsoleView.SerialMessage(
                                timestamp: Date(),
                                content: trimmedContent,
                                type: .output
                            )
                        )
                    }
                }
            }
        }
    }


    private func processMessage(_ string: String) {
        if let jsonData = string.data(using: .utf8),
           let serialData = try? JSONDecoder().decode(SerialData.self, from: jsonData) {
            messages.append(SerialConsoleView.SerialMessage(
                timestamp: Date(),
                content: serialData.data,
                type: .output
            ))
        } else {
            let trimmedContent = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedContent.isEmpty {
                messages.append(SerialConsoleView.SerialMessage(
                    timestamp: Date(),
                    content: trimmedContent,
                    type: .output
                ))
            }
        }
        print("Debug: Message count: \(messages.count)")
    }


    
    private func handleSerialMessage(_ message: String) {
        DispatchQueue.main.async {
            if let data = message.data(using: .utf8),
               let serialData = try? JSONDecoder().decode(SerialData.self, from: data) {
                self.messages.append(
                    SerialConsoleView.SerialMessage(
                        timestamp: Date(),
                        content: serialData.data,
                        type: .output
                    )
                )
            } else {
                // Fallback to raw text if JSON decoding fails
                let trimmedContent = message.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedContent.isEmpty {
                    self.messages.append(
                        SerialConsoleView.SerialMessage(
                            timestamp: Date(),
                            content: trimmedContent,
                            type: .output
                        )
                    )
                }
            }
        }
    }
    
    @objc private func handleSerialMessageNotification(_ notification: Notification) {
        guard let message = notification.object as? String else { return }
        processSerialMessage(message)
    }
    
    private func processSerialMessage(_ message: String) {
        DispatchQueue.main.async {
            if let data = message.data(using: .utf8),
               let serialData = try? JSONDecoder().decode(SerialData.self, from: data) {
                self.messages.append(
                    SerialConsoleView.SerialMessage(
                        timestamp: Date(),
                        content: serialData.data,
                        type: .output
                    )
                )
            } else {
                let trimmedContent = message.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedContent.isEmpty {
                    self.messages.append(
                        SerialConsoleView.SerialMessage(
                            timestamp: Date(),
                            content: trimmedContent,
                            type: .output
                        )
                    )
                }
            }
        }
    }

    
    func stopListening() {
        cotListener?.cancel()
        cotListener = nil
        zmqHandler?.disconnect()
        zmqHandler = nil
        NotificationCenter.default.removeObserver(self, name: Self.serialMessageNotification, object: nil)
        isSubscribed = false
    }
}
