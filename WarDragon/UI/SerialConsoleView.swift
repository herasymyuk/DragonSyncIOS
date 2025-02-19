//
//  SerialConsoleView.swift
//  WarDragon
//
//  Created by Luke on 2/18/25.
//

import Foundation
import SwiftUI


struct SerialConsoleView: View {
    @StateObject private var viewModel = SerialConsoleViewModel()
    @State private var isAutoscrolling = true
    private let maxMessages = 1000
    
    struct SerialMessage: Identifiable {
        let id = UUID()
        let timestamp: Date
        let content: String
        let type: MessageType
        
        enum MessageType {
            case input
            case output
            case system
            
            var color: Color {
                switch self {
                case .input: return .green
                case .output: return .cyan
                case .system: return .yellow
                }
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Green Stroke Wrapper
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.3), lineWidth: 2)
            
            // Terminal background
            Color.black
                .edgesIgnoringSafeArea(.all)
                .overlay(
                    // Scanline effect
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.0),
                                    Color.white.opacity(0.1),
                                    Color.white.opacity(0.0)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .opacity(0.1)
                )
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("SERIAL CONSOLE")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(.green)
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.messages.removeAll()
                    }) {
                        Text("Clear")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.orange)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                            )
                    }
                    
                    Toggle(isOn: $isAutoscrolling) {
                        Text("Autoscroll")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isAutoscrolling ? Color.green : Color.gray)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                            )
                    }
                    .toggleStyle(.button)
                }
                .padding()
                .background(Color.black.opacity(0.8))

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(viewModel.messages) { message in
                                MessageRow(message: message)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        if isAutoscrolling, let lastMessage = viewModel.messages.last {
                            DispatchQueue.main.async {
                                withAnimation {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
            .onAppear {
                // Start listening for serial data when view appears
                if Settings.shared.connectionMode == .multicast {
                    viewModel.startListening(port: UInt16(Settings.shared.serialConsoleMulticastPort))
                } else {
                    viewModel.startListening(port: UInt16(Settings.shared.serialConsoleZMQPort))
                }
            }
            .onDisappear {
                // Stop listening when view disappears
                viewModel.stopListening()
            }
        }
    }
    
    struct MessageRow: View {
        let message: SerialMessage
        
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(message.timestamp, format: .dateTime.hour().minute().second())
                        .foregroundColor(.gray)
                    Text(message.content)
                        .foregroundColor(message.type.color)
                }
                .font(.system(.body, design: .monospaced))
            }
            .padding(.vertical, 2)
        }
    }
    
    func addMessage(_ content: String, type: SerialMessage.MessageType = .output) {
        let message = SerialMessage(timestamp: Date(), content: content, type: type)
        viewModel.messages.append(message)
        
        // Trim old messages if needed
        if viewModel.messages.count > maxMessages {
            viewModel.messages.removeFirst(viewModel.messages.count - maxMessages)
        }
    }
}
