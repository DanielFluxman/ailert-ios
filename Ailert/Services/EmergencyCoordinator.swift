// EmergencyCoordinator.swift
// LLM-powered autonomous emergency coordinator

import Foundation
import Combine
import CoreLocation

@MainActor
class EmergencyCoordinator: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var state: CoordinatorState = .idle
    @Published private(set) var transcript: [LLMTranscriptEntry] = []
    @Published private(set) var decisions: [LLMDecision] = []
    @Published private(set) var currentDecision: LLMDecision?
    @Published private(set) var pendingConfirmation: LLMDecision?
    @Published var lastError: String?
    
    // MARK: - Dependencies
    
    private let llmService: LLMService
    private weak var sensorEngine: SensorFusionEngine?
    private weak var escalationEngine: EscalationEngine?
    private weak var classifier: EmergencyClassifier?
    
    // MARK: - Configuration
    
    private let updateInterval: TimeInterval = 10  // Seconds between LLM updates
    private var currentIncident: Incident?
    private var updateTimer: Timer?
    private var recentSensorSnapshots: [SensorSnapshot] = []
    private let maxSnapshotsInContext = 20
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Init
    
    init(
        llmService: LLMService = .shared,
        sensorEngine: SensorFusionEngine? = nil,
        escalationEngine: EscalationEngine? = nil,
        classifier: EmergencyClassifier? = nil
    ) {
        self.llmService = llmService
        self.sensorEngine = sensorEngine
        self.escalationEngine = escalationEngine
        self.classifier = classifier
    }
    
    // MARK: - Start/Stop Coordination
    
    func startCoordinating(
        for incident: Incident,
        sensorEngine: SensorFusionEngine,
        escalationEngine: EscalationEngine,
        classifier: EmergencyClassifier
    ) {
        self.currentIncident = incident
        self.sensorEngine = sensorEngine
        self.escalationEngine = escalationEngine
        self.classifier = classifier
        
        state = .listening
        transcript.removeAll()
        decisions.removeAll()
        recentSensorSnapshots.removeAll()
        
        addTranscriptEntry(
            type: .observation,
            content: "Emergency Coordinator activated. Monitoring sensors..."
        )
        
        // Subscribe to sensor updates
        bindSensorUpdates()
        
        // Start periodic LLM analysis
        startUpdateTimer()
    }
    
    func stopCoordinating() {
        updateTimer?.invalidate()
        updateTimer = nil
        cancellables.removeAll()
        
        if state.isActive {
            addTranscriptEntry(
                type: .observation,
                content: "Emergency Coordinator deactivated"
            )
        }
        
        state = .idle
        currentIncident = nil
    }
    
    // MARK: - User Confirmation
    
    func confirmPendingAction() {
        guard let pending = pendingConfirmation else { return }
        
        addTranscriptEntry(
            type: .confirmation,
            content: "User confirmed: \(pending.actionType.displayName)"
        )
        
        Task {
            await executeDecision(pending)
        }
        
        pendingConfirmation = nil
        state = .listening
    }
    
    func cancelPendingAction() {
        guard let pending = pendingConfirmation else { return }
        
        addTranscriptEntry(
            type: .confirmation,
            content: "User cancelled: \(pending.actionType.displayName)"
        )
        
        pendingConfirmation = nil
        state = .listening
    }
    
    // MARK: - Private - Sensor Binding
    
    private func bindSensorUpdates() {
        // Collect sensor snapshots
        sensorEngine?.$lastSensorSnapshot
            .compactMap { $0 }
            .sink { [weak self] snapshot in
                self?.collectSnapshot(snapshot)
            }
            .store(in: &cancellables)
    }
    
    private func collectSnapshot(_ snapshot: SensorSnapshot) {
        recentSensorSnapshots.append(snapshot)
        if recentSensorSnapshots.count > maxSnapshotsInContext {
            recentSensorSnapshots.removeFirst()
        }
    }
    
    // MARK: - Private - Update Timer
    
    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performAnalysis()
            }
        }
        
        // First analysis after short delay
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await performAnalysis()
        }
    }
    
    // MARK: - Private - LLM Analysis
    
    private func performAnalysis() async {
        guard state == .listening || state == .analyzing,
              let incident = currentIncident,
              let sensorEngine = sensorEngine else { return }
        
        state = .analyzing
        
        let contextPrompt = LLMContextBuilder.buildContextPrompt(
            incident: incident,
            recentSensorData: recentSensorSnapshots,
            motionPattern: sensorEngine.currentMotionPattern,
            detectedSounds: classifier?.detectedSounds ?? [],
            currentLocation: sensorEngine.currentLocation,
            previousDecisions: decisions
        )
        
        do {
            let response = try await llmService.complete(
                systemPrompt: LLMContextBuilder.systemPrompt,
                userPrompt: contextPrompt,
                temperature: 0.3  // Lower temperature for more consistent decisions
            )
            
            if let decision = parseDecision(from: response) {
                await handleDecision(decision)
            } else {
                lastError = "Could not parse LLM response"
            }
            
        } catch {
            lastError = error.localizedDescription
            addTranscriptEntry(
                type: .error,
                content: "Analysis error: \(error.localizedDescription)"
            )
        }
        
        if state == .analyzing {
            state = .listening
        }
    }
    
    // MARK: - Private - Response Parsing
    
    private func parseDecision(from response: String) -> LLMDecision? {
        // Try to extract JSON from response
        let jsonPattern = "\\{[^{}]*\\}"
        guard let regex = try? NSRegularExpression(pattern: jsonPattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: response, range: NSRange(response.startIndex..., in: response)),
              let range = Range(match.range, in: response) else {
            return nil
        }
        
        let jsonString = String(response[range])
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        guard let actionStr = json["action"] as? String,
              let certainty = json["certainty"] as? Double,
              let reasoning = json["reasoning"] as? String else {
            return nil
        }
        
        let actionType = LLMActionType(rawValue: actionStr) ?? .noAction
        let message = json["message"] as? String
        
        return LLMDecision(
            actionType: actionType,
            reasoning: reasoning,
            certainty: certainty,
            suggestedMessage: message
        )
    }
    
    // MARK: - Private - Decision Handling
    
    private func handleDecision(_ decision: LLMDecision) async {
        decisions.append(decision)
        currentDecision = decision
        
        // Add to transcript
        addTranscriptEntry(
            type: .decision,
            content: "[\(decision.certaintyLevel.displayName) certainty] \(decision.reasoning)"
        )
        
        // Check if action can be executed autonomously
        if decision.actionType == .noAction {
            // Just observing, no action needed
            return
        }
        
        if decision.canExecuteAutonomously {
            addTranscriptEntry(
                type: .action,
                content: "Executing: \(decision.actionType.displayName)"
            )
            await executeDecision(decision)
        } else if decision.actionType.requiresConfirmation || decision.certaintyLevel < decision.actionType.minimumCertainty {
            // Need user confirmation
            pendingConfirmation = decision
            state = .waitingConfirm
            addTranscriptEntry(
                type: .decision,
                content: "Awaiting confirmation: \(decision.actionType.displayName)"
            )
        }
    }
    
    // MARK: - Private - Action Execution
    
    private func executeDecision(_ decision: LLMDecision) async {
        guard let incident = currentIncident else { return }
        
        state = .acting
        
        switch decision.actionType {
        case .shareLocation:
            // Trigger location sharing via parent manager
            NotificationCenter.default.post(
                name: .llmRequestLocationSharing,
                object: nil,
                userInfo: ["incidentId": incident.id, "decision": decision]
            )
            
        case .notifyContacts:
            await escalationEngine?.escalate(incident: incident, to: .trustedContacts)
            
        case .escalateToServices:
            await escalationEngine?.escalate(incident: incident, to: .emergencyServices)
            
        case .captureEvidence:
            NotificationCenter.default.post(
                name: .llmRequestEvidence,
                object: nil,
                userInfo: ["incidentId": incident.id]
            )
            
        case .suggestAction, .updateStatus, .noAction:
            // Display only, no system action
            break
        }
        
        // Update decision as executed
        if let index = decisions.lastIndex(where: { $0.id == decision.id }) {
            decisions[index] = LLMDecision(
                id: decision.id,
                timestamp: decision.timestamp,
                actionType: decision.actionType,
                reasoning: decision.reasoning,
                certainty: decision.certainty,
                suggestedMessage: decision.suggestedMessage,
                wasExecuted: true
            )
        }
        
        state = .listening
    }
    
    // MARK: - Private - Transcript
    
    private func addTranscriptEntry(type: TranscriptEntryType, content: String) {
        let entry = LLMTranscriptEntry(
            type: type,
            content: content
        )
        transcript.append(entry)
        
        // Keep transcript from getting too large
        if transcript.count > 50 {
            transcript.removeFirst(10)
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let llmRequestLocationSharing = Notification.Name("llmRequestLocationSharing")
    static let llmRequestEvidence = Notification.Name("llmRequestEvidence")
}
