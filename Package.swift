// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VENCamera",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CanonKit", targets: ["CanonKit"]),
        .executable(name: "canon-probe", targets: ["canon-probe"]),
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
    ]
)
