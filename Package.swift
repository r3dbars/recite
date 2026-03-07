// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Recite",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "Recite",
            dependencies: [
                .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift")
            ],
            path: "Recite/Sources/Recite",
            resources: [
                .copy("../../Resources/Info.plist"),
                .copy("../../Resources/Recite.entitlements")
            ]
        )
    ]
)
