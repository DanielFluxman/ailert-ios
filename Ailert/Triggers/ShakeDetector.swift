// ShakeDetector.swift
// Detects shake gestures for discrete SOS trigger

import Foundation
import CoreMotion
import SwiftUI

class ShakeDetector: ObservableObject {
    @Published var shakeDetected = false
    
    private let motionManager = CMMotionManager()
    private var shakeCount = 0
    private var lastShakeTime: Date?
    private let requiredShakes = 3
    private let shakeWindow: TimeInterval = 2.0
    private let shakeThreshold: Double = 2.5
    
    private var isEnabled = true
    private var onShakeTriggered: (() -> Void)?
    
    init() {
        setupShakeDetection()
    }
    
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }
    
    func setCallback(_ callback: @escaping () -> Void) {
        onShakeTriggered = callback
    }
    
    private func setupShakeDetection() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 0.1
    }
    
    func startMonitoring() {
        guard isEnabled, motionManager.isAccelerometerAvailable else { return }
        
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self, let data = data else { return }
            self.processAccelerometerData(data)
        }
    }
    
    func stopMonitoring() {
        motionManager.stopAccelerometerUpdates()
        shakeCount = 0
        lastShakeTime = nil
    }
    
    private func processAccelerometerData(_ data: CMAccelerometerData) {
        let acceleration = data.acceleration
        let magnitude = sqrt(
            acceleration.x * acceleration.x +
            acceleration.y * acceleration.y +
            acceleration.z * acceleration.z
        )
        
        // Detect shake (high acceleration)
        if magnitude > shakeThreshold {
            let now = Date()
            
            // Check if within shake window
            if let lastShake = lastShakeTime {
                if now.timeIntervalSince(lastShake) < shakeWindow {
                    shakeCount += 1
                } else {
                    // Window expired, reset
                    shakeCount = 1
                }
            } else {
                shakeCount = 1
            }
            
            lastShakeTime = now
            
            // Check if enough shakes
            if shakeCount >= requiredShakes {
                triggerShake()
            }
        }
    }
    
    private func triggerShake() {
        shakeCount = 0
        lastShakeTime = nil
        
        DispatchQueue.main.async {
            self.shakeDetected = true
            self.onShakeTriggered?()
            
            // Reset after short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.shakeDetected = false
            }
        }
    }
}

// MARK: - SwiftUI Shake Detection Extension

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

// View modifier for shake detection
struct DeviceShakeViewModifier: ViewModifier {
    let action: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                action()
            }
    }
}

extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        self.modifier(DeviceShakeViewModifier(action: action))
    }
}
