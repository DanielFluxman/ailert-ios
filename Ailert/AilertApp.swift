// AilertApp.swift
// Main entry point for Ailert

import SwiftUI

@main
struct AilertApp: App {
    @StateObject private var incidentManager = IncidentSessionManager()
    @StateObject private var settingsManager = SettingsManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(incidentManager)
                .environmentObject(settingsManager)
        }
    }
}
