// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "HelperMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Helper", targets: ["HelperMac"]),
        .library(name: "HelperCore", targets: ["HelperCore"]),
    ],
    targets: [
        // Pure logic (no UI): OpenAI client, RAG, licensing, image stitching.
        .target(name: "HelperCore"),
        // The SwiftUI/AppKit application.
        .executableTarget(name: "HelperMac", dependencies: ["HelperCore"]),
        // Self-contained check runner (`swift run HelperChecks`): works without Xcode/XCTest.
        .executableTarget(name: "HelperChecks", dependencies: ["HelperCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
