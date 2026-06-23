// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Vocal",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Vocal", targets: ["Vocal"])
    ],
    targets: [
        .executableTarget(
            name: "Vocal",
            // AppIcon.icns is staged into the .app bundle by the build scripts, not by SwiftPM.
            exclude: ["Resources/AppIcon.icns"],
            resources: [
                .copy("Resources/parakeet_daemon.py")
            ]
        )
    ]
)
