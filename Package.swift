// swift-tools-version:5.9
// TouchTargets: fail a UI test when a screen's touch targets are too small or
// too close together. See ios/TouchTargets/TouchTargets.swift.
// FilmGrain: real 35mm film grain over an app's whole UI. See ios/FilmGrain/FilmGrain.swift.
import PackageDescription

let package = Package(
    name: "visual-test-tools",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "TouchTargets", targets: ["TouchTargets"]),
        .library(name: "FilmGrain", targets: ["FilmGrain"]),
    ],
    targets: [
        .target(name: "FilmGrain", path: "ios/FilmGrain"),
        .target(
            name: "TouchTargets",
            path: "ios/TouchTargets",
            linkerSettings: [.linkedFramework("XCTest")]
        ),
    ]
)
