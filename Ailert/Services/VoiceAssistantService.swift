// VoiceAssistantService.swift
// AI voice output and real-time conversation handler

import Foundation
import AVFoundation
import Speech
import Combine

@MainActor
class VoiceAssistantService: NSObject, ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var isListening = false
    @Published private(set) var isSpeaking = false
    @Published private(set) var currentTranscript = ""
    @Published private(set) var lastAssistantMessage = ""
    @Published private(set) var conversationLog: [VoiceMessage] = []
    
    // MARK: - Private
    
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 2.0 // Seconds of silence before processing
    private var lastSpeechTime = Date()
    
    weak var delegate: VoiceAssistantDelegate?
    
    // MARK: - Singleton
    
    static let shared = VoiceAssistantService()
    
    // MARK: - Init
    
    override init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        super.init()
        speechSynthesizer.delegate = self
    }
    
    // MARK: - Start/Stop Listening
    
    func startListening() throws {
        guard !isListening else { return }
        
        // Request permission if needed
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        guard authStatus == .authorized else {
            SFSpeechRecognizer.requestAuthorization { _ in }
            throw VoiceAssistantError.notAuthorized
        }
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw VoiceAssistantError.recognizerNotAvailable
        }
        
        // Configure audio session for both input and output
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw VoiceAssistantError.requestCreationFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.addsPunctuation = true
        
        // Start recognition
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
        
        isListening = true
        lastSpeechTime = Date()
        startSilenceTimer()
        
        // Greet the user
        speak("I'm here and listening. Tell me what's happening.")
    }
    
    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        isListening = false
    }
    
    // MARK: - Speech Output
    
    func speak(_ text: String, priority: Bool = false) {
        guard !text.isEmpty else { return }
        
        // Stop current speech if priority
        if priority && isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        // Pause listening while speaking to avoid feedback
        if isListening {
            audioEngine.pause()
        }
        
        lastAssistantMessage = text
        addToConversation(role: .assistant, content: text)
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52 // Slightly faster than default
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        isSpeaking = true
        speechSynthesizer.speak(utterance)
    }
    
    // MARK: - Private - Recognition Handling
    
    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        if let result = result {
            let transcript = result.bestTranscription.formattedString
            
            // Update current transcript
            if transcript != currentTranscript {
                currentTranscript = transcript
                lastSpeechTime = Date()
            }
            
            // If result is final, process it
            if result.isFinal {
                processUserSpeech(transcript)
                currentTranscript = ""
            }
        }
        
        if error != nil && isListening {
            // Restart recognition on error
            restartRecognition()
        }
    }
    
    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForSilence()
            }
        }
    }
    
    private func checkForSilence() {
        guard isListening, !isSpeaking else { return }
        
        let silenceDuration = Date().timeIntervalSince(lastSpeechTime)
        
        // If user has stopped speaking for a moment and we have content, process it
        if silenceDuration >= silenceThreshold && !currentTranscript.isEmpty {
            processUserSpeech(currentTranscript)
            currentTranscript = ""
            lastSpeechTime = Date()
        }
    }
    
    private func processUserSpeech(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        addToConversation(role: .user, content: trimmed)
        
        // Notify delegate to process with LLM
        delegate?.voiceAssistant(self, didReceiveUserSpeech: trimmed)
    }
    
    private func restartRecognition() {
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognitionResult(result, error: error)
            }
        }
    }
    
    // MARK: - Conversation Log
    
    private func addToConversation(role: VoiceMessage.Role, content: String) {
        let message = VoiceMessage(role: role, content: content)
        conversationLog.append(message)
        
        // Keep only recent messages
        if conversationLog.count > 50 {
            conversationLog.removeFirst()
        }
    }
    
    func clearConversation() {
        conversationLog.removeAll()
    }
    
    func getRecentContext(maxMessages: Int = 10) -> String {
        let recent = conversationLog.suffix(maxMessages)
        return recent.map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n")
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension VoiceAssistantService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            
            // Resume listening after speaking
            if isListening {
                try? audioEngine.start()
            }
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = true
        }
    }
}

// MARK: - Models

struct VoiceMessage: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let role: Role
    let content: String
    
    enum Role: String {
        case user = "User"
        case assistant = "Assistant"
    }
}

enum VoiceAssistantError: LocalizedError {
    case notAuthorized
    case recognizerNotAvailable
    case requestCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Speech recognition not authorized"
        case .recognizerNotAvailable: return "Speech recognizer not available"
        case .requestCreationFailed: return "Could not create recognition request"
        }
    }
}

// MARK: - Delegate Protocol

@MainActor
protocol VoiceAssistantDelegate: AnyObject {
    func voiceAssistant(_ assistant: VoiceAssistantService, didReceiveUserSpeech text: String)
}
