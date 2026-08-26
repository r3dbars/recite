// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Recite",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", revision: "cae704f53bc32a3d0b606823828fbc5bedaaf388"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", .upToNextMajor(from: "0.30.6")),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", .upToNextMajor(from: "3.31.3"))
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
                .copy("../../Resources/Recite.entitlements"),
                .copy("../../Resources/AppIcon.icns"),
                .copy("../../Resources/DMGIcon.icns"),
                .copy("../../Resources/MenuBarIcon.png"),
                .copy("../../Resources/MenuBarIcon@2x.png"),
                .copy("../../Resources/VoiceSamples")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "ReciteTests",
            dependencies: ["Recite"],
            path: "Tests/ReciteTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
