// DuressDetector.swift
// Detects duress situations during cancel flow

import Foundation

class DuressDetector {
    static let shared = DuressDetector()
    
    private init() {}
    
    /// Check if entered PIN indicates duress
    func checkDuress(enteredPIN: String) -> Bool {
        let duressPIN = UserDefaults.standard.string(forKey: "duressPIN") ?? ""
        let cancelPIN = UserDefaults.standard.string(forKey: "cancelPIN") ?? ""
        
        // If duress PIN is set and matches, this is a duress situation
        if !duressPIN.isEmpty && enteredPIN == duressPIN {
            logDuressEvent()
            return true
        }
        
        // If cancel PIN is set and entered PIN doesn't match either, 
        // could indicate tampering or confusion - not duress
        return false
    }
    
    /// Check if cancel behavior seems coerced
    func analyzeCancel(
        timeSinceStart: TimeInterval,
        attemptsCount: Int,
        locationChanged: Bool
    ) -> DuressIndicators {
        var indicators = DuressIndicators()
        
        // Very fast cancel could indicate coercion
        if timeSinceStart < 5 {
            indicators.suspiciouslyFast = true
        }
        
        // Multiple failed attempts
        if attemptsCount > 2 {
            indicators.multipleFailedAttempts = true
        }
        
        // Location changed significantly during cancel
        if locationChanged {
            indicators.locationChanged = true
        }
        
        return indicators
    }
    
    private func logDuressEvent() {
        AuditLogger.shared.log(event: .duressDetected, incidentId: nil)
    }
}

struct DuressIndicators {
    var suspiciouslyFast = false
    var multipleFailedAttempts = false
    var locationChanged = false
    var voicePatternAbnormal = false
    
    var riskLevel: DuressRiskLevel {
        let count = [suspiciouslyFast, multipleFailedAttempts, locationChanged, voicePatternAbnormal]
            .filter { $0 }.count
        
        switch count {
        case 0: return .none
        case 1: return .low
        case 2: return .medium
        default: return .high
        }
    }
}

enum DuressRiskLevel {
    case none
    case low
    case medium
    case high
}
