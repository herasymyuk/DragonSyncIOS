//
//  SettingsView.swift
//  WarDragon
//
//  Created by Luke on 11/23/24.
//

import SwiftUI
import Network
import UIKit

struct SettingsView: View {
    @ObservedObject var zmqHandler: ZMQHandler
    @StateObject private var settings = Settings.shared
    
    var body: some View {
        Form {
            Section("Connection") {
                HStack {
                    Image(systemName: connectionStatusSymbol)
                        .foregroundStyle(connectionStatusColor)
                        .symbolEffect(.bounce, options: .repeat(3), value: zmqHandler.isConnected)
                    Text(connectionStatusText)
                        .foregroundStyle(connectionStatusColor)
                }
                
                Picker("Mode", selection: .init(
                    get: { settings.connectionMode },
                    set: { settings.updateConnection(mode: $0) }
                )) {
                    ForEach(ConnectionMode.allCases, id: \.self) { mode in
                        HStack {
                            Image(systemName: mode.icon)
                            Text(mode.rawValue)
                        }
                        .tag(mode)
                    }
                }
                
                if settings.connectionMode != .multicast {
                    TextField("ZMQ Host", text: .init(
                        get: { settings.zmqHost },
                        set: { settings.updateConnection(mode: settings.connectionMode, host: $0) }
                    ))
                    .textContentType(.URL)
                    .autocapitalization(.none)
                }
                
                Toggle("Active", isOn: .init(
                    get: { settings.isListening },
                    set: { settings.toggleListening($0) }
                ))
            }
            
            Section("Preferences") {
                Toggle("Enable Notifications", isOn: .init(
                    get: { settings.notificationsEnabled },
                    set: { settings.updatePreferences(notifications: $0, screenOn: settings.keepScreenOn) }
                ))
                
                Toggle("Keep Screen On", isOn: .init(
                    get: { settings.keepScreenOn },
                    set: { settings.updatePreferences(notifications: settings.notificationsEnabled, screenOn: $0) }
                ))
            }
            
            Section("Ports") {
                HStack {
                    Text("Messages")
                    Spacer()
                    Text(verbatim: String(settings.telemetryPort))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                HStack {
                    Text("Status")
                    Spacer()
                    Text(verbatim: String(settings.statusPort))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                        .foregroundStyle(.secondary)
                }
                
                Link(destination: URL(string: "https://github.com/lukeswitz/DragonLink")!) {
                    HStack {
                        Text("Source Code")
                        Spacer()
                        Image(systemName: "arrow.up.right.circle")
                    }
                }
            }
        }
        .navigationTitle("Settings")
    }
    
    private var connectionStatusSymbol: String {
        if zmqHandler.isConnected {
            switch settings.connectionMode {
            case .multicast:
                return "antenna.radiowaves.left.and.right.circle.fill"
            case .zmq:
                return "network.badge.shield.half.filled"
            case .both:
                return "network.slash.circle.fill"
            }
        } else {
            return "bolt.horizontal.circle"
        }
    }
    
    private var connectionStatusColor: Color {
        if settings.isListening {
            return .green  // Always green when listening
        } else {
            return .red
        }
    }
    
    private var connectionStatusText: String {
        if settings.isListening {
            if zmqHandler.isConnected {
                return "Connected"
            } else {
                return "Listening..."  // Changed from "Waiting for data..."
            }
        } else {
            return "Disconnected"
        }
    }
}
