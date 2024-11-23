//
//  Settings.swift
//  WarDragon
//
//  Created by Luke on 11/23/24.
//

import Foundation
import SwiftUI

enum ConnectionMode: String, Codable, CaseIterable {
    case multicast = "Multicast"
    case zmq = "Direct ZMQ"
    case both = "Both"
    
    var icon: String {
        switch self {
        case .multicast:
            return "antenna.radiowaves.left.and.right"
        case .zmq:
            return "network"
        case .both:
            return "network.badge.shield.half.filled"
        }
    }
}

class Settings: ObservableObject {
    static let shared = Settings()
    
    @AppStorage("connectionMode") private(set) var connectionMode: ConnectionMode = .multicast
    @AppStorage("zmqHost") private(set) var zmqHost: String = "localhost"
    @AppStorage("notificationsEnabled") private(set) var notificationsEnabled = true
    @AppStorage("keepScreenOn") private(set) var keepScreenOn = true
    @AppStorage("isListening") private(set) var isListening = false
    
    private init() {}
    
    // Dynamic ports based on the mode
    var telemetryPort: Int {
        connectionMode == .multicast ? 6969 : 4224
    }
    
    var statusPort: Int {
        connectionMode == .multicast ? 4225 : 4225
    }
    
    func updateConnection(mode: ConnectionMode, host: String? = nil) {
        if let host = host {
            zmqHost = host
        }
        connectionMode = mode
        objectWillChange.send()
    }
    
    func toggleListening(_ active: Bool) {
        isListening = active
        objectWillChange.send()
    }
    
    func updatePreferences(notifications: Bool, screenOn: Bool) {
        notificationsEnabled = notifications
        keepScreenOn = screenOn
        UIApplication.shared.isIdleTimerDisabled = screenOn
        objectWillChange.send()
    }
}
