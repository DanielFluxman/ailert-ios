// MediaCapture.swift
// Model for video, audio, and photo captures during incidents

import Foundation

struct MediaCapture: Codable, Identifiable {
    let id: UUID
    let type: MediaType
    let startTime: Date
    var endTime: Date?
    let localFileURL: URL
    var duration: TimeInterval?
    var locationSnapshot: LocationSnapshot?
    var uploadStatus: UploadStatus
    var fileSizeBytes: Int64?
    
    init(type: MediaType, localFileURL: URL, locationSnapshot: LocationSnapshot? = nil) {
        self.id = UUID()
        self.type = type
        self.startTime = Date()
        self.endTime = nil
        self.localFileURL = localFileURL
        self.duration = nil
        self.locationSnapshot = locationSnapshot
        self.uploadStatus = .local
        self.fileSizeBytes = nil
    }
    
    mutating func finalize(duration: TimeInterval, fileSize: Int64) {
        self.endTime = Date()
        self.duration = duration
        self.fileSizeBytes = fileSize
    }
}

enum MediaType: String, Codable {
    case video
    case audio
    case photo
    
    var fileExtension: String {
        switch self {
        case .video: return "mp4"
        case .audio: return "m4a"
        case .photo: return "jpg"
        }
    }
    
    var icon: String {
        switch self {
        case .video: return "video.fill"
        case .audio: return "waveform"
        case .photo: return "photo.fill"
        }
    }
}

enum UploadStatus: String, Codable {
    case local          // Only on device
    case uploading      // Transfer in progress
    case uploaded       // Securely backed up
    case failed         // Upload failed
}
