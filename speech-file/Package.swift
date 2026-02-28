// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpeechFile",
    platforms: [
        .macOS(.v15),
        .iOS(.v17),
    ],
    dependencies: [
        .package(path: "../speech-core"),
    ],
    targets: [
        .executableTarget(
            name: "SpeechFile",
            dependencies: [
                .product(name: "SpeechCore", package: "speech-core"),
            ]
        ),
    ]
)
