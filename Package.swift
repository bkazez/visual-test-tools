// swift-tools-version:5.9
// TouchTargets: fail a UI test when a screen's touch targets are too small or
// too close together. See ios/TouchTargets/TouchTargets.swift.
import PackageDescription

let package = Package(
    name: "visual-test-tools",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "TouchTargets", targets: ["TouchTargets"]),
    ],
    targets: [
        .target(
            name: "TouchTargets",
            path: "ios/TouchTargets",
            linkerSettings: [.linkedFramework("XCTest")]
        ),
    ]
)
