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
    @Published var isDualCameraEnabled: Bool = false
    @Published var dualCameraSupported: Bool = AVCaptureMultiCamSession.isMultiCamSupported
    
    // MARK: - Capture Session
    private var captureSession: AVCaptureSession?
    private var singleVideoOutput: AVCaptureMovieFileOutput?
    private var backVideoOutput: AVCaptureMovieFileOutput?
    private var frontVideoOutput: AVCaptureMovieFileOutput?
    private var photoOutput: AVCapturePhotoOutput?
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var pendingPhotoURL: URL?
    private var pendingPhotoCompletion: ((MediaCapture?) -> Void)?
    private var pendingVideoDuration: TimeInterval?
    private var pendingVideoCompletion: (([MediaCapture]) -> Void)?
    private var pendingExpectedVideoCallbacks: Int = 0
    private var pendingVideoCaptures: [MediaCapture] = []
    
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

        if dualCameraSupported, setupMultiCamSession() {
            isDualCameraEnabled = true
            return
        }

        isDualCameraEnabled = false
        setupSingleCameraSession()
    }

    private func setupSingleCameraSession() {
        let session = AVCaptureSession()
        session.sessionPreset = .high
        
        // Add video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            lastError = "No camera is available."
            return
        }
        
        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        }
        
        // Add audio input
        if isAudioAuthorized,
           let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }
        
        // Add video output
        let movieOutput = AVCaptureMovieFileOutput()
        movieOutput.maxRecordedDuration = CMTime(seconds: maxSegmentDuration, preferredTimescale: 600)
        
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            singleVideoOutput = movieOutput
        }
        
        // Add photo output
        let photoOut = AVCapturePhotoOutput()
        if session.canAddOutput(photoOut) {
            session.addOutput(photoOut)
            photoOutput = photoOut
        }
        
        captureSession = session
        currentCamera = .back
        
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    private func setupMultiCamSession() -> Bool {
        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let backInput = try? AVCaptureDeviceInput(device: backCamera),
              let frontInput = try? AVCaptureDeviceInput(device: frontCamera) else {
            lastError = "Dual camera is not available on this device."
            return false
        }

        let session = AVCaptureMultiCamSession()
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard session.canAddInput(backInput), session.canAddInput(frontInput) else {
            lastError = "Dual camera inputs are unavailable."
            return false
        }
        session.addInputWithNoConnections(backInput)
        session.addInputWithNoConnections(frontInput)

        var audioInput: AVCaptureDeviceInput?
        if isAudioAuthorized,
           let audioDevice = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(input) {
            session.addInputWithNoConnections(input)
            audioInput = input
        }

        let backOutput = AVCaptureMovieFileOutput()
        let frontOutput = AVCaptureMovieFileOutput()
        backOutput.maxRecordedDuration = CMTime(seconds: maxSegmentDuration, preferredTimescale: 600)
        frontOutput.maxRecordedDuration = CMTime(seconds: maxSegmentDuration, preferredTimescale: 600)

        guard session.canAddOutput(backOutput), session.canAddOutput(frontOutput) else {
            lastError = "Dual camera outputs are unavailable."
            return false
        }
        session.addOutputWithNoConnections(backOutput)
        session.addOutputWithNoConnections(frontOutput)

        guard let backVideoPort = backInput.ports.first(where: { $0.mediaType == .video }),
              let frontVideoPort = frontInput.ports.first(where: { $0.mediaType == .video }) else {
            lastError = "Unable to connect dual camera ports."
            return false
        }

        let backVideoConnection = AVCaptureConnection(inputPorts: [backVideoPort], output: backOutput)
        let frontVideoConnection = AVCaptureConnection(inputPorts: [frontVideoPort], output: frontOutput)

        guard session.canAddConnection(backVideoConnection), session.canAddConnection(frontVideoConnection) else {
            lastError = "Unable to add dual camera connections."
            return false
        }
        session.addConnection(backVideoConnection)
        session.addConnection(frontVideoConnection)

        if let audioPort = audioInput?.ports.first(where: { $0.mediaType == .audio }) {
            let backAudioConnection = AVCaptureConnection(inputPorts: [audioPort], output: backOutput)
            if session.canAddConnection(backAudioConnection) {
                session.addConnection(backAudioConnection)
            }

            let frontAudioConnection = AVCaptureConnection(inputPorts: [audioPort], output: frontOutput)
            if session.canAddConnection(frontAudioConnection) {
                session.addConnection(frontAudioConnection)
            }
        }

        let photoOut = AVCapturePhotoOutput()
        if session.canAddOutput(photoOut) {
            session.addOutputWithNoConnections(photoOut)
            let photoConnection = AVCaptureConnection(inputPorts: [backVideoPort], output: photoOut)
            if session.canAddConnection(photoConnection) {
                session.addConnection(photoConnection)
                photoOutput = photoOut
            }
        }

        captureSession = session
        singleVideoOutput = nil
        backVideoOutput = backOutput
        frontVideoOutput = frontOutput
        currentCamera = .back
        lastError = nil

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }

        return true
    }
    
    // MARK: - Recording Control
    
    @discardableResult
    func startRecording(camera: CameraPosition = .back) -> Bool {
        guard !isRecording else { return true }

        if captureSession == nil {
            setupCaptureSession()
        }

        guard isAuthorized else {
            lastError = "Camera permission is required."
            return false
        }

        if !isDualCameraEnabled, camera != currentCamera {
            switchCamera()
        }

        let outputs = recordingOutputs()
        guard !outputs.isEmpty else {
            lastError = "Video output is unavailable. Check camera permissions."
            return false
        }

        if captureSession?.isRunning == false {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.startRunning()
            }
        }
        
        recordingStartTime = Date()
        lastError = nil
        pendingVideoCaptures.removeAll()

        for output in outputs {
            let stream = streamName(for: output)
            let fileURL = generateVideoURL(stream: stream)
            output.startRecording(to: fileURL, recordingDelegate: self)
        }

        isRecording = true
        currentDuration = 0
        startDurationTimer()
        return true
    }
    
    func stopRecording(completion: @escaping ([MediaCapture]) -> Void) {
        guard pendingVideoCompletion == nil else {
            completion([])
            return
        }

        guard isRecording else {
            completion([])
            return
        }

        let outputsToStop = recordingOutputs().filter { $0.isRecording }
        guard !outputsToStop.isEmpty else {
            isRecording = false
            stopDurationTimer()
            completion([])
            return
        }

        pendingVideoCompletion = completion
        if let startTime = recordingStartTime {
            pendingVideoDuration = Date().timeIntervalSince(startTime)
        } else {
            pendingVideoDuration = currentDuration
        }
        pendingExpectedVideoCallbacks = outputsToStop.count
        pendingVideoCaptures.removeAll()

        isRecording = false
        stopDurationTimer()
        outputsToStop.forEach { $0.stopRecording() }
    }
    
    func switchCamera() {
        guard !isDualCameraEnabled else {
            lastError = "Dual camera recording is active. Flip is disabled."
            return
        }
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
    
    private func recordingOutputs() -> [AVCaptureMovieFileOutput] {
        if isDualCameraEnabled {
            return [backVideoOutput, frontVideoOutput].compactMap { $0 }
        }
        return [singleVideoOutput].compactMap { $0 }
    }

    private func streamName(for output: AVCaptureMovieFileOutput) -> String {
        if output === backVideoOutput {
            return "back"
        }
        if output === frontVideoOutput {
            return "front"
        }
        return currentCamera == .front ? "front" : "back"
    }

    private func generateVideoURL(stream: String) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let incidentMediaPath = documentsPath.appendingPathComponent("IncidentMedia", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: incidentMediaPath, withIntermediateDirectories: true)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        let filename = "video_\(stream)_\(formatter.string(from: Date())).mp4"
        
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
        guard output is AVCaptureMovieFileOutput else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.handleFinishedRecording(
                outputFileURL: outputFileURL,
                error: error
            )
        }
    }
    
    private func handleFinishedRecording(outputFileURL: URL, error: Error?) {
        if let error = error {
            print("Video recording error: \(error.localizedDescription)")
        } else {
            var capture = MediaCapture(type: .video, localFileURL: outputFileURL)
            let duration = pendingVideoDuration ?? currentDuration

            if let attributes = try? FileManager.default.attributesOfItem(atPath: outputFileURL.path),
               let fileSize = attributes[.size] as? Int64 {
                capture.finalize(duration: duration, fileSize: fileSize)
            } else {
                capture.finalize(duration: duration, fileSize: 0)
            }

            pendingVideoCaptures.append(capture)
            print("Video saved to: \(outputFileURL.path)")
        }

        pendingExpectedVideoCallbacks -= 1
        if pendingExpectedVideoCallbacks <= 0 {
            completeVideoBatch()
        }
    }

    private func completeVideoBatch() {
        let completion = pendingVideoCompletion
        let captures = pendingVideoCaptures.sorted { lhs, rhs in
            streamPriority(for: lhs.localFileURL.lastPathComponent) < streamPriority(for: rhs.localFileURL.lastPathComponent)
        }

        pendingVideoCompletion = nil
        pendingVideoDuration = nil
        pendingVideoCaptures.removeAll()
        pendingExpectedVideoCallbacks = 0
        currentDuration = 0
        recordingStartTime = nil

        completion?(captures)
    }

    private func streamPriority(for filename: String) -> Int {
        if filename.contains("_back_") { return 0 }
        if filename.contains("_front_") { return 1 }
        return 2
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
