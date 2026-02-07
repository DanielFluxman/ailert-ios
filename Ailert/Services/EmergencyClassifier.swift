// EmergencyClassifier.swift
// On-device AI for emergency classification using Apple frameworks

import Foundation
import AVFoundation
import SoundAnalysis
import NaturalLanguage
import Combine

// MARK: - Emergency Classifier

class EmergencyClassifier: NSObject, ObservableObject {
    static let shared = EmergencyClassifier()
    
    @Published var currentClassification: EmergencyClassification = .unknown
    @Published var confidence: Double = 0.0
    @Published var detectedSounds: [DetectedSound] = []
    @Published var isAnalyzing: Bool = false
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var analysisRequest: SNClassifySoundRequest?
    private var streamAnalyzer: SNAudioStreamAnalyzer?
    
    // Sound categories that indicate emergencies
    private let emergencySounds: [String: EmergencyClassification] = [
        // Medical
        "coughing": .medical,
        "breathing": .medical,
        "heartbeat": .medical,
        "crying": .medical,
        
        // Accidents
        "car_horn": .accident,
        "vehicle": .accident,
        "car": .accident,
        "crash": .accident,
        "glass_breaking": .accident,
        "explosion": .accident,
        
        // Safety threats
        "screaming": .safety,
        "shouting": .safety,
        "gunshot": .safety,
        "siren": .safety,
        "alarm": .safety,
        "dog_barking": .safety
    ]
    
    private override init() {
        super.init()
    }
    
    // MARK: - Start Analysis
    
    func startAnalyzing() {
        guard !isAnalyzing else { return }
        
        do {
            // Configure audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true)
            
            // Create audio engine
            audioEngine = AVAudioEngine()
            guard let audioEngine = audioEngine else { return }
            
            inputNode = audioEngine.inputNode
            guard let inputNode = inputNode else { return }
            
            let format = inputNode.outputFormat(forBus: 0)
            
            // Create sound classification request using Apple's built-in classifier
            if #available(iOS 15.0, *) {
                let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
                request.windowDuration = CMTime(seconds: 1.0, preferredTimescale: 48000)
                request.overlapFactor = 0.5
                analysisRequest = request
            }
            
            // Create stream analyzer
            streamAnalyzer = SNAudioStreamAnalyzer(format: format)
            
            // Add request to analyzer
            if let request = analysisRequest, let analyzer = streamAnalyzer {
                try analyzer.add(request, withObserver: self)
            }
            
            // Install tap on input node
            inputNode.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak self] buffer, time in
                self?.streamAnalyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
            }
            
            // Start audio engine
            try audioEngine.start()
            
            DispatchQueue.main.async {
                self.isAnalyzing = true
            }
            
        } catch {
            print("Failed to start audio analysis: \(error)")
        }
    }
    
    func stopAnalyzing() {
        audioEngine?.stop()
        inputNode?.removeTap(onBus: 0)
        streamAnalyzer?.removeAllRequests()
        
        audioEngine = nil
        inputNode = nil
        streamAnalyzer = nil
        
        DispatchQueue.main.async {
            self.isAnalyzing = false
        }
    }
    
    // MARK: - Text Analysis
    
    func analyzeText(_ text: String) -> EmergencyClassification {
        // Keywords for emergency classification
        let medicalKeywords = ["help", "can't breathe", "heart", "pain", "ambulance", "doctor", "hospital", "injury", "blood", "hurt", "sick", "emergency"]
        let accidentKeywords = ["crash", "accident", "car", "collision", "hit", "wreck", "stuck", "fire", "trapped"]
        let safetyKeywords = ["help", "following", "scared", "danger", "threat", "attack", "weapon", "gun", "knife", "stop", "leave me alone", "stalking"]
        
        let lowercaseText = text.lowercased()
        
        var scores: [EmergencyClassification: Int] = [:]
        
        for keyword in medicalKeywords where lowercaseText.contains(keyword) {
            scores[.medical, default: 0] += 1
        }
        
        for keyword in accidentKeywords where lowercaseText.contains(keyword) {
            scores[.accident, default: 0] += 1
        }
        
        for keyword in safetyKeywords where lowercaseText.contains(keyword) {
            scores[.safety, default: 0] += 1
        }
        
        // Use NaturalLanguage for sentiment analysis
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        
        if let sentiment = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore).0 {
            if let score = Double(sentiment.rawValue), score < -0.5 {
                // Strong negative sentiment suggests distress
                scores[.safety, default: 0] += 2
            }
        }
        
        // Return classification with highest score
        if let (classification, _) = scores.max(by: { $0.value < $1.value }) {
            return classification
        }
        
        return .unknown
    }
}

// MARK: - Sound Analysis Observer

extension EmergencyClassifier: SNResultsObserving {
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        
        // Get top classifications
        let topClassifications = result.classifications.prefix(5)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update detected sounds
            self.detectedSounds = topClassifications.compactMap { classification in
                guard classification.confidence > 0.3 else { return nil }
                return DetectedSound(
                    identifier: classification.identifier,
                    confidence: classification.confidence,
                    timestamp: Date()
                )
            }
            
            // Check for emergency sounds
            for classification in topClassifications {
                if classification.confidence > 0.5,
                   let emergencyType = self.emergencySounds[classification.identifier] {
                    self.currentClassification = emergencyType
                    self.confidence = Double(classification.confidence)
                    
                    // Post notification for emergency detection
                    NotificationCenter.default.post(
                        name: .emergencySoundDetected,
                        object: nil,
                        userInfo: [
                            "classification": emergencyType,
                            "sound": classification.identifier,
                            "confidence": classification.confidence
                        ]
                    )
                    break
                }
            }
        }
    }
    
    func request(_ request: SNRequest, didFailWithError error: Error) {
        print("Sound analysis failed: \(error)")
        DispatchQueue.main.async {
            self.isAnalyzing = false
        }
    }
    
    func requestDidComplete(_ request: SNRequest) {
        // Analysis completed
    }
}

// MARK: - Detected Sound

struct DetectedSound: Identifiable {
    let id = UUID()
    let identifier: String
    let confidence: Double
    let timestamp: Date
    
    var displayName: String {
        identifier.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let emergencySoundDetected = Notification.Name("emergencySoundDetected")
}
