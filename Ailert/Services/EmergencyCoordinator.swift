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
    private let observationLogEverySnapshots = 5
    private var snapshotsSinceLastObservationLog = 0
    
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
        snapshotsSinceLastObservationLog = 0
        
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

    func updateIncidentContext(_ incident: Incident) {
        guard currentIncident?.id == incident.id else { return }
        currentIncident = incident
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

        snapshotsSinceLastObservationLog += 1
        guard snapshotsSinceLastObservationLog >= observationLogEverySnapshots else { return }
        snapshotsSinceLastObservationLog = 0

        addTranscriptEntry(
            type: .observation,
            content: buildSensorObservationSummary(from: snapshot)
        )
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

        let detectedSounds = classifier?.detectedSounds ?? []
        if let latestSnapshot = recentSensorSnapshots.last {
            addTranscriptEntry(
                type: .observation,
                content: buildSensorObservationSummary(from: latestSnapshot)
            )
        }

        let candidateActions = inferCandidateActions(
            incident: incident,
            latestSnapshot: recentSensorSnapshots.last,
            motionPattern: sensorEngine.currentMotionPattern,
            detectedSounds: detectedSounds,
            currentLocation: sensorEngine.currentLocation
        )
        addTranscriptEntry(
            type: .analysis,
            content: formatCandidateActions(candidateActions)
        )

        let contextPrompt = LLMContextBuilder.buildContextPrompt(
            incident: incident,
            recentSensorData: recentSensorSnapshots,
            motionPattern: sensorEngine.currentMotionPattern,
            detectedSounds: detectedSounds,
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
                addTranscriptEntry(
                    type: .error,
                    content: "Could not parse LLM response. Continuing with sensor monitoring."
                )
            }

        } catch {
            lastError = error.localizedDescription
            addTranscriptEntry(
                type: .error,
                content: "Analysis error: \(error.localizedDescription). Using sensor-only monitoring."
            )
        }
        
        if state == .analyzing {
            state = .listening
        }
    }
    
    // MARK: - Private - Response Parsing
    
    private func parseDecision(from response: String) -> LLMDecision? {
        for candidate in extractJSONObjectCandidates(from: response) {
            guard let data = candidate.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let certainty = parseDoubleValue(json["certainty"]),
                  let reasoning = json["reasoning"] as? String else {
                continue
            }

            let actionType = parseActionType(json["action"])
            let message = json["message"] as? String

            return LLMDecision(
                actionType: actionType,
                reasoning: reasoning,
                certainty: certainty,
                suggestedMessage: message
            )
        }

        return nil
    }
    
    // MARK: - Private - Decision Handling
    
    private func handleDecision(_ decision: LLMDecision) async {
        decisions.append(decision)
        currentDecision = decision

        let confidence = max(0, min(100, Int(decision.certainty * 100)))
        addTranscriptEntry(
            type: .decision,
            content: "Considering action: \(decision.actionType.displayName) (\(confidence)% confidence)"
        )

        // Add to transcript
        addTranscriptEntry(
            type: .decision,
            content: "[\(decision.certaintyLevel.displayName) certainty] \(decision.reasoning)"
        )
        
        // Check if action can be executed autonomously
        if decision.actionType == .noAction {
            // Just observing, no action needed
            addTranscriptEntry(
                type: .analysis,
                content: "Decision: continue monitoring. No immediate intervention."
            )
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

    private struct CandidateAction {
        let actionType: LLMActionType
        let confidence: Double
        let reason: String
    }

    private func buildSensorObservationSummary(from snapshot: SensorSnapshot) -> String {
        var segments: [String] = []

        let motionPattern = sensorEngine?.currentMotionPattern.rawValue ?? MotionPattern.unknown.rawValue
        if let motion = snapshot.motion {
            segments.append("motion \(motionPattern), \(String(format: "%.2f", motion.accelerationMagnitude))g")
        } else {
            segments.append("motion \(motionPattern), unavailable")
        }

        if let audio = snapshot.audio {
            let voice = audio.hasVoiceActivity ? ", voice activity" : ""
            segments.append(
                "audio avg \(String(format: "%.1f", audio.averageDecibels))dB peak \(String(format: "%.1f", audio.peakDecibels))dB\(voice)"
            )
        } else {
            segments.append("audio unavailable")
        }

        if let location = sensorEngine?.currentLocation {
            let speedText = location.speed >= 0
                ? "\(String(format: "%.1f", location.speed * 2.237)) mph"
                : "stationary"
            segments.append("location \(speedText), ±\(Int(location.horizontalAccuracy))m")
        } else {
            segments.append("location unavailable")
        }

        let topSounds = (classifier?.detectedSounds ?? [])
            .sorted(by: { $0.confidence > $1.confidence })
            .prefix(2)

        if !topSounds.isEmpty {
            let sounds = topSounds.map { "\($0.displayName) \(Int($0.confidence * 100))%" }.joined(separator: ", ")
            segments.append("sound classes: \(sounds)")
        }

        return "Sensors: " + segments.joined(separator: " | ")
    }

    private func inferCandidateActions(
        incident: Incident,
        latestSnapshot: SensorSnapshot?,
        motionPattern: MotionPattern,
        detectedSounds: [DetectedSound],
        currentLocation: CLLocation?
    ) -> [CandidateAction] {
        var candidates: [CandidateAction] = []

        if let motion = latestSnapshot?.motion {
            if motion.accelerationMagnitude >= 2.0 || motionPattern == .impact || motionPattern == .falling {
                candidates.append(
                    CandidateAction(
                        actionType: .captureEvidence,
                        confidence: 0.7,
                        reason: "high-impact movement detected (\(String(format: "%.2f", motion.accelerationMagnitude))g)"
                    )
                )

                if incident.liveShareSession?.isActive != true {
                    candidates.append(
                        CandidateAction(
                            actionType: .shareLocation,
                            confidence: 0.65,
                            reason: "impact-like motion while location sharing is off"
                        )
                    )
                }
            }
        }

        if let audio = latestSnapshot?.audio {
            if audio.peakDecibels > -15 {
                candidates.append(
                    CandidateAction(
                        actionType: .suggestAction,
                        confidence: 0.5,
                        reason: "loud audio spike (\(String(format: "%.1f", audio.peakDecibels))dB)"
                    )
                )
            }

            if audio.hasVoiceActivity && audio.averageDecibels > -30 {
                candidates.append(
                    CandidateAction(
                        actionType: .notifyContacts,
                        confidence: 0.78,
                        reason: "sustained voice activity during active incident"
                    )
                )
            }
        }

        for sound in detectedSounds where sound.confidence >= 0.65 {
            let soundId = sound.identifier.lowercased()
            if soundId.contains("gunshot") || soundId.contains("explosion") {
                candidates.append(
                    CandidateAction(
                        actionType: .escalateToServices,
                        confidence: 0.96,
                        reason: "critical sound class detected (\(sound.displayName))"
                    )
                )
            } else if soundId.contains("scream") || soundId.contains("shouting") || soundId.contains("alarm") {
                candidates.append(
                    CandidateAction(
                        actionType: .notifyContacts,
                        confidence: 0.84,
                        reason: "distress sound detected (\(sound.displayName))"
                    )
                )
            }
        }

        if let location = currentLocation,
           location.speed >= 0,
           location.speed * 2.237 >= 45,
           motionPattern == .impact {
            candidates.append(
                CandidateAction(
                    actionType: .notifyContacts,
                    confidence: 0.88,
                    reason: "high-speed movement followed by impact pattern"
                )
            )
        }

        if candidates.isEmpty {
            candidates.append(
                CandidateAction(
                    actionType: .noAction,
                    confidence: 0.4,
                    reason: "no high-risk signals in current sensor window"
                )
            )
        }

        var highestByAction: [LLMActionType: CandidateAction] = [:]
        for candidate in candidates {
            if let existing = highestByAction[candidate.actionType], existing.confidence >= candidate.confidence {
                continue
            }
            highestByAction[candidate.actionType] = candidate
        }

        return highestByAction.values.sorted(by: { $0.confidence > $1.confidence }).prefix(3).map { $0 }
    }

    private func formatCandidateActions(_ candidates: [CandidateAction]) -> String {
        let formatted = candidates.map { candidate in
            let confidence = max(0, min(100, Int(candidate.confidence * 100)))
            return "\(candidate.actionType.displayName) (\(confidence)%): \(candidate.reason)"
        }
        return "Considering actions: " + formatted.joined(separator: " | ")
    }

    private func extractJSONObjectCandidates(from response: String) -> [String] {
        var candidates: [String] = []
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            candidates.append(trimmed)
        }

        if let regex = try? NSRegularExpression(
            pattern: "```(?:json)?\\s*(\\{[\\s\\S]*?\\})\\s*```",
            options: [.caseInsensitive]
        ) {
            let matches = regex.matches(in: response, range: NSRange(response.startIndex..., in: response))
            for match in matches {
                guard match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: response) else { continue }
                candidates.append(String(response[range]))
            }
        }

        var depth = 0
        var startIndex: String.Index?
        for index in response.indices {
            let character = response[index]
            if character == "{" {
                if depth == 0 {
                    startIndex = index
                }
                depth += 1
            } else if character == "}" {
                guard depth > 0 else { continue }
                depth -= 1
                if depth == 0, let start = startIndex {
                    let next = response.index(after: index)
                    candidates.append(String(response[start..<next]))
                    startIndex = nil
                }
            }
        }

        var seen = Set<String>()
        var deduplicated: [String] = []
        for candidate in candidates where seen.insert(candidate).inserted {
            deduplicated.append(candidate)
        }
        return deduplicated
    }

    private func parseDoubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    private func parseActionType(_ value: Any?) -> LLMActionType {
        guard let rawAction = value as? String else { return .noAction }
        if let direct = LLMActionType(rawValue: rawAction) {
            return direct
        }

        let normalized = rawAction
            .lowercased()
            .replacingOccurrences(of: "[^a-z]", with: "", options: .regularExpression)

        switch normalized {
        case "sharelocation", "locationshare", "sharelive":
            return .shareLocation
        case "notifycontacts", "contacttrustedcontacts", "alertcontacts":
            return .notifyContacts
        case "escalatetoservices", "call911", "contactemergencyservices":
            return .escalateToServices
        case "captureevidence", "takephoto", "startrecording":
            return .captureEvidence
        case "suggestaction", "suggest":
            return .suggestAction
        case "updatestatus", "statusupdate":
            return .updateStatus
        default:
            return .noAction
        }
    }
    
    private func addTranscriptEntry(type: TranscriptEntryType, content: String) {
        let entry = LLMTranscriptEntry(
            type: type,
            content: content
        )
        transcript.append(entry)
        
        // Keep transcript from getting too large
        if transcript.count > 120 {
            transcript.removeFirst(20)
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let llmRequestLocationSharing = Notification.Name("llmRequestLocationSharing")
    static let llmRequestEvidence = Notification.Name("llmRequestEvidence")
}
