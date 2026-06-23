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
            // AppIcon.icns / AppIconSource.png are handled by the build scripts and the
            // icon generator, not bundled by SwiftPM.
            exclude: ["Resources/AppIcon.icns", "Resources/AppIconSource.png"],
            resources: [
                .copy("Resources/parakeet_daemon.py"),
                .copy("Resources/MenuGlyph.svg")
            ]
        )
    ]
)
