// swift-tools-version:5.9
import Foundation
import PackageDescription

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

let package = Package(
    name: "VENCamera",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CanonKit", targets: ["CanonKit"]),
        .executable(name: "canon-probe", targets: ["canon-probe"]),
        .executable(name: "VENCamera", targets: ["VENCamera"]),
    ],
    targets: [
        .systemLibrary(
            name: "CGPhoto2",
            path: "Sources/CGPhoto2",
            pkgConfig: "libgphoto2",
            providers: [.brew(["libgphoto2"])]
        ),
        .target(name: "CanonKit", dependencies: ["CGPhoto2"]),
        .executableTarget(name: "canon-probe", dependencies: ["CanonKit"]),

        // The Metal server half of Syphon (BSD-2, github.com/Syphon/Syphon-Framework),
        // vendored because Syphon has no SwiftPM package. OBS reads our frames through it.
        .target(
            name: "Syphon",
            exclude: ["LICENSE.txt", "VENDORED.md"],
            cSettings: [
                .headerSearchPath("include/Syphon"),
                .unsafeFlags(["-include", "\(root)/Sources/Syphon/Syphon_Prefix.h", "-Wno-deprecated-declarations"]),
            ],
            linkerSettings: [.linkedFramework("Cocoa"), .linkedFramework("Metal"), .linkedFramework("IOSurface")]
        ),
        .executableTarget(
            name: "VENCamera",
            dependencies: ["CanonKit", "CGPhoto2", "Syphon"],
            exclude: ["Info.plist"]
        ),
    ]
)
