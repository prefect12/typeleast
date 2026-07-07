// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Typeleast",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.10.2"),
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.1"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.15.0")
    ],
    targets: [
        .executableTarget(
            name: "Typeleast",
            dependencies: ["Alamofire", "HotKey", "WhisperKit"],
            path: "Sources",
            exclude: ["VersionInfo.swift.template"],
            resources: [
                .process("Assets.xcassets"),
                .copy("parakeet_transcribe_pcm.py"),
                .copy("mlx_semantic_correct.py"),
                .copy("verify_parakeet.py"),
                .copy("verify_mlx.py"),
                .copy("ml_daemon.py"),
                .copy("ml"),
                // Bundle additional resources like uv binary and lock files
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "TypeleastTests",
            dependencies: ["Typeleast"],
            path: "Tests",
            exclude: ["README.md", "test_parakeet_transcribe.py", "__Snapshots__"]
        )
    ]
)
