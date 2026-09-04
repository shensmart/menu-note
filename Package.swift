// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MenuNote",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MenuNote",
            path: "Sources/MenuNote"
        ),
        .testTarget(
            name: "MenuNoteTests",
            dependencies: ["MenuNote"],
            path: "Tests/MenuNoteTests"
        )
    ]
)
