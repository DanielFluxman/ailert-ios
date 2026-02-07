// SettingsManager.swift
// Manages user settings and preferences

import Foundation
import Combine

class SettingsManager: ObservableObject {
    // MARK: - Published Settings
    @Published var trustedContacts: [TrustedContact] = []
    @Published var emergencyProfile: EmergencyProfile = EmergencyProfile()
    @Published var cancelPIN: String = ""
    @Published var duressPIN: String = ""
    
    // MARK: - Trigger Settings
    @Published var enableShakeTrigger: Bool = true
    @Published var enableVolumeButtonTrigger: Bool = true
    @Published var volumeButtonPressCount: Int = 5
    
    // MARK: - Escalation Settings
    @Published var cancelWindowSeconds: Int = 30
    @Published var autoEscalateSeconds: Int = 60
    @Published var enableNearbyResponders: Bool = false
    @Published var nearbyResponderRadius: Double = 500 // meters
    
    // MARK: - Recording Settings
    @Published var autoRecordVideo: Bool = true
    @Published var defaultCamera: CameraPosition = .back
    @Published var maxVideoLengthMinutes: Int = 5
    
    // MARK: - Privacy Settings
    @Published var shareLocationWithContacts: Bool = true
    @Published var sharePreciseLocation: Bool = true // vs coarse
    @Published var shareMediaWithContacts: Bool = false
    
    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init() {
        loadSettings()
    }
    
    // MARK: - Trusted Contacts
    
    func addContact(_ contact: TrustedContact) {
        trustedContacts.append(contact)
        saveContacts()
    }
    
    func updateContact(_ contact: TrustedContact) {
        if let index = trustedContacts.firstIndex(where: { $0.id == contact.id }) {
            trustedContacts[index] = contact
            saveContacts()
        }
    }
    
    func removeContact(_ contact: TrustedContact) {
        trustedContacts.removeAll { $0.id == contact.id }
        saveContacts()
    }
    
    func reorderContacts(from source: IndexSet, to destination: Int) {
        trustedContacts.move(fromOffsets: source, toOffset: destination)
        // Update priorities based on new order
        for (index, _) in trustedContacts.enumerated() {
            trustedContacts[index].priority = index + 1
        }
        saveContacts()
    }
    
    // MARK: - Persistence
    
    private func loadSettings() {
        // Load trusted contacts
        if let data = defaults.data(forKey: "trustedContacts"),
           let contacts = try? decoder.decode([TrustedContact].self, from: data) {
            trustedContacts = contacts
        }
        
        // Load emergency profile
        if let data = defaults.data(forKey: "emergencyProfile"),
           let profile = try? decoder.decode(EmergencyProfile.self, from: data) {
            emergencyProfile = profile
        }
        
        // Load PINs (should use Keychain in production)
        cancelPIN = defaults.string(forKey: "cancelPIN") ?? ""
        duressPIN = defaults.string(forKey: "duressPIN") ?? ""
        
        // Load trigger settings
        enableShakeTrigger = defaults.bool(forKey: "enableShakeTrigger")
        enableVolumeButtonTrigger = defaults.bool(forKey: "enableVolumeButtonTrigger")
        volumeButtonPressCount = defaults.integer(forKey: "volumeButtonPressCount")
        if volumeButtonPressCount == 0 { volumeButtonPressCount = 5 }
        
        // Load escalation settings
        cancelWindowSeconds = defaults.integer(forKey: "cancelWindowSeconds")
        if cancelWindowSeconds == 0 { cancelWindowSeconds = 30 }
        autoEscalateSeconds = defaults.integer(forKey: "autoEscalateSeconds")
        if autoEscalateSeconds == 0 { autoEscalateSeconds = 60 }
        enableNearbyResponders = defaults.bool(forKey: "enableNearbyResponders")
        
        // Load recording settings
        autoRecordVideo = defaults.bool(forKey: "autoRecordVideo")
    }
    
    private func saveContacts() {
        if let data = try? encoder.encode(trustedContacts) {
            defaults.set(data, forKey: "trustedContacts")
        }
    }
    
    func saveEmergencyProfile() {
        if let data = try? encoder.encode(emergencyProfile) {
            defaults.set(data, forKey: "emergencyProfile")
        }
    }
    
    func savePINs() {
        // TODO: Use Keychain for secure storage
        defaults.set(cancelPIN, forKey: "cancelPIN")
        defaults.set(duressPIN, forKey: "duressPIN")
    }
    
    func saveTriggerSettings() {
        defaults.set(enableShakeTrigger, forKey: "enableShakeTrigger")
        defaults.set(enableVolumeButtonTrigger, forKey: "enableVolumeButtonTrigger")
        defaults.set(volumeButtonPressCount, forKey: "volumeButtonPressCount")
    }
    
    func saveEscalationSettings() {
        defaults.set(cancelWindowSeconds, forKey: "cancelWindowSeconds")
        defaults.set(autoEscalateSeconds, forKey: "autoEscalateSeconds")
        defaults.set(enableNearbyResponders, forKey: "enableNearbyResponders")
    }
    
    func saveRecordingSettings() {
        defaults.set(autoRecordVideo, forKey: "autoRecordVideo")
    }
}
