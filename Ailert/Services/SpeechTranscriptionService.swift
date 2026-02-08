// SpeechTranscriptionService.swift
// Real-time speech-to-text for emergency coordinator

import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
class SpeechTranscriptionService: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var isTranscribing = false
    @Published private(set) var currentTranscript = ""
    @Published private(set) var recentTranscripts: [TranscriptSegment] = []
    @Published private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    
    // MARK: - Private
    
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private let maxRecentTranscripts = 20
    private var currentSegmentStart: Date?
    
    // MARK: - Singleton
    
    static let shared = SpeechTranscriptionService()
    
    // MARK: - Init
    
    init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        checkAuthorizationStatus()
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.authorizationStatus = status
            }
        }
    }
    
    private func checkAuthorizationStatus() {
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    }
    
    // MARK: - Start/Stop
    
    func startTranscribing() throws {
        guard authorizationStatus == .authorized else {
            throw TranscriptionError.notAuthorized
        }
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw TranscriptionError.recognizerNotAvailable
        }
        
        // Stop any existing session
        stopTranscribing()
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw TranscriptionError.requestCreationFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.addsPunctuation = true
        
        if #available(iOS 16.0, *) {
            recognitionRequest.requiresOnDeviceRecognition = false // Use server for better accuracy
        }
        
        currentSegmentStart = Date()
        
        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognitionResult(result, error: error)
            }
        }
        
        // Set up audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        isTranscribing = true
    }
    
    func stopTranscribing() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Save current segment if we have content
        if !currentTranscript.isEmpty {
            saveCurrentSegment()
        }
        
        isTranscribing = false
    }
    
    // MARK: - Private
    
    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        if let result = result {
            currentTranscript = result.bestTranscription.formattedString
            
            // If we get a final result, save the segment and start fresh
            if result.isFinal {
                saveCurrentSegment()
                currentTranscript = ""
                currentSegmentStart = Date()
            }
        }
        
        if error != nil {
            // Attempt to restart if there was an error but we should be transcribing
            if isTranscribing {
                stopTranscribing()
                try? startTranscribing()
            }
        }
    }
    
    private func saveCurrentSegment() {
        guard !currentTranscript.isEmpty else { return }
        
        let segment = TranscriptSegment(
            text: currentTranscript,
            startTime: currentSegmentStart ?? Date(),
            endTime: Date()
        )
        
        recentTranscripts.append(segment)
        
        // Keep only recent transcripts
        if recentTranscripts.count > maxRecentTranscripts {
            recentTranscripts.removeFirst()
        }
    }
    
    // MARK: - Context for LLM
    
    func getRecentTranscriptsForContext(maxAge: TimeInterval = 120) -> String {
        let cutoff = Date().addingTimeInterval(-maxAge)
        let relevantTranscripts = recentTranscripts.filter { $0.endTime > cutoff }
        
        if relevantTranscripts.isEmpty && currentTranscript.isEmpty {
            return "[No recent speech detected]"
        }
        
        var output: [String] = []
        
        for segment in relevantTranscripts {
            let timeAgo = Int(-segment.endTime.timeIntervalSinceNow)
            output.append("[\(timeAgo)s ago] \"\(segment.text)\"")
        }
        
        if !currentTranscript.isEmpty {
            output.append("[now] \"\(currentTranscript)\"")
        }
        
        return output.joined(separator: "\n")
    }
    
    func clearTranscripts() {
        recentTranscripts.removeAll()
        currentTranscript = ""
    }
}

// MARK: - Models

struct TranscriptSegment: Identifiable {
    let id = UUID()
    let text: String
    let startTime: Date
    let endTime: Date
}

enum TranscriptionError: LocalizedError {
    case notAuthorized
    case recognizerNotAvailable
    case requestCreationFailed
    case audioEngineError
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Speech recognition not authorized"
        case .recognizerNotAvailable: return "Speech recognizer not available"
        case .requestCreationFailed: return "Could not create recognition request"
        case .audioEngineError: return "Audio engine error"
        }
    }
}
