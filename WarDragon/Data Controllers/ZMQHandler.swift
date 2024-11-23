//
//  ZMQHandler.swift
//  WarDragon
//
//  Created by Luke on 11/23/24.
//

import Foundation
import Network

class ZMQHandler: ObservableObject {
    @Published var isConnected = false
    @Published var lastMessageReceived = Date()
    private var telemetryConnection: NWConnection?
    private var statusConnection: NWConnection?
    private var multicastConnection: NWConnection?
    private let queue = DispatchQueue(label: "com.wardragon.zmq")
    private var connectionTimer: Timer?
    private let connectionTimeout: TimeInterval = 5
    
    func connect(mode: ConnectionMode, host: String, telemetryPort: UInt16 = 4224, statusPort: UInt16 = 4225) {
        disconnect()
        setupConnectionMonitor()
        
        switch mode {
        case .multicast:
            setupMulticast(telemetryPort: 6969, statusPort: statusPort)
        case .zmq:
            setupZMQConnection(host: host, telemetryPort: telemetryPort, statusPort: statusPort)
        case .both:
            setupMulticast(telemetryPort: 6969, statusPort: statusPort)
            setupZMQConnection(host: host, telemetryPort: telemetryPort, statusPort: statusPort)
        }
    }
    
    private func setupZMQConnection(host: String, telemetryPort: UInt16, statusPort: UInt16) {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        
        if let tcpOptions = params.defaultProtocolStack.internetProtocol as? NWProtocolTCP.Options {
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveIdle = 5
            tcpOptions.connectionTimeout = 5
        }
        
        let telemetryEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: telemetryPort)
        )
        let statusEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: statusPort)
        )
        
        telemetryConnection = NWConnection(to: telemetryEndpoint, using: params)
        statusConnection = NWConnection(to: statusEndpoint, using: params)
        
        setupConnection(telemetryConnection, type: "ZMQ Telemetry")
        setupConnection(statusConnection, type: "ZMQ Status")
    }
    
    private func setupMulticast(telemetryPort: UInt16, statusPort: UInt16) {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        params.requiredInterfaceType = .wifi
        
        let multicastGroup = NWEndpoint.hostPort(
            host: NWEndpoint.Host("224.0.0.1"),
            port: NWEndpoint.Port(integerLiteral: telemetryPort)
        )
        
        multicastConnection = NWConnection(to: multicastGroup, using: params)
        setupConnection(multicastConnection, type: "Multicast")
    }
    
    private func setupConnection(_ connection: NWConnection?, type: String) {
        connection?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    print("\(type) Connection established")
                    self.isConnected = true
                case .waiting(let error):
                    print("\(type) Connection waiting: \(error)")
                    if error != .posix(.ECANCELED) {
                        self.handleConnectionWaiting(connection, type: type)
                    }
                case .failed(let error):
                    print("\(type) Connection failed: \(error)")
                    self.handleConnectionFailure(connection, type: type)
                case .preparing:
                    print("\(type) Connection preparing")
                case .cancelled:
                    print("\(type) Connection cancelled")
                    self.isConnected = false
                default:
                    break
                }
            }
        }
        
        connection?.start(queue: queue)
    }
    
    private func setupConnectionMonitor() {
        connectionTimer?.invalidate()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let timeSinceLastMessage = Date().timeIntervalSince(self.lastMessageReceived)
            DispatchQueue.main.async {
                self.isConnected = timeSinceLastMessage < self.connectionTimeout
            }
        }
    }
    
    private func handleConnectionWaiting(_ connection: NWConnection?, type: String) {
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if case .waiting = connection?.state {
                print("Retrying \(type) connection...")
                connection?.restart()
            }
        }
    }
    
    private func handleConnectionFailure(_ connection: NWConnection?, type: String) {
        connection?.cancel()
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
        }
    }
    
    func startReceiving(
        onTelemetryMessage: @escaping (String) -> Void,
        onStatusMessage: @escaping (String) -> Void
    ) {
        receiveMessages(from: multicastConnection) { message in
            onTelemetryMessage(message)
        }
        
        receiveMessages(from: telemetryConnection) { message in
            onTelemetryMessage(message)
        }
        
        receiveMessages(from: statusConnection) { message in
            onStatusMessage(message)
        }
    }
    
    private func receiveMessages(from connection: NWConnection?, completion: @escaping (String) -> Void) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            if let error = error {
                print("Receive error: \(error)")
                return
            }
            
            if let data = content, let message = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.lastMessageReceived = Date()
                    completion(message)
                }
            }
            
            if !isComplete {
                self?.receiveMessages(from: connection, completion: completion)
            }
        }
    }
    
    func disconnect() {
        connectionTimer?.invalidate()
        connectionTimer = nil
        multicastConnection?.cancel()
        telemetryConnection?.cancel()
        statusConnection?.cancel()
        multicastConnection = nil
        telemetryConnection = nil
        statusConnection = nil
        isConnected = false
    }
    
    deinit {
        connectionTimer?.invalidate()
        disconnect()
    }
}
