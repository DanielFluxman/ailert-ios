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
    @Published var isAudioAuthorized: Bool = false
    @Published var lastError: String?
    
    // MARK: - Capture Session
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureMovieFileOutput?
    private var photoOutput: AVCapturePhotoOutput?
    private var currentVideoURL: URL?
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var pendingPhotoURL: URL?
    private var pendingPhotoCompletion: ((MediaCapture?) -> Void)?
    private var pendingVideoDuration: TimeInterval?
    private var pendingVideoCompletion: ((MediaCapture?) -> Void)?
    
    // MARK: - Configuration
    private let maxSegmentDuration: TimeInterval = 300 // 5 minutes
    
    override init() {
        super.init()
        checkAuthorization()
    }
    
    // MARK: - Authorization
    
    private func checkAuthorization() {
        requestVideoAuthorization { [weak self] videoGranted in
            guard let self = self else { return }

            self.requestAudioAuthorization { audioGranted in
                DispatchQueue.main.async {
                    self.isAuthorized = videoGranted
                    self.isAudioAuthorized = audioGranted

                    if videoGranted {
                        self.setupCaptureSession()
                    }
                }
            }
        }
    }

    private func requestVideoAuthorization(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video, completionHandler: completion)
        default:
            completion(false)
        }
    }

    private func requestAudioAuthorization(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
        default:
            completion(false)
        }
    }
    
    // MARK: - Setup
    
    private func setupCaptureSession() {
        if captureSession != nil {
            return
        }

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
        if isAudioAuthorized,
           let audioDevice = AVCaptureDevice.default(for: .audio),
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
    
    @discardableResult
    func startRecording(camera: CameraPosition = .back) -> Bool {
        guard !isRecording else { return true }

        if captureSession == nil {
            setupCaptureSession()
        }

        guard let videoOutput = videoOutput else {
            lastError = "Video output is unavailable. Check camera permissions."
            return false
        }

        if captureSession?.isRunning == false {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.startRunning()
            }
        }
        
        if camera != currentCamera {
            switchCamera()
        }
        
        let fileURL = generateVideoURL()
        currentVideoURL = fileURL
        recordingStartTime = Date()
        lastError = nil
        videoOutput.startRecording(to: fileURL, recordingDelegate: self)
        isRecording = true
        currentDuration = 0
        startDurationTimer()
        return true
    }
    
    func stopRecording(completion: @escaping (MediaCapture?) -> Void) {
        guard isRecording else {
            completion(nil)
            return
        }

        guard recordingStartTime != nil, currentVideoURL != nil else {
            isRecording = false
            stopDurationTimer()
            completion(nil)
            return
        }

        pendingVideoCompletion = completion
        if let startTime = recordingStartTime {
            pendingVideoDuration = Date().timeIntervalSince(startTime)
        } else {
            pendingVideoDuration = currentDuration
        }

        isRecording = false
        stopDurationTimer()
        videoOutput?.stopRecording()
    }
    
    func switchCamera() {
        guard let session = captureSession else { return }
        guard !isRecording else { return }
        
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
    
    func capturePhoto(completion: @escaping (MediaCapture?) -> Void) {
        guard let photoOutput = photoOutput else {
            completion(nil)
            return
        }
        
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        
        pendingPhotoURL = generatePhotoURL()
        pendingPhotoCompletion = completion
        photoOutput.capturePhoto(with: settings, delegate: self)
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
            completeVideoCapture(nil)
            return
        }

        var capture = MediaCapture(type: .video, localFileURL: outputFileURL)
        let duration = pendingVideoDuration ?? currentDuration

        if let attributes = try? FileManager.default.attributesOfItem(atPath: outputFileURL.path),
           let fileSize = attributes[.size] as? Int64 {
            capture.finalize(duration: duration, fileSize: fileSize)
        } else {
            capture.finalize(duration: duration, fileSize: 0)
        }

        print("Video saved to: \(outputFileURL.path)")
        completeVideoCapture(capture)
    }

    private func completeVideoCapture(_ capture: MediaCapture?) {
        let completion = pendingVideoCompletion
        pendingVideoCompletion = nil
        pendingVideoDuration = nil

        currentDuration = 0
        currentVideoURL = nil
        recordingStartTime = nil

        DispatchQueue.main.async {
            completion?(capture)
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension VideoRecorder: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Photo capture error: \(error.localizedDescription)")
            completePhotoCapture(nil)
            return
        }

        guard let imageData = photo.fileDataRepresentation(),
              let photoURL = pendingPhotoURL else {
            completePhotoCapture(nil)
            return
        }

        do {
            try imageData.write(to: photoURL)
            var capture = MediaCapture(type: .photo, localFileURL: photoURL)
            capture.finalize(duration: 0, fileSize: Int64(imageData.count))
            completePhotoCapture(capture)
        } catch {
            print("Failed to save photo: \(error.localizedDescription)")
            completePhotoCapture(nil)
        }
    }

    private func completePhotoCapture(_ capture: MediaCapture?) {
        let completion = pendingPhotoCompletion
        pendingPhotoCompletion = nil
        pendingPhotoURL = nil
        DispatchQueue.main.async {
            completion?(capture)
        }
    }
}
