// IncidentStore.swift
// Persistent storage for incidents

import Foundation

class IncidentStore {
    static let shared = IncidentStore()
    
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private var storageURL: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("incidents.json")
    }
    
    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - CRUD Operations
    
    func save(_ incident: Incident) {
        var incidents = loadAll()
        
        if let index = incidents.firstIndex(where: { $0.id == incident.id }) {
            incidents[index] = incident
        } else {
            incidents.append(incident)
        }
        
        saveAll(incidents)
    }
    
    func loadAll() -> [Incident] {
        guard fileManager.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let incidents = try? decoder.decode([Incident].self, from: data) else {
            return []
        }
        return incidents.sorted { $0.sessionStart > $1.sessionStart }
    }
    
    func load(id: UUID) -> Incident? {
        return loadAll().first { $0.id == id }
    }
    
    func delete(id: UUID) {
        var incidents = loadAll()
        incidents.removeAll { $0.id == id }
        saveAll(incidents)
    }
    
    func deleteAll() {
        try? fileManager.removeItem(at: storageURL)
    }
    
    // MARK: - Private
    
    private func saveAll(_ incidents: [Incident]) {
        guard let data = try? encoder.encode(incidents) else { return }
        try? data.write(to: storageURL)
    }
}
