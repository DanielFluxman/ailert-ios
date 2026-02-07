// VolumeButtonTrigger.swift
// Detects rapid volume button presses as discrete SOS trigger

import Foundation
import MediaPlayer
import AVFoundation

class VolumeButtonTrigger: NSObject, ObservableObject {
    @Published var isEnabled = false
    
    private var isObserving = false
    
    private var volumeView: MPVolumeView?
    private var volumeSlider: UISlider?
    private var lastVolume: Float = 0.5
    private var pressCount = 0
    private var lastPressTime: Date?
    
    private let pressWindow: TimeInterval = 2.0
    private var requiredPresses = 5
    private var onTriggered: (() -> Void)?
    
    override init() {
        super.init()
        setupVolumeObserver()
    }
    
    func configure(pressCount: Int) {
        requiredPresses = pressCount
    }
    
    func setCallback(_ callback: @escaping () -> Void) {
        onTriggered = callback
    }
    
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }
    
    private func setupVolumeObserver() {
        // Create hidden volume view
        volumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        
        // Find the volume slider
        for subview in volumeView?.subviews ?? [] {
            if let slider = subview as? UISlider {
                volumeSlider = slider
                break
            }
        }
        
        // Set up audio session
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
    
    func startMonitoring() {
        guard isEnabled, !isObserving else { return }
        
        // Get initial volume
        lastVolume = AVAudioSession.sharedInstance().outputVolume
        
        // Observe volume changes
        AVAudioSession.sharedInstance().addObserver(
            self,
            forKeyPath: "outputVolume",
            options: [.new, .old],
            context: nil
        )
        isObserving = true
    }
    
    func stopMonitoring() {
        guard isObserving else { return }
        AVAudioSession.sharedInstance().removeObserver(self, forKeyPath: "outputVolume")
        isObserving = false
        pressCount = 0
        lastPressTime = nil
    }
    
    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == "outputVolume" {
            handleVolumeChange()
        }
    }
    
    private func handleVolumeChange() {
        let currentVolume = AVAudioSession.sharedInstance().outputVolume
        let now = Date()
        
        // Detect a button press (volume changed)
        if abs(currentVolume - lastVolume) > 0.01 {
            if let lastPress = lastPressTime {
                if now.timeIntervalSince(lastPress) < pressWindow {
                    pressCount += 1
                } else {
                    // Window expired, reset
                    pressCount = 1
                }
            } else {
                pressCount = 1
            }
            
            lastPressTime = now
            
            // Check if triggered
            if pressCount >= requiredPresses {
                triggerSOS()
            }
            
            // Restore volume to prevent audible changes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.volumeSlider?.value = self?.lastVolume ?? 0.5
            }
        }
    }
    
    private func triggerSOS() {
        pressCount = 0
        lastPressTime = nil
        
        DispatchQueue.main.async {
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
            
            self.onTriggered?()
        }
    }
    
    deinit {
        stopMonitoring()
    }
}
