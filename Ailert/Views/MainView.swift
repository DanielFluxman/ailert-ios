// MainView.swift
// Primary app view with SOS button

import SwiftUI

struct MainView: View {
    @EnvironmentObject var incidentManager: IncidentSessionManager
    @State private var showSettings = false
    @State private var showHistory = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.1),
                        Color(red: 0.1, green: 0.05, blue: 0.15)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 40) {
                    Spacer()
                    
                    // Status indicator
                    StatusIndicator()
                    
                    // Main SOS Button - starts session immediately
                    SOSButtonView {
                        incidentManager.startSession(classification: .unknown)
                    }
                    
                    // Quick actions for pre-classified emergencies
                    HStack(spacing: 30) {
                        QuickActionButton(
                            icon: "heart.fill",
                            label: "Medical",
                            color: .red
                        ) {
                            incidentManager.startSession(classification: .medical)
                        }
                        
                        QuickActionButton(
                            icon: "car.fill",
                            label: "Accident",
                            color: .orange
                        ) {
                            incidentManager.startSession(classification: .accident)
                        }
                        
                        QuickActionButton(
                            icon: "shield.fill",
                            label: "Safety",
                            color: .blue
                        ) {
                            incidentManager.startSession(classification: .safety)
                        }
                    }
                    .padding(.top, 20)
                    
                    Spacer()
                    
                    // Bottom info
                    Text("Press and hold for emergency")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.bottom, 30)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.white)
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text("Ailert")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.white)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showHistory) {
                IncidentHistoryView()
            }
        }
    }
}

// MARK: - Status Indicator

struct StatusIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
            
            Text("Ready")
                .font(.caption)
                .foregroundColor(.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.green.opacity(0.2))
        )
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Text(label)
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .frame(width: 70, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.1))
            )
        }
    }
}

#Preview {
    MainView()
        .environmentObject(IncidentSessionManager())
        .environmentObject(SettingsManager())
}
