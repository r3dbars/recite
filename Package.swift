// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Recite",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "Recite",
            dependencies: [
                .product(name: "TTSKit", package: "WhisperKit"),
            ],
            path: "Recite/Sources/Recite",
            resources: [
                .copy("../../Resources/Info.plist"),
                .copy("../../Resources/Recite.entitlements")
            ]
        )
    ]
)
