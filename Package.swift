// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EyeVoice",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "EyeVoice",
            path: "Sources/EyeVoice"
        )
    ]
)
