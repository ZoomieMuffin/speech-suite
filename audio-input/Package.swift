// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AudioInput",
    platforms: [
        .macOS(.v15),
        .iOS(.v17),
    ],
    dependencies: [
        .package(path: "../speech-core"),
    ],
    targets: [
        .executableTarget(
            name: "AudioInput",
            dependencies: [
                .product(name: "SpeechCore", package: "speech-core"),
            ]
        ),
    ]
)
