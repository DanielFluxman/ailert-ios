// VideoRecorder.swift
// Handles video and photo capture during incidents

import Foundation
import AVFoundation
import UIKit

class VideoRecorder: NSObject, ObservableObject {
    // MARK: - Published State
    @Published var isRecording: Bool = false
    @Published var currentDuration: TimeInterval = 0
    @Published var currentCamera: CameraPosition = .back
    @Published var isAuthorized: Bool = false
    
    // MARK: - Capture Session
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureMovieFileOutput?
    private var photoOutput: AVCapturePhotoOutput?
    private var currentVideoURL: URL?
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    
    // MARK: - Configuration
    private let maxSegmentDuration: TimeInterval = 300 // 5 minutes
    
    override init() {
        super.init()
        checkAuthorization()
    }
    
    // MARK: - Authorization
    
    private func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            setupCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted {
                        self?.setupCaptureSession()
                    }
                }
            }
        default:
            isAuthorized = false
        }
    }
    
    // MARK: - Setup
    
    private func setupCaptureSession() {
        let session = AVCaptureSession()
        session.sessionPreset = .high
        
        // Add video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            return
        }
        
        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        }
        
        // Add audio input
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice) {
            if session.canAddInput(audioInput) {
                session.addInput(audioInput)
            }
        }
        
        // Add video output
        let movieOutput = AVCaptureMovieFileOutput()
        movieOutput.maxRecordedDuration = CMTime(seconds: maxSegmentDuration, preferredTimescale: 600)
        
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            videoOutput = movieOutput
        }
        
        // Add photo output
        let photoOut = AVCapturePhotoOutput()
        if session.canAddOutput(photoOut) {
            session.addOutput(photoOut)
            photoOutput = photoOut
        }
        
        captureSession = session
        
        // Start session in background
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }
    
    // MARK: - Recording Control
    
    func startRecording(camera: CameraPosition = .back) {
        guard !isRecording, let videoOutput = videoOutput else { return }
        
        if camera != currentCamera {
            switchCamera()
        }
        
        let fileURL = generateVideoURL()
        currentVideoURL = fileURL
        recordingStartTime = Date()
        
        videoOutput.startRecording(to: fileURL, recordingDelegate: self)
        isRecording = true
        
        startDurationTimer()
    }
    
    func stopRecording() -> MediaCapture? {
        guard isRecording else { return nil }
        
        videoOutput?.stopRecording()
        isRecording = false
        stopDurationTimer()
        
        guard let url = currentVideoURL, let startTime = recordingStartTime else {
            return nil
        }
        
        var capture = MediaCapture(type: .video, localFileURL: url)
        
        // Get file size
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = attributes[.size] as? Int64 {
            capture.finalize(duration: currentDuration, fileSize: fileSize)
        }
        
        currentDuration = 0
        currentVideoURL = nil
        recordingStartTime = nil
        
        return capture
    }
    
    func switchCamera() {
        guard let session = captureSession else { return }
        
        let newPosition: AVCaptureDevice.Position = currentCamera == .back ? .front : .back
        
        session.beginConfiguration()
        
        // Remove existing video input
        if let currentInput = session.inputs.first(where: { input in
            guard let deviceInput = input as? AVCaptureDeviceInput else { return false }
            return deviceInput.device.hasMediaType(.video)
        }) {
            session.removeInput(currentInput)
        }
        
        // Add new camera input
        guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
              let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
            session.commitConfiguration()
            return
        }
        
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            currentCamera = newPosition == .front ? .front : .back
        }
        
        session.commitConfiguration()
    }
    
    // MARK: - Photo Capture
    
    func capturePhoto() -> MediaCapture? {
        guard let photoOutput = photoOutput else { return nil }
        
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        
        let fileURL = generatePhotoURL()
        
        // Note: In production, would use delegate to handle captured photo
        photoOutput.capturePhoto(with: settings, delegate: self)
        
        return MediaCapture(type: .photo, localFileURL: fileURL)
    }
    
    // MARK: - Helpers
    
    private func generateVideoURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let incidentMediaPath = documentsPath.appendingPathComponent("IncidentMedia", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: incidentMediaPath, withIntermediateDirectories: true)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "video_\(formatter.string(from: Date())).mp4"
        
        return incidentMediaPath.appendingPathComponent(filename)
    }
    
    private func generatePhotoURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let incidentMediaPath = documentsPath.appendingPathComponent("IncidentMedia", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: incidentMediaPath, withIntermediateDirectories: true)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "photo_\(formatter.string(from: Date())).jpg"
        
        return incidentMediaPath.appendingPathComponent(filename)
    }
    
    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.currentDuration += 1
        }
    }
    
    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension VideoRecorder: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Video recording error: \(error.localizedDescription)")
        } else {
            print("Video saved to: \(outputFileURL.path)")
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension VideoRecorder: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation(),
              let currentURL = currentVideoURL else { return }
        
        // Would save to the photo URL
        print("Photo captured")
    }
}
