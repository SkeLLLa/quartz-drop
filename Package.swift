// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "quartz-drop",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "quartz-drop", targets: ["QuartzDrop"])
    ],
    dependencies: [
        .package(url: "https://github.com/dduan/TOMLDecoder", from: "0.4.5")
    ],
    targets: [
        .target(
            name: "QuartzDropCore",
            dependencies: [.product(name: "TOMLDecoder", package: "TOMLDecoder")]
        ),
        .executableTarget(
            name: "QuartzDrop",
            dependencies: ["QuartzDropCore"]
        ),
        .testTarget(
            name: "QuartzDropCoreTests",
            dependencies: ["QuartzDropCore"]
        ),
    ]
)
