// LLMContextBuilder.swift
// Formats sensor data and incident context for LLM prompts

import Foundation
import CoreLocation

// MARK: - Context Builder

class LLMContextBuilder {
    
    // MARK: - System Prompt
    
    static let systemPrompt = """
    You are an emergency response AI assistant embedded in a personal safety app called Ailert. Your role is to:
    
    1. MONITOR sensor data (motion, audio, location) during active incidents
    2. ANALYZE patterns that indicate danger, distress, or escalating situations
    3. DECIDE on appropriate actions based on certainty thresholds
    4. EXPLAIN your reasoning clearly so users understand what's happening
    
    ## Available Actions
    - shareLocation: Enable live location sharing with trusted contacts
    - notifyContacts: Send alert messages to trusted emergency contacts
    - escalateToServices: Recommend calling emergency services (911)
    - captureEvidence: Start recording or take photos
    - suggestAction: Display a suggestion to the user
    - updateStatus: Update the incident classification
    - noAction: Continue monitoring without action
    
    ## Certainty Thresholds for Autonomous Actions
    - 0.3+ (low): Suggestions only
    - 0.6+ (moderate): Can enable location sharing, start recording
    - 0.8+ (high): Can notify trusted contacts
    - 0.95+ (critical): Can recommend emergency services
    
    ## Response Format
    Respond with a JSON object:
    {
        "action": "actionType",
        "certainty": 0.0-1.0,
        "reasoning": "Brief explanation of your analysis",
        "message": "Optional message to display or send"
    }
    
    ## Guidelines
    - Err on the side of caution in genuine emergencies
    - Be conservative with high-impact actions (calling 911)
    - Consider context: a fall while running differs from a fall while stationary
    - Battery/connectivity issues may warrant proactive location sharing
    - Sudden silence after distress sounds is concerning
    - Always explain your reasoning briefly for transparency
    
    Current time context will be provided. Focus on pattern changes over time.
    """
    
    // MARK: - Build Context
    
    /// Build a context prompt from the current incident state
    static func buildContextPrompt(
        incident: Incident,
        recentSensorData: [SensorSnapshot],
        motionPattern: MotionPattern,
        detectedSounds: [DetectedSound],
        currentLocation: CLLocation?,
        previousDecisions: [LLMDecision],
        speechTranscript: String? = nil
    ) -> String {
        var context = "## Current Incident Status\n"
        context += "- Started: \(formatTimeAgo(incident.sessionStart))\n"
        context += "- Classification: \(incident.classification.displayName)\n"
        context += "- Escalation Level: \(incident.escalationLevel.displayName)\n"
        context += "- Location Sharing: \(incident.liveShareSession?.isActive == true ? "Active" : "Not active")\n"
        context += "\n"
        
        // Live Speech Transcript (CRITICAL for understanding what's happening)
        context += "## Live Audio Transcript\n"
        if let transcript = speechTranscript, !transcript.isEmpty {
            context += transcript + "\n"
        } else {
            context += "[No speech detected or transcription not available]\n"
        }
        context += "\n"
        
        // Motion analysis
        context += "## Motion Analysis\n"
        context += "- Current Pattern: \(motionPattern.rawValue)\n"
        if let recentMotion = recentSensorData.last?.motion {
            context += "- Acceleration Magnitude: \(String(format: "%.2f", recentMotion.accelerationMagnitude))g\n"
        }
        context += buildMotionHistory(from: recentSensorData)
        context += "\n"
        
        // Audio analysis
        context += "## Audio Analysis\n"
        if let recentAudio = recentSensorData.last?.audio {
            context += "- Current Level: \(String(format: "%.1f", recentAudio.averageDecibels))dB\n"
            context += "- Peak Level: \(String(format: "%.1f", recentAudio.peakDecibels))dB\n"
            context += "- Voice Activity: \(recentAudio.hasVoiceActivity ? "Detected" : "None")\n"
        }
        if !detectedSounds.isEmpty {
            context += "- Detected Sounds: \(detectedSounds.map { "\($0.displayName) (\(Int($0.confidence * 100))%)" }.joined(separator: ", "))\n"
        }
        context += "\n"
        
        // Location analysis
        context += "## Location\n"
        if let location = currentLocation {
            context += "- Speed: \(location.speed >= 0 ? "\(String(format: "%.1f", location.speed * 2.237)) mph" : "Stationary")\n"
            context += "- Accuracy: \(String(format: "%.0f", location.horizontalAccuracy))m\n"
        }
        context += buildLocationHistory(from: incident.locationSnapshots)
        context += "\n"
        
        // Device context
        if let deviceContext = recentSensorData.last?.deviceContext {
            context += "## Device Status\n"
            context += "- Battery: \(Int(deviceContext.batteryLevel * 100))%\n"
            context += "- Network: \(deviceContext.networkType.rawValue)\n"
            context += "\n"
        }
        
        // Recent events
        let recentEvents = incident.events.suffix(5)
        if !recentEvents.isEmpty {
            context += "## Recent Events\n"
            for event in recentEvents {
                context += "- \(formatTimeAgo(event.timestamp)): \(event.description)\n"
            }
            context += "\n"
        }
        
        // Previous LLM decisions
        if !previousDecisions.isEmpty {
            context += "## Your Previous Decisions\n"
            for decision in previousDecisions.suffix(3) {
                context += "- \(formatTimeAgo(decision.timestamp)): \(decision.actionType.displayName)"
                if decision.wasExecuted {
                    context += " (executed)"
                }
                context += "\n"
            }
            context += "\n"
        }
        
        // User contacts info
        context += "## User's Trusted Contacts\n"
        let contacts = loadTrustedContacts()
        if contacts.isEmpty {
            context += "- No trusted contacts configured\n"
        } else {
            context += "- \(contacts.count) contact(s) available\n"
        }
        context += "\n"
        
        context += "## Your Task\n"
        context += "Based on the above data, determine if any action should be taken. "
        context += "Respond with JSON specifying your decision.\n"
        
        return context
    }
    
    // MARK: - Helpers
    
    private static func buildMotionHistory(from snapshots: [SensorSnapshot]) -> String {
        guard snapshots.count >= 3 else { return "" }
        
        let magnitudes = snapshots.compactMap { $0.motion?.accelerationMagnitude }
        guard !magnitudes.isEmpty else { return "" }
        
        let avg = magnitudes.reduce(0, +) / Double(magnitudes.count)
        let max = magnitudes.max() ?? 0
        let min = magnitudes.min() ?? 0
        
        var result = "- Recent Motion: avg=\(String(format: "%.2f", avg))g, "
        result += "max=\(String(format: "%.2f", max))g, min=\(String(format: "%.2f", min))g\n"
        
        // Detect patterns
        if max > 2.0 && magnitudes.suffix(5).allSatisfy({ $0 < 0.2 }) {
            result += "- Pattern: Impact followed by stillness detected\n"
        }
        
        return result
    }
    
    private static func buildLocationHistory(from snapshots: [LocationSnapshot]) -> String {
        guard snapshots.count >= 2 else { return "" }
        
        let recent = Array(snapshots.suffix(10))
        let speeds = recent.compactMap { $0.speed }.filter { $0 >= 0 }
        
        if !speeds.isEmpty {
            let avgSpeed = speeds.reduce(0, +) / Double(speeds.count)
            return "- Average Speed: \(String(format: "%.1f", avgSpeed * 2.237)) mph\n"
        }
        return ""
    }
    
    private static func formatTimeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 {
            return "\(seconds)s ago"
        } else if seconds < 3600 {
            return "\(seconds / 60)m ago"
        } else {
            return "\(seconds / 3600)h ago"
        }
    }
    
    private static func loadTrustedContacts() -> [TrustedContact] {
        guard let data = UserDefaults.standard.data(forKey: "trustedContacts"),
              let contacts = try? JSONDecoder().decode([TrustedContact].self, from: data) else {
            return []
        }
        return contacts.filter { $0.isEnabled }
    }
}
