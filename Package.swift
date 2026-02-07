// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ailert",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "AilertCore",
            targets: ["AilertCore"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AilertCore",
            dependencies: [],
            path: "Ailert",
            sources: [
                "Models/Incident.swift",
                "Models/MediaCapture.swift",
                "Models/TrustedContact.swift",
                "Models/EmergencyProfile.swift",
                "Models/SensorData.swift",
                "Safety/AuditLogger.swift",
                "Safety/DuressDetector.swift",
                "Safety/PrivacyManager.swift",
                "Services/IncidentStore.swift",
            ]
        ),
        .testTarget(
            name: "AilertTests",
            dependencies: ["AilertCore"],
            path: "AilertTests"
        ),
    ]
)
