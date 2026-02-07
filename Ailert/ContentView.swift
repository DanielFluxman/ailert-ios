// ContentView.swift
// Root view that handles navigation between main states

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var incidentManager: IncidentSessionManager
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
            } else if incidentManager.hasActiveIncident {
                ActiveIncidentView()
            } else {
                MainView()
            }
        }
        .animation(.easeInOut, value: incidentManager.hasActiveIncident)
    }
}

#Preview {
    ContentView()
        .environmentObject(IncidentSessionManager())
        .environmentObject(SettingsManager())
}
