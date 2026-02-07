// Incident.swift
// Core data model for emergency incidents

import Foundation
import CoreLocation

struct Incident: Codable, Identifiable {
    let id: UUID
    let sessionStart: Date
    var sessionEnd: Date?
    var status: IncidentStatus
    var classification: EmergencyClassification
    var confidence: Double
    var explanation: String?
    var events: [IncidentEvent]
    var locationSnapshots: [LocationSnapshot]
    var sensorSnapshots: [SensorSnapshot]
    var escalationLevel: EscalationLevel
    var mediaCaptures: [MediaCapture]
    
    init(id: UUID = UUID(), sessionStart: Date = Date()) {
        self.id = id
        self.sessionStart = sessionStart
        self.sessionEnd = nil
        self.status = .active
        self.classification = .unknown
        self.confidence = 0.0
        self.explanation = nil
        self.events = []
        self.locationSnapshots = []
        self.sensorSnapshots = []
        self.escalationLevel = .none
        self.mediaCaptures = []
    }
}

enum IncidentStatus: String, Codable {
    case active         // Currently in progress
    case cancelled      // User cancelled
    case escalated      // Help requested
    case resolved       // Completed
    case duress         // Cancelled under duress (silent alert sent)
}

enum EmergencyClassification: String, Codable, CaseIterable {
    case medical    // Fall, fainting, health crisis
    case accident   // Vehicle collision, impact
    case safety     // Threat, followed, distress
    case unknown
    
    var displayName: String {
        switch self {
        case .medical: return "Medical Emergency"
        case .accident: return "Accident"
        case .safety: return "Personal Safety"
        case .unknown: return "Unknown"
        }
    }
    
    var icon: String {
        switch self {
        case .medical: return "heart.circle.fill"
        case .accident: return "car.circle.fill"
        case .safety: return "shield.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

enum EscalationLevel: Int, Codable, Comparable {
    case none = 0
    case trustedContacts = 1
    case emergencyServices = 2
    case nearbyResponders = 3
    
    static func < (lhs: EscalationLevel, rhs: EscalationLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    var displayName: String {
        switch self {
        case .none: return "Monitoring"
        case .trustedContacts: return "Contacts Notified"
        case .emergencyServices: return "Emergency Services"
        case .nearbyResponders: return "Nearby Responders"
        }
    }
}

struct IncidentEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let type: EventType
    let description: String
    let data: [String: String]?
    
    init(type: EventType, description: String, data: [String: String]? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = type
        self.description = description
        self.data = data
    }
}

enum EventType: String, Codable {
    case sessionStarted
    case sessionCancelled
    case sessionEscalated
    case classificationUpdated
    case motionDetected
    case audioDetected
    case locationUpdated
    case contactNotified
    case emergencyServicesContacted
    case videoRecordingStarted
    case videoRecordingStopped
    case photoTaken
    case userAction
}

struct LocationSnapshot: Codable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let horizontalAccuracy: Double
    let speed: Double?
    let heading: Double?
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    init(from location: CLLocation) {
        self.timestamp = location.timestamp
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
        self.horizontalAccuracy = location.horizontalAccuracy
        self.speed = location.speed >= 0 ? location.speed : nil
        self.heading = location.course >= 0 ? location.course : nil
    }
}
