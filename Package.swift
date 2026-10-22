// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Snag",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Snag", targets: ["Snag"])],
    targets: [
        .target(name: "ShelfKit"),
        .executableTarget(
            name: "Snag",
            dependencies: ["ShelfKit"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("Quartz"),
                .linkedFramework("QuickLookThumbnailing"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "ShelfKitTests", dependencies: ["ShelfKit"]),
    ]
)
