// IncidentSessionManager.swift
// Central coordinator for emergency incident sessions

import Foundation
import Combine
import CoreLocation

@MainActor
class IncidentSessionManager: ObservableObject {
    // MARK: - Published State
    @Published private(set) var currentIncident: Incident?
    @Published private(set) var hasActiveIncident: Bool = false
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var currentClassification: EmergencyClassification = .unknown
    @Published private(set) var currentConfidence: Double = 0.0
    @Published private(set) var isVideoRecording: Bool = false
    @Published private(set) var videoRecordingDuration: TimeInterval = 0
    @Published private(set) var liveAudioDecibels: Float = -120
    @Published private(set) var sensorSnapshotCount: Int = 0
    @Published private(set) var isDualCameraCaptureActive: Bool = false
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var isLiveSharing: Bool = false
    @Published private(set) var liveShareURL: URL?
    
    // LLM Coordinator State
    @Published private(set) var isCoordinatorEnabled: Bool = false
    @Published private(set) var coordinatorState: CoordinatorState = .idle
    @Published private(set) var coordinatorTranscript: [LLMTranscriptEntry] = []
    @Published private(set) var pendingCoordinatorAction: LLMDecision?
    
    // MARK: - Services
    private let sensorFusion: SensorFusionEngine
    private let escalationEngine: EscalationEngine
    private let videoRecorder: VideoRecorder
    private let reportGenerator: IncidentReportGenerator
    private let auditLogger: AuditLogger
    private let emergencyCoordinator: EmergencyCoordinator
    
    // MARK: - Timers
    private var sessionTimer: Timer?
    private var escalationTimer: Timer?
    private var documentationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Configuration
    private let autoEscalationSeconds: TimeInterval = 60
    
    init() {
        self.sensorFusion = SensorFusionEngine()
        self.escalationEngine = EscalationEngine()
        self.videoRecorder = VideoRecorder()
        self.reportGenerator = IncidentReportGenerator()
        self.auditLogger = AuditLogger.shared
        self.emergencyCoordinator = EmergencyCoordinator()
        
        // Check if coordinator is enabled in settings
        self.isCoordinatorEnabled = UserDefaults.standard.bool(forKey: "llmCoordinatorEnabled")

        bindServicePublishers()
        bindCoordinatorPublishers()
        setupCoordinatorNotifications()
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
        currentClassification = incident.classification
        currentConfidence = incident.confidence
        sensorSnapshotCount = 0
        
        // Start timers
        startSessionTimer()
        startEscalationTimer()
        startDocumentationTimer()
        
        // Start live data collection and evidence capture
        sensorFusion.startMonitoring()
        startAutomaticDocumentation()
        
        // Start LLM coordinator if enabled
        if isCoordinatorEnabled {
            emergencyCoordinator.startCoordinating(
                for: incident,
                sensorEngine: sensorFusion,
                escalationEngine: escalationEngine,
                classifier: EmergencyClassifier.shared
            )
        }

        // Log audit event
        auditLogger.log(event: .sessionStarted, incidentId: incident.id)
    }
    
    func updateClassification(_ classification: EmergencyClassification) {
        guard var incident = currentIncident else { return }
        incident.classification = classification
        currentClassification = classification
        
        let event = IncidentEvent(
            type: .classificationUpdated,
            description: "Classification changed to \(classification.displayName)"
        )
        incident.events.append(event)
        currentIncident = incident
        saveIncident(incident)
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

        finalizeDocumentation(for: incident) { [weak self] finalizedIncident in
            guard let self = self else { return }
            self.saveIncident(finalizedIncident)
            self.stopSession()
        }
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

        finalizeDocumentation(for: incident) { [weak self] finalizedIncident in
            guard let self = self else { return }

            let report = self.reportGenerator.generateReport(for: finalizedIncident)
            _ = self.reportGenerator.saveReport(report)
            self.saveIncident(finalizedIncident)
            self.stopSession()
        }
    }
    
    // MARK: - Video Recording
    
    func startVideoRecording(camera: CameraPosition = .back) {
        guard var incident = currentIncident else { return }
        
        let started = videoRecorder.startRecording(camera: camera)
        let event: IncidentEvent
        if started {
            let modeDescription = videoRecorder.isDualCameraEnabled ? "front + back cameras" : (camera == .front ? "front camera" : "back camera")
            event = IncidentEvent(
                type: .videoRecordingStarted,
                description: "Video recording started (\(modeDescription))"
            )
        } else {
            event = IncidentEvent(
                type: .userAction,
                description: "Video recording failed to start: \(videoRecorder.lastError ?? "unknown error")"
            )
        }
        incident.events.append(event)
        currentIncident = incident
        saveIncident(incident)
    }
    
    func stopVideoRecording() {
        guard currentIncident != nil else { return }

        videoRecorder.stopRecording { [weak self] captures in
            guard let self = self else { return }
            guard var incident = self.currentIncident else { return }

            if captures.isEmpty {
                incident.events.append(
                    IncidentEvent(type: .userAction, description: "Video stop requested, but recorder was not active")
                )
            } else {
                incident.mediaCaptures.append(contentsOf: captures)
                incident.events.append(
                    IncidentEvent(type: .videoRecordingStopped, description: "\(captures.count) video stream(s) saved locally")
                )
                incident.events.append(
                    IncidentEvent(type: .audioDetected, description: "Audio saved in local recording")
                )
            }

            self.currentIncident = incident
            self.saveIncident(incident)
        }
    }

    func switchCamera() {
        videoRecorder.switchCamera()
    }
    
    func capturePhoto() {
        guard currentIncident != nil else { return }
        
        videoRecorder.capturePhoto { [weak self] capture in
            guard let self = self else { return }
            guard var incident = self.currentIncident else { return }

            if let capture = capture {
                incident.mediaCaptures.append(capture)
                incident.events.append(
                    IncidentEvent(type: .photoTaken, description: "Photo captured")
                )
            } else {
                incident.events.append(
                    IncidentEvent(type: .userAction, description: "Photo capture failed")
                )
            }

            self.currentIncident = incident
            self.saveIncident(incident)
        }
    }

    func startLiveLocationSharing() {
        guard var incident = currentIncident else { return }
        guard incident.liveShareSession?.isActive != true else { return }

        let prefs = loadLiveSharePreferences()
        guard prefs.shareEnabled else {
            incident.events.append(
                IncidentEvent(type: .userAction, description: "Live sharing is disabled in Settings")
            )
            currentIncident = incident
            saveIncident(incident)
            return
        }

        let session = LiveLocationService.shared.startLiveShareSession(
            for: incident,
            includeMediaMetadata: prefs.includeMediaMetadata,
            autoNotifyContacts: prefs.autoNotifyContacts
        )

        // Preserve any media that was captured while we were setting up the session
        if let storedIncident = IncidentStore.shared.load(id: incident.id) {
            incident.mediaCaptures = storedIncident.mediaCaptures
        }

        incident.liveShareSession = session
        incident.events.append(
            IncidentEvent(type: .locationUpdated, description: "Live tracker started: \(session.shareURL.absoluteString)")
        )

        currentIncident = incident
        isLiveSharing = true
        liveShareURL = session.shareURL
        saveIncident(incident)

        if prefs.autoNotifyContacts {
            Task {
                await escalationEngine.notifyContactsWithLiveTracker(
                    incident: incident,
                    shareSession: session,
                    location: currentLocation
                )
            }
        }
    }

    func stopLiveLocationSharing() {
        guard var incident = currentIncident,
              let session = incident.liveShareSession,
              session.isActive else { return }

        let endedSession = LiveLocationService.shared.stopLiveShareSession(session)
        incident.liveShareSession = endedSession
        incident.events.append(
            IncidentEvent(type: .locationUpdated, description: "Live tracker stopped")
        )

        currentIncident = incident
        isLiveSharing = false
        liveShareURL = nil
        saveIncident(incident)
    }

    func locationShareMessage() -> String? {
        guard let incident = currentIncident, let location = currentLocation else { return nil }
        return LiveLocationService.shared.generateLocationMessage(
            for: incident,
            location: location,
            liveShareURL: incident.liveShareSession?.shareURL
        )
    }
    
    // MARK: - Private Helpers

    private func bindServicePublishers() {
        videoRecorder.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.isVideoRecording = $0 }
            .store(in: &cancellables)

        videoRecorder.$currentDuration
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.videoRecordingDuration = $0 }
            .store(in: &cancellables)

        videoRecorder.$isDualCameraEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.isDualCameraCaptureActive = $0 }
            .store(in: &cancellables)

        sensorFusion.$lastAudioData
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.liveAudioDecibels = $0?.averageDecibels ?? -120
            }
            .store(in: &cancellables)

        sensorFusion.$currentLocation
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.currentLocation = $0 }
            .store(in: &cancellables)
    }

    private func startAutomaticDocumentation() {
        guard var incident = currentIncident else { return }

        if videoRecorder.startRecording(camera: .back) {
            incident.events.append(
                IncidentEvent(
                    type: .videoRecordingStarted,
                    description: videoRecorder.isDualCameraEnabled ? "Auto-recording started (front + back cameras)" : "Auto-recording started (back camera)"
                )
            )
        } else {
            incident.events.append(
                IncidentEvent(
                    type: .userAction,
                    description: "Auto-recording failed: \(videoRecorder.lastError ?? "unknown error")"
                )
            )
        }

        incident.events.append(
            IncidentEvent(type: .audioDetected, description: "Live audio monitoring started")
        )

        currentIncident = incident
        saveIncident(incident)
    }
    
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

    private func startDocumentationTimer() {
        documentationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.persistDocumentationSnapshot()
            }
        }
    }

    private func persistDocumentationSnapshot() {
        guard var incident = currentIncident else { return }

        let snapshot = sensorFusion.generateSnapshot()
        incident.sensorSnapshots.append(snapshot)

        if incident.sensorSnapshots.count > 3600 {
            incident.sensorSnapshots.removeFirst(incident.sensorSnapshots.count - 3600)
        }

        if let locationSnapshot = sensorFusion.lastLocationSnapshot {
            if incident.locationSnapshots.last?.timestamp != locationSnapshot.timestamp {
                incident.locationSnapshots.append(locationSnapshot)
            }
        }

        if incident.locationSnapshots.count > 3600 {
            incident.locationSnapshots.removeFirst(incident.locationSnapshots.count - 3600)
        }

        if let session = incident.liveShareSession, session.isActive {
            let audio = liveAudioDecibels > -120 ? liveAudioDecibels : nil
            let updatedSession = LiveLocationService.shared.updateLiveShareSession(
                session,
                location: currentLocation,
                audioDecibels: audio
            )
            incident.liveShareSession = updatedSession
            liveShareURL = updatedSession.shareURL
            isLiveSharing = true
        }

        sensorSnapshotCount = incident.sensorSnapshots.count
        currentIncident = incident
        saveIncident(incident)
    }
    
    private func autoEscalate() {
        guard let incident = currentIncident, incident.escalationLevel == .none else { return }
        escalate(to: .trustedContacts)
    }

    private func finalizeDocumentation(for incident: Incident, completion: @escaping (Incident) -> Void) {
        var finalizedIncident = incident

        if let snapshot = sensorFusion.lastSensorSnapshot {
            finalizedIncident.sensorSnapshots.append(snapshot)
        } else {
            finalizedIncident.sensorSnapshots.append(sensorFusion.generateSnapshot())
        }

        if let locationSnapshot = sensorFusion.lastLocationSnapshot {
            if finalizedIncident.locationSnapshots.last?.timestamp != locationSnapshot.timestamp {
                finalizedIncident.locationSnapshots.append(locationSnapshot)
            }
        }

        if let session = finalizedIncident.liveShareSession, session.isActive {
            finalizedIncident.liveShareSession = LiveLocationService.shared.stopLiveShareSession(session)
        }

        videoRecorder.stopRecording { captures in
            var completedIncident = finalizedIncident

            if !captures.isEmpty {
                completedIncident.mediaCaptures.append(contentsOf: captures)
                completedIncident.events.append(
                    IncidentEvent(type: .videoRecordingStopped, description: "\(captures.count) video stream(s) saved locally")
                )
                completedIncident.events.append(
                    IncidentEvent(type: .audioDetected, description: "Audio saved in local video track")
                )
            }

            completion(completedIncident)
        }
    }
    
    private func stopSession() {
        sessionTimer?.invalidate()
        escalationTimer?.invalidate()
        documentationTimer?.invalidate()
        sessionTimer = nil
        escalationTimer = nil
        documentationTimer = nil
        
        sensorFusion.stopMonitoring()
        LiveLocationService.shared.stopSharing()
        emergencyCoordinator.stopCoordinating()
        
        currentIncident = nil
        hasActiveIncident = false
        elapsedTime = 0
        isVideoRecording = false
        videoRecordingDuration = 0
        isDualCameraCaptureActive = false
        isLiveSharing = false
        liveShareURL = nil
        sensorSnapshotCount = 0
        liveAudioDecibels = -120
        coordinatorState = .idle
        coordinatorTranscript.removeAll()
        pendingCoordinatorAction = nil
        escalationEngine.reset()
    }

    private func loadLiveSharePreferences() -> (shareEnabled: Bool, autoNotifyContacts: Bool, includeMediaMetadata: Bool) {
        let defaults = UserDefaults.standard
        let shareEnabled = defaults.object(forKey: "shareLiveTrackerWithContacts") as? Bool ?? true
        let autoNotifyContacts = defaults.object(forKey: "autoNotifyContactsOnLiveShare") as? Bool ?? true
        let includeMediaMetadata = defaults.object(forKey: "includeLiveMediaMetadata") as? Bool ?? true
        return (shareEnabled, autoNotifyContacts, includeMediaMetadata)
    }
    
    private func saveIncident(_ incident: Incident) {
        IncidentStore.shared.save(incident)
    }
    
    // MARK: - Coordinator Integration
    
    private func bindCoordinatorPublishers() {
        emergencyCoordinator.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.coordinatorState = $0 }
            .store(in: &cancellables)
        
        emergencyCoordinator.$transcript
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.coordinatorTranscript = $0 }
            .store(in: &cancellables)
        
        emergencyCoordinator.$pendingConfirmation
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.pendingCoordinatorAction = $0 }
            .store(in: &cancellables)
    }
    
    private func setupCoordinatorNotifications() {
        NotificationCenter.default.addObserver(
            forName: .llmRequestLocationSharing,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let incidentId = notification.userInfo?["incidentId"] as? UUID,
                  self?.currentIncident?.id == incidentId else { return }
            self?.startLiveLocationSharing()
            
            // Log the LLM-triggered action
            if var incident = self?.currentIncident {
                incident.events.append(
                    IncidentEvent(type: .llmLocationShareTriggered, description: "AI coordinator enabled live location sharing")
                )
                self?.currentIncident = incident
                self?.saveIncident(incident)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .llmRequestEvidence,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let incidentId = notification.userInfo?["incidentId"] as? UUID,
                  self?.currentIncident?.id == incidentId else { return }
            self?.capturePhoto()
        }
    }
    
    func setCoordinatorEnabled(_ enabled: Bool) {
        isCoordinatorEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "llmCoordinatorEnabled")
        
        if enabled, hasActiveIncident, let incident = currentIncident {
            emergencyCoordinator.startCoordinating(
                for: incident,
                sensorEngine: sensorFusion,
                escalationEngine: escalationEngine,
                classifier: EmergencyClassifier.shared
            )
        } else if !enabled {
            emergencyCoordinator.stopCoordinating()
        }
    }
    
    func confirmCoordinatorAction() {
        emergencyCoordinator.confirmPendingAction()
    }
    
    func cancelCoordinatorAction() {
        emergencyCoordinator.cancelPendingAction()
    }
}

// MARK: - Camera Position

enum CameraPosition {
    case front
    case back
}
