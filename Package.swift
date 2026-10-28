// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Insel",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Insel", path: "Sources/Insel")
    ]
)
