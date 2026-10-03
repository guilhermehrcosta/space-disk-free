// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SpaceDiskFree",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SpaceDiskFree", targets: ["SpaceDiskFree"]),
    ],
    targets: [
        .target(name: "DiskCore"),
        .executableTarget(name: "SpaceDiskFree", dependencies: ["DiskCore"]),
        .testTarget(name: "DiskCoreTests", dependencies: ["DiskCore"]),
    ]
)
