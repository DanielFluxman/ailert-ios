// IncidentSessionManager.swift
// Central coordinator for emergency incident sessions

import Foundation
import Combine

@MainActor
class IncidentSessionManager: ObservableObject {
    // MARK: - Published State
    @Published private(set) var currentIncident: Incident?
    @Published private(set) var hasActiveIncident: Bool = false
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var currentClassification: EmergencyClassification = .unknown
    @Published private(set) var currentConfidence: Double = 0.0
    
    // MARK: - Services
    private let sensorFusion: SensorFusionEngine
    private let escalationEngine: EscalationEngine
    private let videoRecorder: VideoRecorder
    private let reportGenerator: IncidentReportGenerator
    private let auditLogger: AuditLogger
    
    // MARK: - Timers
    private var sessionTimer: Timer?
    private var escalationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Configuration
    private let cancelWindowSeconds: TimeInterval = 30
    private let autoEscalationSeconds: TimeInterval = 60
    
    init() {
        self.sensorFusion = SensorFusionEngine()
        self.escalationEngine = EscalationEngine()
        self.videoRecorder = VideoRecorder()
        self.reportGenerator = IncidentReportGenerator()
        self.auditLogger = AuditLogger()
    }
    
    // MARK: - Session Control
    
    func startSession(classification: EmergencyClassification? = nil) {
        guard currentIncident == nil else { return }
        
        var incident = Incident()
        if let classification = classification {
            incident.classification = classification
        }
        
        let event = IncidentEvent(
            type: .sessionStarted,
            description: "Emergency session started"
        )
        incident.events.append(event)
        
        currentIncident = incident
        hasActiveIncident = true
        
        // Start timers
        startSessionTimer()
        startEscalationTimer()
        
        // Start sensor collection
        sensorFusion.startMonitoring()
        
        // Log audit event
        auditLogger.log(event: .sessionStarted, incidentId: incident.id)
    }
    
    func cancelSession(pin: String? = nil) {
        guard var incident = currentIncident else { return }
        
        // Check for duress (wrong PIN)
        if let pin = pin {
            let isDuress = DuressDetector.shared.checkDuress(enteredPIN: pin)
            if isDuress {
                // Silent escalation - don't show user
                incident.status = .duress
                escalationEngine.silentEscalate(incident: incident)
                auditLogger.log(event: .duressDetected, incidentId: incident.id)
            } else {
                incident.status = .cancelled
            }
        } else {
            incident.status = .cancelled
        }
        
        let event = IncidentEvent(
            type: .sessionCancelled,
            description: incident.status == .duress ? "Session ended (duress detected)" : "Session cancelled by user"
        )
        incident.events.append(event)
        incident.sessionEnd = Date()
        
        // Save incident to history
        saveIncident(incident)
        
        stopSession()
    }
    
    func escalate(to level: EscalationLevel) {
        guard var incident = currentIncident else { return }
        
        incident.escalationLevel = level
        let event = IncidentEvent(
            type: .sessionEscalated,
            description: "Escalated to \(level.displayName)"
        )
        incident.events.append(event)
        
        currentIncident = incident
        
        // Trigger escalation actions
        Task {
            await escalationEngine.escalate(incident: incident, to: level)
        }
        
        auditLogger.log(event: .escalated(level: level), incidentId: incident.id)
    }
    
    func resolveSession() {
        guard var incident = currentIncident else { return }
        
        incident.status = .resolved
        incident.sessionEnd = Date()
        
        // Generate report
        let report = reportGenerator.generateReport(for: incident)
        
        // Save incident
        saveIncident(incident)
        
        stopSession()
    }
    
    // MARK: - Video Recording
    
    func startVideoRecording(camera: CameraPosition = .back) {
        guard var incident = currentIncident else { return }
        
        videoRecorder.startRecording(camera: camera)
        
        let event = IncidentEvent(
            type: .videoRecordingStarted,
            description: "Video recording started (\(camera == .front ? "front" : "back") camera)"
        )
        incident.events.append(event)
        currentIncident = incident
    }
    
    func stopVideoRecording() {
        guard var incident = currentIncident else { return }
        
        if let capture = videoRecorder.stopRecording() {
            incident.mediaCaptures.append(capture)
            
            let event = IncidentEvent(
                type: .videoRecordingStopped,
                description: "Video recording saved"
            )
            incident.events.append(event)
            currentIncident = incident
        }
    }
    
    func capturePhoto() {
        guard var incident = currentIncident else { return }
        
        if let capture = videoRecorder.capturePhoto() {
            incident.mediaCaptures.append(capture)
            
            let event = IncidentEvent(
                type: .photoTaken,
                description: "Photo captured"
            )
            incident.events.append(event)
            currentIncident = incident
        }
    }
    
    // MARK: - Private Helpers
    
    private func startSessionTimer() {
        elapsedTime = 0
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsedTime += 1
            }
        }
    }
    
    private func startEscalationTimer() {
        escalationTimer = Timer.scheduledTimer(withTimeInterval: autoEscalationSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.autoEscalate()
            }
        }
    }
    
    private func autoEscalate() {
        guard let incident = currentIncident, incident.escalationLevel == .none else { return }
        escalate(to: .trustedContacts)
    }
    
    private func stopSession() {
        sessionTimer?.invalidate()
        escalationTimer?.invalidate()
        sessionTimer = nil
        escalationTimer = nil
        
        sensorFusion.stopMonitoring()
        videoRecorder.stopRecording()
        
        currentIncident = nil
        hasActiveIncident = false
        elapsedTime = 0
    }
    
    private func saveIncident(_ incident: Incident) {
        IncidentStore.shared.save(incident)
    }
}

// MARK: - Camera Position

enum CameraPosition {
    case front
    case back
}
