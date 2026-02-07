// LLMAction.swift
// Models for LLM-coordinated emergency actions

import Foundation

// MARK: - Certainty Levels

/// Certainty threshold for autonomous LLM actions
enum CertaintyLevel: Double, Codable, Comparable {
    case low = 0.3        // Suggest only, require confirmation
    case moderate = 0.6   // Can act on non-critical actions
    case high = 0.8       // Can escalate to contacts
    case critical = 0.95  // Can contact emergency services
    
    static func < (lhs: CertaintyLevel, rhs: CertaintyLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    var displayName: String {
        switch self {
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }
    
    var thresholdDescription: String {
        switch self {
        case .low: return "Suggestions only"
        case .moderate: return "Location sharing, documentation"
        case .high: return "Contact notification"
        case .critical: return "Emergency services"
        }
    }
}

// MARK: - LLM Actions

/// Actions the LLM coordinator can take
enum LLMActionType: String, Codable {
    case shareLocation          // Enable live location sharing
    case notifyContacts         // Send alerts to trusted contacts
    case escalateToServices     // Contact emergency services
    case captureEvidence        // Take photo/start recording
    case suggestAction          // Display suggestion to user
    case updateStatus           // Update incident status
    case noAction               // Continue monitoring
    
    var requiresConfirmation: Bool {
        switch self {
        case .escalateToServices: return true
        case .notifyContacts, .shareLocation: return false
        case .captureEvidence, .suggestAction, .updateStatus, .noAction: return false
        }
    }
    
    var minimumCertainty: CertaintyLevel {
        switch self {
        case .escalateToServices: return .critical
        case .notifyContacts: return .high
        case .shareLocation: return .moderate
        case .captureEvidence: return .moderate
        case .suggestAction, .updateStatus, .noAction: return .low
        }
    }
    
    var displayName: String {
        switch self {
        case .shareLocation: return "Share Location"
        case .notifyContacts: return "Notify Contacts"
        case .escalateToServices: return "Call Emergency Services"
        case .captureEvidence: return "Capture Evidence"
        case .suggestAction: return "Suggestion"
        case .updateStatus: return "Status Update"
        case .noAction: return "Monitoring"
        }
    }
    
    var icon: String {
        switch self {
        case .shareLocation: return "location.fill"
        case .notifyContacts: return "person.2.fill"
        case .escalateToServices: return "phone.fill"
        case .captureEvidence: return "camera.fill"
        case .suggestAction: return "lightbulb.fill"
        case .updateStatus: return "info.circle.fill"
        case .noAction: return "eye.fill"
        }
    }
}

// MARK: - LLM Decision

/// A decision made by the LLM coordinator
struct LLMDecision: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let actionType: LLMActionType
    let reasoning: String
    let certainty: Double
    let suggestedMessage: String?
    let wasExecuted: Bool
    let requiresConfirmation: Bool
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        actionType: LLMActionType,
        reasoning: String,
        certainty: Double,
        suggestedMessage: String? = nil,
        wasExecuted: Bool = false,
        requiresConfirmation: Bool? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.actionType = actionType
        self.reasoning = reasoning
        self.certainty = certainty
        self.suggestedMessage = suggestedMessage
        self.wasExecuted = wasExecuted
        self.requiresConfirmation = requiresConfirmation ?? actionType.requiresConfirmation
    }
    
    var certaintyLevel: CertaintyLevel {
        if certainty >= CertaintyLevel.critical.rawValue { return .critical }
        if certainty >= CertaintyLevel.high.rawValue { return .high }
        if certainty >= CertaintyLevel.moderate.rawValue { return .moderate }
        return .low
    }
    
    var canExecuteAutonomously: Bool {
        certaintyLevel >= actionType.minimumCertainty
    }
}

// MARK: - Coordinator State

/// Current state of the LLM coordinator
enum CoordinatorState: String, Codable {
    case idle           // Not active
    case listening      // Monitoring sensor data
    case analyzing      // Processing with LLM
    case acting         // Executing an action
    case waitingConfirm // Waiting for user confirmation
    case error          // Error state
    
    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .listening: return "Monitoring"
        case .analyzing: return "Analyzing..."
        case .acting: return "Taking Action"
        case .waitingConfirm: return "Awaiting Confirmation"
        case .error: return "Error"
        }
    }
    
    var icon: String {
        switch self {
        case .idle: return "moon.fill"
        case .listening: return "waveform"
        case .analyzing: return "brain"
        case .acting: return "bolt.fill"
        case .waitingConfirm: return "hand.raised.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
    
    var isActive: Bool {
        switch self {
        case .listening, .analyzing, .acting, .waitingConfirm: return true
        case .idle, .error: return false
        }
    }
}

// MARK: - LLM Transcript Entry

/// An entry in the LLM conversation/action transcript
struct LLMTranscriptEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let type: TranscriptEntryType
    let content: String
    let metadata: [String: String]?
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        type: TranscriptEntryType,
        content: String,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.content = content
        self.metadata = metadata
    }
}

enum TranscriptEntryType: String, Codable {
    case observation    // Sensor data observation
    case analysis       // LLM analysis
    case decision       // Action decision
    case action         // Action taken
    case confirmation   // User confirmation
    case error          // Error occurred
    
    var icon: String {
        switch self {
        case .observation: return "sensor.tag.radiowaves.forward"
        case .analysis: return "brain"
        case .decision: return "lightbulb.fill"
        case .action: return "checkmark.circle.fill"
        case .confirmation: return "hand.thumbsup.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}
