// SensorData.swift
// Models for sensor fusion data

import Foundation
import CoreMotion

struct SensorSnapshot: Codable {
    let timestamp: Date
    let motion: MotionData?
    let audio: AudioData?
    let deviceContext: DeviceContext
}

struct MotionData: Codable {
    let accelerationX: Double
    let accelerationY: Double
    let accelerationZ: Double
    let rotationRateX: Double
    let rotationRateY: Double
    let rotationRateZ: Double
    let attitude: AttitudeData?
    
    var accelerationMagnitude: Double {
        sqrt(accelerationX * accelerationX + 
             accelerationY * accelerationY + 
             accelerationZ * accelerationZ)
    }
    
    init(from deviceMotion: CMDeviceMotion) {
        self.accelerationX = deviceMotion.userAcceleration.x
        self.accelerationY = deviceMotion.userAcceleration.y
        self.accelerationZ = deviceMotion.userAcceleration.z
        self.rotationRateX = deviceMotion.rotationRate.x
        self.rotationRateY = deviceMotion.rotationRate.y
        self.rotationRateZ = deviceMotion.rotationRate.z
        self.attitude = AttitudeData(from: deviceMotion.attitude)
    }
}

struct AttitudeData: Codable {
    let roll: Double
    let pitch: Double
    let yaw: Double
    
    init(from attitude: CMAttitude) {
        self.roll = attitude.roll
        self.pitch = attitude.pitch
        self.yaw = attitude.yaw
    }
}

struct AudioData: Codable {
    let averageDecibels: Float
    let peakDecibels: Float
    let hasVoiceActivity: Bool
    let detectedDistressKeywords: [String]?
}

struct DeviceContext: Codable {
    let batteryLevel: Float
    let batteryState: BatteryState
    let isConnectedToNetwork: Bool
    let networkType: NetworkType
    let timestamp: Date
    
    init() {
        self.batteryLevel = 1.0
        self.batteryState = .unknown
        self.isConnectedToNetwork = true
        self.networkType = .unknown
        self.timestamp = Date()
    }
}

enum BatteryState: String, Codable {
    case unknown
    case unplugged
    case charging
    case full
}

enum NetworkType: String, Codable {
    case wifi
    case cellular
    case none
    case unknown
}

// MARK: - Fall Detection

struct FallEvent: Codable {
    let timestamp: Date
    let impactMagnitude: Double
    let fallDuration: TimeInterval
    let postFallMovement: Bool
    let confidence: Double
}

// MARK: - Motion Patterns

enum MotionPattern: String, Codable {
    case stationary
    case walking
    case running
    case driving
    case falling
    case impact
    case unknown
}
