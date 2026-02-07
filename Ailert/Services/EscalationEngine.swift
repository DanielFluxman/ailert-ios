// EscalationEngine.swift
// Handles the privacy-first escalation ladder

import Foundation
import MessageUI
import CallKit

class EscalationEngine: ObservableObject {
    // MARK: - Published State
    @Published var currentLevel: EscalationLevel = .none
    @Published var notifiedContacts: [UUID] = []
    @Published var emergencyServicesContacted: Bool = false
    
    // MARK: - Dependencies
    private let callController = CXCallController()
    
    // MARK: - Escalation
    
    func escalate(incident: Incident, to level: EscalationLevel) async {
        guard level > currentLevel else { return }
        
        currentLevel = level
        
        switch level {
        case .none:
            break
            
        case .trustedContacts:
            await notifyTrustedContacts(for: incident)
            
        case .emergencyServices:
            await notifyTrustedContacts(for: incident)
            prepareEmergencyCall(for: incident)
            
        case .nearbyResponders:
            await notifyTrustedContacts(for: incident)
            prepareEmergencyCall(for: incident)
            await alertNearbyResponders(for: incident)
        }
    }
    
    // MARK: - Silent Escalation (Duress)
    
    func silentEscalate(incident: Incident) {
        // Send silent alert to trusted contacts without showing user
        Task {
            await notifyTrustedContacts(for: incident, isSilent: true)
        }
    }
    
    // MARK: - Trusted Contacts
    
    private func notifyTrustedContacts(for incident: Incident, isSilent: Bool = false) async {
        let contacts = loadTrustedContacts().filter { $0.isEnabled }
        
        for contact in contacts.sorted(by: { $0.priority < $1.priority }) {
            if contact.notifyVia.contains(.sms) {
                await sendSMS(to: contact, for: incident, isSilent: isSilent)
            }
            
            if contact.notifyVia.contains(.call) && !isSilent {
                // Don't auto-call, just prepare
            }
            
            notifiedContacts.append(contact.id)
        }
    }
    
    private func sendSMS(to contact: TrustedContact, for incident: Incident, isSilent: Bool) async {
        // Build message
        var message = isSilent ? "🚨 DURESS ALERT: " : "🆘 EMERGENCY ALERT: "
        message += "This is an automated alert from Ailert. "
        
        if let location = incident.locationSnapshots.last {
            message += "Location: https://maps.apple.com/?ll=\(location.latitude),\(location.longitude)"
        }
        
        if isSilent {
            message += " (User may be in danger - this was a silent alert)"
        }
        
        // In production, this would use a messaging service or native SMS
        // For now, prepare the URL scheme
        let urlString = "sms:\(contact.phone)&body=\(message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        if let url = URL(string: urlString) {
            await MainActor.run {
                // Would open SMS composer or use a service
                print("Would send SMS to \(contact.phone): \(message)")
            }
        }
    }
    
    // MARK: - Emergency Services
    
    func prepareEmergencyCall(for incident: Incident) {
        emergencyServicesContacted = true
        
        // Using CallKit to initiate 911 call
        // Note: In a real app, you might want user confirmation
        let handle = CXHandle(type: .phoneNumber, value: "911")
        let startCallAction = CXStartCallAction(call: UUID(), handle: handle)
        let transaction = CXTransaction(action: startCallAction)
        
        // Don't auto-dial - prepare for user to confirm
        print("Emergency call prepared for 911")
    }
    
    func initiateEmergencyCall() {
        // Direct dial using tel: URL scheme
        if let url = URL(string: "tel://911") {
            Task { @MainActor in
                // UIApplication.shared.open(url)
                print("Would dial 911")
            }
        }
    }
    
    // MARK: - Nearby Responders (Opt-in)
    
    private func alertNearbyResponders(for incident: Incident) async {
        guard let location = incident.locationSnapshots.last else { return }
        
        // Coarse location only - round to ~500m precision
        let coarseLatitude = (location.latitude * 200).rounded() / 200
        let coarseLongitude = (location.longitude * 200).rounded() / 200
        
        // In production, this would connect to a server with opted-in responders
        // For now, just log
        print("Would alert nearby responders at coarse location: \(coarseLatitude), \(coarseLongitude)")
        
        // IMPORTANT: No identifying information shared, just:
        // - Coarse location
        // - Emergency type
        // - Time
    }
    
    // MARK: - Helpers
    
    private func loadTrustedContacts() -> [TrustedContact] {
        guard let data = UserDefaults.standard.data(forKey: "trustedContacts"),
              let contacts = try? JSONDecoder().decode([TrustedContact].self, from: data) else {
            return []
        }
        return contacts
    }
    
    func reset() {
        currentLevel = .none
        notifiedContacts.removeAll()
        emergencyServicesContacted = false
    }
}
