//
//  ContentView.swift
//  WarDragon
//
//  Created by Luke on 11/18/24.
//

import SwiftUI
import Network
import UserNotifications

struct ContentView: View {
    @StateObject private var statusViewModel = StatusViewModel()
    @StateObject private var spectrumViewModel = SpectrumData.SpectrumViewModel()
    @StateObject private var serialViewModel = SerialConsoleViewModel()
    @StateObject private var cotViewModel: CoTViewModel
    @StateObject private var settings = Settings.shared
    @State private var showAlert = false
    @State private var latestMessage: CoTViewModel.CoTMessage?
    @State private var selectedTab: Int
    
    
    init() {
        let statusVM = StatusViewModel()
        _statusViewModel = StateObject(wrappedValue: statusVM)
        _cotViewModel = StateObject(wrappedValue: CoTViewModel(statusViewModel: statusVM))
        _selectedTab = State(initialValue: Settings.shared.isListening ? 0 : 3)
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView(
                    statusViewModel: statusViewModel,
                    cotViewModel: cotViewModel,
                    spectrumViewModel: spectrumViewModel
                )
                .navigationTitle("Dashboard")
            }
            .tabItem {
                Label("Dashboard", systemImage: "gauge")
            }
            .tag(0)
            
            NavigationStack {
                VStack {
                    ScrollViewReader { proxy in
                        List(cotViewModel.parsedMessages) { item in
                            MessageRow(message: item, cotViewModel: cotViewModel)
                        }
                        .listStyle(.inset)
                        .onChange(of: cotViewModel.parsedMessages) { oldMessages, newMessages in
                            // Only proceed if we have more messages than before
                            if oldMessages.count < newMessages.count {
                                // Get the newest message
                                if let latest = newMessages.last {
                                    // Check if this message ID wasn't in the old messages
                                    if !oldMessages.contains(where: { $0.id == latest.id }) {
                                        latestMessage = latest
                                        showAlert = false
                                        withAnimation {
                                            proxy.scrollTo(latest.id, anchor: .bottom)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle("DragonSync")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {
                            cotViewModel.parsedMessages.removeAll()  // Remove UI messages
                            cotViewModel.droneSignatures.removeAll() // Ditch old signatures BUGFIX #
                            cotViewModel.macIdHistory.removeAll()
                            cotViewModel.macProcessing.removeAll()
                        }) {
                            Image(systemName: "trash")
                        }
                    }
                }
                .alert("New Message", isPresented: $showAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    if let message = latestMessage {
                        Text("From: \(message.uid)\nType: \(message.type)\nLocation: \(message.lat), \(message.lon)")
                    }
                }
            }
            
            .tabItem {
                Label("Drones", systemImage: "airplane.circle")
            }
            .tag(1)
            
            NavigationStack {
                StatusListView(statusViewModel: statusViewModel)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: { statusViewModel.statusMessages.removeAll() }) {
                                Image(systemName: "trash")
                            }
                        }
                    }
            }
            .tabItem {
                Label("Status", systemImage: "server.rack")
            }
            .tag(2)
            
            NavigationStack {
                SettingsView(cotHandler: cotViewModel)
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(3)
            
            NavigationStack {
                StoredEncountersView()
            }
            .tabItem {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .tag(4) 
            
//            NavigationStack {
//                SpectrumView(viewModel: spectrumViewModel)
//                    .navigationTitle("Spectrum")
//            }
//            .tabItem {
//                Label("Spectrum", systemImage: "waveform")
//            }
//            .tag(4)
        }
        
        .onChange(of: settings.isListening) {
            if settings.isListening {
                cotViewModel.startListening()
            } else { 
                cotViewModel.stopListening()
            }
        }
        .onChange(of: settings.serialConsoleEnabled) {
            if settings.serialConsoleEnabled {
                if Settings.shared.connectionMode == .multicast {
                    serialViewModel.startListening(port: UInt16(Settings.shared.serialConsoleMulticastPort))
                } else {
                    serialViewModel.startListening(port: UInt16(Settings.shared.serialConsoleZMQPort))
                }
            } else {
                serialViewModel.stopListening()
            }
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue != 3 { // Spectrum tab
                spectrumViewModel.stopListening()
            } else if settings.isListening {
                let port = UInt16(UserDefaults.standard.integer(forKey: "spectrumPort"))
                spectrumViewModel.startListening(port: port)
            }
        }
        
//        .onChange(of: settings.connectionMode) {
//            if settings.isListening {
//                // Handle switch when enabled, for now just do not allow
//            }
//        }
    }
}
