import CoreLocation
import XCTest
@testable import AilertCore

final class AilertCoreTests: XCTestCase {
    func testIncidentDefaults() {
        let incident = Incident()

        XCTAssertEqual(incident.status, .active)
        XCTAssertEqual(incident.classification, .unknown)
        XCTAssertEqual(incident.escalationLevel, .none)
        XCTAssertTrue(incident.events.isEmpty)
    }

    func testEmergencyProfileEmptyState() {
        var profile = EmergencyProfile()
        XCTAssertTrue(profile.isEmpty)

        profile.fullName = "Jane Doe"
        XCTAssertFalse(profile.isEmpty)
    }

    func testPrivacySanitizationRedactsSensitiveData() {
        let input = "Call 555-123-4567, email person@example.com, SSN 123-45-6789"
        let sanitized = PrivacyManager.shared.sanitizeForPublicSharing(input)

        XCTAssertFalse(sanitized.contains("555-123-4567"))
        XCTAssertFalse(sanitized.contains("person@example.com"))
        XCTAssertFalse(sanitized.contains("123-45-6789"))
        XCTAssertTrue(sanitized.contains("[REDACTED]"))
    }

    func testLocationSnapshotFromCoreLocation() {
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 15,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 90,
            speed: 2,
            timestamp: Date()
        )

        let snapshot = LocationSnapshot(from: location)
        XCTAssertEqual(snapshot.latitude, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(snapshot.longitude, -122.4194, accuracy: 0.0001)
        XCTAssertEqual(snapshot.heading ?? 0, 90, accuracy: 0.001)
        XCTAssertEqual(snapshot.speed ?? 0, 2, accuracy: 0.001)
    }
}
