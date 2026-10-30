// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Jharokha",
    platforms: [.macOS(.v15)],
    targets: [
        // Pure layout and tiling model: no AppKit, no Accessibility, fully unit-tested.
        .target(name: "JharokhaCore"),
        .executableTarget(
            name: "Jharokha",
            dependencies: ["JharokhaCore"],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        // Command Line Tools can build swift-testing but not run it, so checks are an executable.
        .executableTarget(name: "JharokhaCoreChecks", dependencies: ["JharokhaCore"], path: "Tests/JharokhaCoreChecks"),
    ],
    swiftLanguageModes: [.v5]
)
