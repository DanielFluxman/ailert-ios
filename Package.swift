// Package.swift
// Swift Package definition for Ailert

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ailert",
    platforms: [
        .iOS(.v16),
        .watchOS(.v9)
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
            path: "Ailert"
        ),
        .testTarget(
            name: "AilertTests",
            dependencies: ["AilertCore"],
            path: "AilertTests"
        ),
    ]
)
