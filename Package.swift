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
            exclude: [
                "AilertApp.swift",
                "ContentView.swift",
                "Resources",
                "Views",
                "Triggers",
                "Services/EmergencyClassifier.swift",
                "Services/EscalationEngine.swift",
                "Services/IncidentReportGenerator.swift",
                "Services/IncidentSessionManager.swift",
                "Services/LiveLocationService.swift",
                "Services/SensorFusionEngine.swift",
                "Services/SettingsManager.swift",
                "Services/VideoRecorder.swift",
            ],
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
