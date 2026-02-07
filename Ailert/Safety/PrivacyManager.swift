// PrivacyManager.swift
// Controls data sharing and privacy settings

import Foundation
import CoreLocation

class PrivacyManager {
    static let shared = PrivacyManager()
    
    private init() {}
    
    // MARK: - Location Privacy
    
    /// Returns coarse location (rounded to ~500m precision)
    func getCoarseLocation(from location: CLLocation) -> CLLocationCoordinate2D {
        // Round to approximately 500m precision
        let precision: Double = 200 // Divisions per degree (~500m at equator)
        
        let coarseLat = (location.coordinate.latitude * precision).rounded() / precision
        let coarseLon = (location.coordinate.longitude * precision).rounded() / precision
        
        return CLLocationCoordinate2D(latitude: coarseLat, longitude: coarseLon)
    }
    
    /// Determines what location precision to share based on recipient
    func locationPrecision(for recipient: RecipientType) -> LocationPrecision {
        let settings = UserDefaults.standard
        
        switch recipient {
        case .trustedContact:
            return settings.bool(forKey: "sharePreciseLocation") ? .precise : .coarse
            
        case .emergencyServices:
            // Always share precise with 911
            return .precise
            
        case .nearbyResponder:
            // Always coarse for strangers
            return .coarse
        }
    }
    
    // MARK: - Data Minimization
    
    /// Creates a privacy-safe incident summary for sharing
    func createSafeIncidentSummary(from incident: Incident, for recipient: RecipientType) -> SafeIncidentSummary {
        let locationPrecision = self.locationPrecision(for: recipient)
        
        var summary = SafeIncidentSummary()
        summary.emergencyType = incident.classification.displayName
        summary.startTime = incident.sessionStart
        
        // Add location based on precision
        if let location = incident.locationSnapshots.last {
            switch locationPrecision {
            case .precise:
                summary.latitude = location.latitude
                summary.longitude = location.longitude
            case .coarse:
                let coord = CLLocation(latitude: location.latitude, longitude: location.longitude)
                let coarse = getCoarseLocation(from: coord)
                summary.latitude = coarse.latitude
                summary.longitude = coarse.longitude
            case .none:
                break
            }
        }
        
        // Only share name with trusted contacts and 911
        if recipient == .trustedContact || recipient == .emergencyServices {
            let profile = loadEmergencyProfile()
            summary.userName = profile.fullName
        }
        
        return summary
    }
    
    // MARK: - Anti-Doxxing
    
    /// Validates that shared data doesn't contain identifying info for public sharing
    func sanitizeForPublicSharing(_ text: String) -> String {
        var sanitized = text
        
        // Remove phone numbers
        let phonePattern = #"\b\d{3}[-.]?\d{3}[-.]?\d{4}\b"#
        sanitized = sanitized.replacingOccurrences(
            of: phonePattern,
            with: "[REDACTED]",
            options: .regularExpression
        )
        
        // Remove email addresses
        let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        sanitized = sanitized.replacingOccurrences(
            of: emailPattern,
            with: "[REDACTED]",
            options: .regularExpression
        )
        
        // Remove SSN-like patterns
        let ssnPattern = #"\b\d{3}[-]?\d{2}[-]?\d{4}\b"#
        sanitized = sanitized.replacingOccurrences(
            of: ssnPattern,
            with: "[REDACTED]",
            options: .regularExpression
        )
        
        return sanitized
    }
    
    // MARK: - Data Retention
    
    /// Clears old incident data based on retention policy
    func enforceDataRetention(daysToKeep: Int = 90) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysToKeep, to: Date()) ?? Date()
        
        let incidents = IncidentStore.shared.loadAll()
        for incident in incidents {
            if incident.sessionStart < cutoffDate {
                IncidentStore.shared.delete(id: incident.id)
                deleteMediaCaptures(for: incident)
            }
        }
    }
    
    private func deleteMediaCaptures(for incident: Incident) {
        let fileManager = FileManager.default
        for capture in incident.mediaCaptures {
            try? fileManager.removeItem(at: capture.localFileURL)
        }
    }
    
    private func loadEmergencyProfile() -> EmergencyProfile {
        guard let data = UserDefaults.standard.data(forKey: "emergencyProfile"),
              let profile = try? JSONDecoder().decode(EmergencyProfile.self, from: data) else {
            return EmergencyProfile()
        }
        return profile
    }
}

// MARK: - Models

enum RecipientType {
    case trustedContact
    case emergencyServices
    case nearbyResponder
}

enum LocationPrecision {
    case precise    // Exact GPS coordinates
    case coarse     // ~500m accuracy
    case none       // No location
}

struct SafeIncidentSummary: Codable {
    var emergencyType: String?
    var startTime: Date?
    var latitude: Double?
    var longitude: Double?
    var userName: String?
    
    var mapsURL: URL? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return URL(string: "https://maps.apple.com/?ll=\(lat),\(lon)")
    }
}
