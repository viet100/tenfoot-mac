// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TenFoot",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "TenFoot", targets: ["TenFoot"]),
    ],
    targets: [
        // Pure logic with no AppKit/SwiftUI, so it can be unit-tested.
        .target(name: "TenFootCore"),
        // The launcher app itself.
        .executableTarget(name: "TenFoot", dependencies: ["TenFootCore"]),
        .testTarget(name: "TenFootCoreTests", dependencies: ["TenFootCore"]),
    ],
    swiftLanguageModes: [.v5]
)
