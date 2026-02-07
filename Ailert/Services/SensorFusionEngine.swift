// SensorFusionEngine.swift
// Combines data from motion, audio, and location sensors

import Foundation
import CoreMotion
import CoreLocation
import AVFoundation
import Combine

class SensorFusionEngine: NSObject, ObservableObject {
    // MARK: - Published State
    @Published var isMonitoring: Bool = false
    @Published var currentMotionPattern: MotionPattern = .unknown
    @Published var currentLocation: CLLocation?
    @Published var lastSensorSnapshot: SensorSnapshot?
    @Published var lastAudioData: AudioData?
    @Published var lastLocationSnapshot: LocationSnapshot?
    
    // MARK: - Managers
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    private var audioEngine: AVAudioEngine?
    
    // MARK: - Data Buffers
    private var motionBuffer: [MotionData] = []
    private var locationBuffer: [LocationSnapshot] = []
    private let bufferLimit = 100
    
    // MARK: - Configuration
    private let motionUpdateInterval: TimeInterval = 0.1 // 10 Hz
    private let locationUpdateDistance: CLLocationDistance = 5.0 // meters
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    // MARK: - Setup
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = locationUpdateDistance
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
    }
    
    // MARK: - Monitoring Control
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        startMotionUpdates()
        startLocationUpdates()
        startAudioMonitoring()
    }
    
    func stopMonitoring() {
        isMonitoring = false
        
        motionManager.stopDeviceMotionUpdates()
        locationManager.stopUpdatingLocation()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        
        motionBuffer.removeAll()
        locationBuffer.removeAll()
    }
    
    // MARK: - Motion
    
    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        
        motionManager.deviceMotionUpdateInterval = motionUpdateInterval
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }
            
            let data = MotionData(from: motion)
            self.processMotionData(data)
        }
    }
    
    private func processMotionData(_ data: MotionData) {
        // Add to buffer
        motionBuffer.append(data)
        if motionBuffer.count > bufferLimit {
            motionBuffer.removeFirst()
        }
        
        // Detect patterns
        let pattern = detectMotionPattern(from: motionBuffer)
        if pattern != currentMotionPattern {
            currentMotionPattern = pattern
        }
        
        // Check for fall
        if data.accelerationMagnitude > 2.5 {
            // High G-force detected - potential fall or impact
            detectFall(from: motionBuffer)
        }
    }
    
    private func detectMotionPattern(from buffer: [MotionData]) -> MotionPattern {
        guard buffer.count >= 10 else { return .unknown }
        
        let recentData = buffer.suffix(10)
        let avgMagnitude = recentData.map { $0.accelerationMagnitude }.reduce(0, +) / Double(recentData.count)
        
        if avgMagnitude < 0.1 {
            return .stationary
        } else if avgMagnitude < 0.5 {
            return .walking
        } else if avgMagnitude < 1.5 {
            return .running
        } else if avgMagnitude > 2.0 {
            return .impact
        }
        
        return .unknown
    }
    
    private func detectFall(from buffer: [MotionData]) {
        // Simplified fall detection
        // A fall typically shows: high acceleration spike → brief freefall → impact → stillness
        
        guard buffer.count >= 20 else { return }
        
        let recentData = Array(buffer.suffix(20))
        let magnitudes = recentData.map { $0.accelerationMagnitude }
        
        // Check for impact followed by low activity
        let maxMagnitude = magnitudes.max() ?? 0
        let lastFewMagnitudes = magnitudes.suffix(5)
        let avgAfterImpact = lastFewMagnitudes.reduce(0, +) / Double(lastFewMagnitudes.count)
        
        if maxMagnitude > 2.5 && avgAfterImpact < 0.3 {
            // Likely fall detected
            currentMotionPattern = .falling
            NotificationCenter.default.post(name: .fallDetected, object: nil)
        }
    }
    
    // MARK: - Location
    
    private func startLocationUpdates() {
        let status = locationManager.authorizationStatus
        
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
        case .notDetermined:
            locationManager.requestAlwaysAuthorization()
        default:
            break
        }
    }
    
    // MARK: - Audio
    
    private func startAudioMonitoring() {
        let permission = AVAudioSession.sharedInstance().recordPermission
        if permission == .undetermined {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                guard granted else { return }
                DispatchQueue.main.async {
                    self?.startAudioMonitoring()
                }
            }
            return
        }

        guard permission == .granted else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }

        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }
        
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
        
        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        let frameCount = Int(buffer.frameLength)
        var sum: Float = 0
        var peak: Float = 0
        
        for i in 0..<frameCount {
            let sample = abs(channelData[i])
            sum += sample
            if sample > peak { peak = sample }
        }
        
        let average = sum / Float(frameCount)
        let averageDB = 20 * log10(average + 0.0001)
        let peakDB = 20 * log10(peak + 0.0001)

        let audioData = AudioData(
            averageDecibels: averageDB,
            peakDecibels: peakDB,
            hasVoiceActivity: peakDB > -35,
            detectedDistressKeywords: nil
        )

        DispatchQueue.main.async { [weak self] in
            self?.lastAudioData = audioData
        }
    }
    
    // MARK: - Snapshot Generation
    
    func generateSnapshot() -> SensorSnapshot {
        let deviceContext = DeviceContext()
        let motionData = motionBuffer.last

        let snapshot = SensorSnapshot(
            timestamp: Date(),
            motion: motionData,
            audio: lastAudioData,
            deviceContext: deviceContext
        )

        lastSensorSnapshot = snapshot
        return snapshot
    }

    func recentLocationSnapshots() -> [LocationSnapshot] {
        locationBuffer
    }
}

// MARK: - CLLocationManagerDelegate

extension SensorFusionEngine: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        currentLocation = location
        
        let snapshot = LocationSnapshot(from: location)
        locationBuffer.append(snapshot)
        lastLocationSnapshot = snapshot
        if locationBuffer.count > bufferLimit {
            locationBuffer.removeFirst()
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways ||
           manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let fallDetected = Notification.Name("fallDetected")
    static let impactDetected = Notification.Name("impactDetected")
}
