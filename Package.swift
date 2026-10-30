// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Pane",
    platforms: [.macOS(.v15)],
    targets: [
        // Pure layout and tiling model: no AppKit, no Accessibility, fully unit-tested.
        .target(name: "PaneCore"),
        .executableTarget(
            name: "Pane",
            dependencies: ["PaneCore"],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        // Command Line Tools can build swift-testing but not run it, so checks are an executable.
        .executableTarget(name: "PaneCoreChecks", dependencies: ["PaneCore"], path: "Tests/PaneCoreChecks"),
    ],
    swiftLanguageModes: [.v5]
)
