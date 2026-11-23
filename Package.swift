// swift-tools-version:5.9
// TouchTargets: fail a UI test when a screen's touch targets are too small or
// too close together. See ios/TouchTargets/TouchTargets.swift. Its module also
// has assertTypography: fail when a screen shows a straight quote.
// FilmGrain: real 35mm film grain over an app's whole UI. See ios/FilmGrain/FilmGrain.swift.
// ShowTouches: every touch drawn by the app, for screen recordings. See ios/ShowTouches/ShowTouches.swift.
// Filming: a filmed UI test taps and types as a person does. See ios/Filming/Filming.swift.
import PackageDescription

let package = Package(
    name: "visual-test-tools",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "TouchTargets", targets: ["TouchTargets"]),
        .library(name: "FilmGrain", targets: ["FilmGrain"]),
        .library(name: "ShowTouches", targets: ["ShowTouches"]),
        .library(name: "Filming", targets: ["Filming"]),
    ],
    targets: [
        .target(name: "FilmGrain", path: "ios/FilmGrain"),
        .target(name: "ShowTouches", path: "ios/ShowTouches"),
        .target(name: "Filming", path: "ios/Filming", linkerSettings: [.linkedFramework("XCTest")]),
        .target(
            name: "TouchTargets",
            path: "ios/TouchTargets",
            linkerSettings: [.linkedFramework("XCTest")]
        ),
    ]
)
