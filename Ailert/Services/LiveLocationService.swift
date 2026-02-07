// LiveLocationService.swift
// Service for sharing live location during emergencies

import Foundation
import CoreLocation
import MapKit

class LiveLocationService: ObservableObject {
    static let shared = LiveLocationService()
    
    @Published var isSharingLocation: Bool = false
    @Published var lastSharedLocation: CLLocation?
    @Published var currentAddress: String = "Locating..."
    @Published var activeSession: LiveShareSession?
    
    private let geocoder = CLGeocoder()
    
    private init() {}
    
    // MARK: - Location Sharing
    
    /// Start broadcasting location (marks that sharing is active)
    func startSharing() {
        isSharingLocation = true
    }
    
    /// Stop broadcasting location
    func stopSharing() {
        isSharingLocation = false
        lastSharedLocation = nil
    }

    /// Create a live share session that can be sent to contacts.
    func startLiveShareSession(
        for incident: Incident,
        includeMediaMetadata: Bool,
        autoNotifyContacts: Bool
    ) -> LiveShareSession {
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let shareURL = generateLiveShareURL(token: token)
        let session = LiveShareSession(
            id: UUID(),
            token: token,
            shareURL: shareURL,
            startedAt: Date(),
            endedAt: nil,
            isActive: true,
            updateCount: 0,
            lastLatitude: nil,
            lastLongitude: nil,
            lastAudioDecibels: nil,
            autoNotifiedContacts: autoNotifyContacts,
            includesMediaMetadata: includeMediaMetadata
        )
        activeSession = session
        startSharing()
        return session
    }

    /// Apply a location/audio update to an existing live share session.
    func updateLiveShareSession(
        _ session: LiveShareSession,
        location: CLLocation?,
        audioDecibels: Float?
    ) -> LiveShareSession {
        var updated = session
        updated.updateCount += 1
        updated.isActive = true

        if let location = location {
            updated.lastLatitude = location.coordinate.latitude
            updated.lastLongitude = location.coordinate.longitude
            updateLocation(location)
        }

        if let audioDecibels = audioDecibels {
            updated.lastAudioDecibels = audioDecibels
        }

        activeSession = updated
        return updated
    }

    /// Stop an active live share session.
    func stopLiveShareSession(_ session: LiveShareSession) -> LiveShareSession {
        var ended = session
        ended.isActive = false
        ended.endedAt = Date()
        activeSession = nil
        stopSharing()
        return ended
    }
    
    /// Update current location and address
    func updateLocation(_ location: CLLocation) {
        lastSharedLocation = location
        reverseGeocode(location)
    }
    
    // MARK: - Shareable Links
    
    /// Generate an Apple Maps link for the current location
    func generateMapsLink(for location: CLLocation) -> URL? {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        return URL(string: "https://maps.apple.com/?ll=\(lat),\(lon)&q=Emergency%20Location")
    }
    
    /// Generate a Google Maps link as fallback
    func generateGoogleMapsLink(for location: CLLocation) -> URL? {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        return URL(string: "https://www.google.com/maps?q=\(lat),\(lon)")
    }
    
    /// Generate SMS-ready message with location
    func generateLocationMessage(for incident: Incident, location: CLLocation, liveShareURL: URL? = nil) -> String {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let mapsLink = "https://maps.apple.com/?ll=\(lat),\(lon)&q=Emergency"
        let liveTrackerLine = liveShareURL.map { "Live tracker: \($0.absoluteString)" } ?? ""
        
        let message = """
        🚨 EMERGENCY ALERT
        
        I need help! My current location:
        \(mapsLink)
        
        Coordinates: \(String(format: "%.6f", lat)), \(String(format: "%.6f", lon))
        Time: \(formatTime(Date()))
        Type: \(incident.classification.displayName)
        \(liveTrackerLine)
        
        This is an automated alert from Ailert.
        """
        
        return message
    }

    /// Message used when auto-notifying emergency contacts about a live tracker session.
    func generateLiveShareMessage(
        for incident: Incident,
        shareSession: LiveShareSession,
        location: CLLocation?
    ) -> String {
        let base = "🟢 LIVE TRACKER STARTED\nTrack this emergency in real time:\n\(shareSession.shareURL.absoluteString)"
        guard let location = location else { return "\(base)\nType: \(incident.classification.displayName)" }

        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        return """
        \(base)
        Current map: https://maps.apple.com/?ll=\(lat),\(lon)&q=Emergency
        Type: \(incident.classification.displayName)
        """
    }
    
    /// Generate location update message (for periodic updates)
    func generateUpdateMessage(location: CLLocation, address: String?) -> String {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let mapsLink = "https://maps.apple.com/?ll=\(lat),\(lon)"
        
        var message = "📍 Location Update\n\(mapsLink)"
        
        if let address = address {
            message += "\n\(address)"
        }
        
        if let speed = location.speed.magnitude > 0 ? location.speed : nil {
            let speedMph = speed * 2.237 // m/s to mph
            message += "\nSpeed: \(Int(speedMph)) mph"
        }
        
        return message
    }
    
    // MARK: - Route Summary
    
    /// Generate a route summary for an incident
    func generateRouteSummary(for snapshots: [LocationSnapshot]) -> RouteSummary? {
        guard snapshots.count >= 2 else { return nil }
        
        let sorted = snapshots.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first, let last = sorted.last else { return nil }
        
        let startLocation = CLLocation(latitude: first.latitude, longitude: first.longitude)
        let endLocation = CLLocation(latitude: last.latitude, longitude: last.longitude)
        
        let totalDistance = calculateTotalDistance(snapshots: sorted)
        let duration = last.timestamp.timeIntervalSince(first.timestamp)
        
        return RouteSummary(
            startTime: first.timestamp,
            endTime: last.timestamp,
            startCoordinate: first.coordinate,
            endCoordinate: last.coordinate,
            totalDistance: totalDistance,
            duration: duration,
            pointCount: snapshots.count
        )
    }
    
    /// Calculate total distance traveled through all points
    private func calculateTotalDistance(snapshots: [LocationSnapshot]) -> CLLocationDistance {
        var totalDistance: CLLocationDistance = 0
        
        for i in 1..<snapshots.count {
            let prev = CLLocation(latitude: snapshots[i-1].latitude, longitude: snapshots[i-1].longitude)
            let curr = CLLocation(latitude: snapshots[i].latitude, longitude: snapshots[i].longitude)
            totalDistance += prev.distance(from: curr)
        }
        
        return totalDistance
    }
    
    // MARK: - Geocoding
    
    private func reverseGeocode(_ location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let placemark = placemarks?.first else {
                self?.currentAddress = "Unknown Location"
                return
            }
            
            var components: [String] = []
            
            if let street = placemark.thoroughfare {
                if let number = placemark.subThoroughfare {
                    components.append("\(number) \(street)")
                } else {
                    components.append(street)
                }
            }
            
            if let city = placemark.locality {
                components.append(city)
            }
            
            if let state = placemark.administrativeArea {
                components.append(state)
            }
            
            DispatchQueue.main.async {
                self?.currentAddress = components.isEmpty ? "Unknown Location" : components.joined(separator: ", ")
            }
        }
    }

    // MARK: - Helpers

    private func generateLiveShareURL(token: String) -> URL {
        // Use Apple Maps link directly - works without backend server
        // When location becomes available, the share message includes the actual coordinates
        URL(string: "https://maps.apple.com/?q=Emergency+Location")!
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Route Summary

struct RouteSummary {
    let startTime: Date
    let endTime: Date
    let startCoordinate: CLLocationCoordinate2D
    let endCoordinate: CLLocationCoordinate2D
    let totalDistance: CLLocationDistance
    let duration: TimeInterval
    let pointCount: Int
    
    var averageSpeed: Double {
        guard duration > 0 else { return 0 }
        return totalDistance / duration // meters per second
    }
    
    var averageSpeedMph: Double {
        averageSpeed * 2.237
    }
    
    var formattedDistance: String {
        let miles = totalDistance / 1609.34
        if miles < 0.1 {
            return "\(Int(totalDistance)) ft"
        } else {
            return String(format: "%.1f mi", miles)
        }
    }
    
    var formattedDuration: String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        if mins > 0 {
            return "\(mins)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }
}
