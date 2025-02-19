//
//  StatusListView.swift
//  WarDragon
//
//  Created by Luke on 11/18/24.
//

import SwiftUI

struct StatusListView: View {
    @ObservedObject var statusViewModel: StatusViewModel
    @StateObject private var serviceViewModel = ServiceViewModel()
    @State private var showServiceManagement = false
    @StateObject private var settings = Settings.shared
    
    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                List {
                    // Service Status Widget
//                    Section {
//                        ServiceStatusWidget(
//                            healthReport: serviceViewModel.healthReport,
//                            criticalServices: serviceViewModel.criticalServices(),
//                            showServiceManagement: $showServiceManagement
//                        )
//                    }
//                    .listRowInsets(EdgeInsets())
//                    .listRowBackground(Color.clear)
                    
                    // System status messages
                    Section {
                        ForEach(statusViewModel.statusMessages) { message in
                            StatusMessageView(message: message)
                        }
                    }
                    Section {
                        if settings.serialConsoleEnabled {
                            SerialConsoleView()
                                .frame(height: 400)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: geometry.size.height, alignment: .center)
                .onChange(of: statusViewModel.statusMessages.count) { _, _ in
                    if let latest = statusViewModel.statusMessages.last {
                        withAnimation {
                            proxy.scrollTo(latest.id, anchor: .bottom)
                        }
                    }
                }
                // Option to start/stop status listening (needs handler to see if running)
//                .onAppear {
//                    serviceViewModel.startMonitoring()
//                }
//                .onDisappear {
//                    serviceViewModel.stopMonitoring()
//                }
            }
        }
        .navigationTitle("System Status")
        .sheet(isPresented: $showServiceManagement) {
            NavigationView {
                ServiceManagementView(viewModel: serviceViewModel)
                    .navigationTitle("Service Management")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Done") {
                                showServiceManagement = false
                            }
                        }
                    }
            }
            // Force the status monitor ZMQ/Multicast to listen when tapping system services
//            .onAppear {
//                    serviceViewModel.startMonitoring()
//            }
//            .onDisappear {
//                    serviceViewModel.stopMonitoring()
//            }
        }
    }
}

struct ServiceStatusWidget: View {
    let healthReport: ServiceViewModel.HealthReport?
    let criticalServices: [ServiceControl]
    @Binding var showServiceManagement: Bool
    
    var body: some View {
        Button(action: { showServiceManagement = true }) {
            VStack(spacing: 4) {
                // Health Status Bar
//                HStack(spacing: 12) {
//                    Circle()
//                        .fill(healthReport?.statusColor ?? .gray)
//                        .frame(width: 12, height: 12)
//                    
//                    Text(healthReport?.overallHealth.uppercased() ?? "SYSTEM SERVICES")
//                        .font(.appHeadline)
//                    
//                    Spacer()
//                    
//                    Image(systemName: "chevron.right")
//                        .foregroundColor(.secondary)
//                }
                
                // Critical Services Preview
                if !criticalServices.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CRITICAL SERVICES")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.red)
                        
                        ForEach(criticalServices.prefix(2)) { service in
                            HStack {
                                Circle()
                                    .fill(service.status.healthStatus.color)
                                    .frame(width: 8, height: 8)
                                Text(service.description)
                                    .font(.system(.caption, design: .monospaced))
                                Spacer()
                            }
                        }
                        
                        if criticalServices.count > 2 {
                            Text("+ \(criticalServices.count - 2) more")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            .padding(.horizontal)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
