//
//  CoTViewModel.swift
//  WarDragon
//
//  Created by Luke on 11/18/24.
//

import Foundation
import Network
import UserNotifications
import CoreLocation

class CoTViewModel: ObservableObject {
    @Published var parsedMessages: [CoTMessage] = []
    private var cotListener: NWListener?
    private var statusListener: NWListener?
    private let cotPort: UInt16 = 6969
    private let statusPort: UInt16 = 4225
    private let listenerQueue = DispatchQueue(label: "CoTListenerQueue")
    private var statusViewModel = StatusViewModel()

    struct CoTMessage: Identifiable, Equatable {
        var id: String { uid }
        var uid: String
        var type: String
        var lat: String
        var lon: String
        var speed: String
        var vspeed: String
        var alt: String
        var height: String
        var pilotLat: String
        var pilotLon: String
        var description: String
        
        var coordinate: CLLocationCoordinate2D? {
            guard let latDouble = Double(lat),
                  let lonDouble = Double(lon) else {
                print("Failed to convert lat: \(lat) or lon: \(lon) to Double")
                return nil
            }
            return CLLocationCoordinate2D(latitude: latDouble, longitude: lonDouble)
        }
    }

    init(statusViewModel: StatusViewModel) {
        self.statusViewModel = statusViewModel
        self.checkPermissions()
    }
    
    private func checkPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            if settings.authorizationStatus != .authorized {
                self?.requestNotificationPermission()
            }
        }
        
        let listener = try? NWListener(using: .udp)
        if listener == nil {
            requestLocalNetworkPermission()
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            print("Notification permission granted: \(granted)")
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    private func requestLocalNetworkPermission() {
        let listener = try? NWListener(using: .udp)
        listener?.start(queue: .main)
        listener?.cancel()
    }

    func startListening() {
        stopListening()

        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        parameters.prohibitedInterfaceTypes = [.cellular]
        parameters.requiredInterfaceType = .wifi

        // Start both listeners
        [cotPort, statusPort].forEach { port in
            if let nwPort = NWEndpoint.Port(rawValue: port) {
                do {
                    let listener = try NWListener(using: parameters, on: nwPort)
                    if port == cotPort {
                        self.cotListener = listener
                    } else {
                        self.statusListener = listener
                    }
                    setupListener(listener, port: port)
                } catch let error {
                    print("Failed to create listener on port \(port): \(error.localizedDescription)")
                }
            }
        }
    }

    private func setupListener(_ listener: NWListener?, port: UInt16) {
        listener?.stateUpdateHandler = { state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    print("Listener ready on port \(port)")
                case .failed(let error):
                    print("Listener failed on port \(port) with error: \(error.localizedDescription)")
                case .cancelled:
                    print("Listener cancelled on port \(port)")
                default:
                    break
                }
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.listenerQueue ?? .main)
            
            // Determine the type based on the port
            let type = (port == self?.cotPort) ? "CoT" : "Status"
            self?.receiveMessages(from: connection, type: type)
        }

        listener?.start(queue: self.listenerQueue)
    }


    private func receiveMessages(from connection: NWConnection, type: String) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("Error receiving data: \(error.localizedDescription)")
                    self.receiveMessages(from: connection, type: type)
                    return
                }

                if let data = data, !data.isEmpty {
                    if let message = String(data: data, encoding: .utf8) {
                        print("Received data: \(message)")
                        
                        if type == "Status" {
                            self.statusViewModel.handleStatusMessage(message)
                        } else {
                            // Check if it's XML first
                            if message.trimmingCharacters(in: .whitespacesAndNewlines).starts(with: "<") {
                                let parser = XMLParser(data: data)
                                let cotParserDelegate = CoTMessageParser()
                                parser.delegate = cotParserDelegate
                                
                                if parser.parse(), let parsedMessage = cotParserDelegate.cotMessage {
                                    DispatchQueue.main.async {
                                        self.parsedMessages.append(parsedMessage)
                                        self.sendNotification(for: parsedMessage)
                                    }
                                }
                            } else {
                                // Try JSON parsing if it's not XML
                                do {
                                    if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                                        for jsonData in jsonArray {
                                            if jsonData["Basic ID"] != nil {
                                                let parser = CoTMessageParser()
                                                if let parsedMessage = parser.parseESP32Message(jsonData) {
                                                    DispatchQueue.main.async {
                                                        self.parsedMessages.append(parsedMessage)
                                                        self.sendNotification(for: parsedMessage)
                                                    }
                                                }
                                            }
                                        }
                                    } else if let jsonData = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                        if jsonData["Basic ID"] != nil {
                                            let parser = CoTMessageParser()
                                            if let parsedMessage = parser.parseESP32Message(jsonData) {
                                                DispatchQueue.main.async {
                                                    self.parsedMessages.append(parsedMessage)
                                                    self.sendNotification(for: parsedMessage)
                                                }
                                            }
                                        }
                                    }
                                } catch {
                                    print("JSON Parsing error: \(error)")
                                }
                              }
                        }
                    }
                }
                
                if !isComplete {
                    self.receiveMessages(from: connection, type: type)
                } else {
                    connection.cancel()
                }
            }
        }

    private func sendNotification(for message: CoTViewModel.CoTMessage) {
        let content = UNMutableNotificationContent()
        content.title = "New CoT Message"
        content.body = "From: \(message.uid)\nType: \(message.type)\nLocation: \(message.lat), \(message.lon)"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    func handleZMQMessage(_ message: String) {
            guard let data = message.data(using: .utf8) else { return }
            
            // Check if it's XML first (CoT format)
            if message.trimmingCharacters(in: .whitespacesAndNewlines).starts(with: "<") {
                let parser = XMLParser(data: data)
                let cotParserDelegate = CoTMessageParser()
                parser.delegate = cotParserDelegate
                
                if parser.parse(), let parsedMessage = cotParserDelegate.cotMessage {
                    DispatchQueue.main.async {
                        self.parsedMessages.append(parsedMessage)
                        self.sendNotification(for: parsedMessage)
                    }
                }
            } else {
                // Try JSON parsing (ESP32 format)
                do {
                    if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                        for jsonData in jsonArray {
                            if jsonData["Basic ID"] != nil {
                                let parser = CoTMessageParser()
                                if let parsedMessage = parser.parseESP32Message(jsonData) {
                                    DispatchQueue.main.async {
                                        self.parsedMessages.append(parsedMessage)
                                        self.sendNotification(for: parsedMessage)
                                    }
                                }
                            }
                        }
                    } else if let jsonData = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if jsonData["Basic ID"] != nil {
                            let parser = CoTMessageParser()
                            if let parsedMessage = parser.parseESP32Message(jsonData) {
                                DispatchQueue.main.async {
                                    self.parsedMessages.append(parsedMessage)
                                    self.sendNotification(for: parsedMessage)
                                }
                            }
                        }
                    }
                } catch {
                    print("JSON Parsing error: \(error)")
                }
            }
        }

    func stopListening() {
        cotListener?.cancel()
        statusListener?.cancel()
        cotListener = nil
        statusListener = nil
    }

    func resetListener() {
        stopListening()
        parsedMessages.removeAll()
        startListening()
    }
}
