// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Glance",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Glance", targets: ["Glance"]),
               .executable(name: "GlancePowerHelper", targets: ["GlancePowerHelper"])],
    targets: [
        .target(name: "GlanceCore"),
        .executableTarget(name: "Glance", dependencies: ["GlanceCore"], resources: [.process("Resources")]),
        .executableTarget(name: "GlancePowerHelper", dependencies: ["GlanceCore"]),
        .testTarget(name: "GlanceCoreTests", dependencies: ["GlanceCore", "Glance"])
    ],
    swiftLanguageModes: [.v5]
)
