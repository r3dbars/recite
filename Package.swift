// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Recite",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "mlx-audio-swift", path: "local-deps/mlx-audio-swift"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", .upToNextMajor(from: "0.30.6")),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", .upToNextMajor(from: "2.30.3"))
    ],
    targets: [
        .executableTarget(
            name: "Recite",
            dependencies: [
                .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm")
            ],
            path: "Recite/Sources/Recite",
            resources: [
                .copy("../../Resources/Info.plist"),
                .copy("../../Resources/Recite.entitlements")
            ]
        )
    ]
)
