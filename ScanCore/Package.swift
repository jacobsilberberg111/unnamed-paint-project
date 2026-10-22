// swift-tools-version:5.9
import PackageDescription

// Pure-Swift measurement core. No RoomPlan or UIKit, so the maths runs and is
// unit-tested on any platform (`swift test --package-path ScanCore`).
let package = Package(
    name: "ScanCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ScanCore", targets: ["ScanCore"]),
    ],
    targets: [
        .target(name: "ScanCore"),
        .testTarget(name: "ScanCoreTests", dependencies: ["ScanCore"]),
    ]
)
