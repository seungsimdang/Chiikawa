// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ChiikawaDesktop",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "ChiikawaDesktop")]
)
