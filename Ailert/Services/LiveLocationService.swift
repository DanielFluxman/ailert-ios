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
    func generateLocationMessage(for incident: Incident, location: CLLocation) -> String {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let mapsLink = "https://maps.apple.com/?ll=\(lat),\(lon)&q=Emergency"
        
        let message = """
        🚨 EMERGENCY ALERT
        
        I need help! My current location:
        \(mapsLink)
        
        Coordinates: \(String(format: "%.6f", lat)), \(String(format: "%.6f", lon))
        Time: \(formatTime(Date()))
        Type: \(incident.classification.displayName)
        
        This is an automated alert from Ailert.
        """
        
        return message
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
