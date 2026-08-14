// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MarkdownPreview",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MarkdownCore", targets: ["MarkdownCore"])
    ],
    targets: [
        .target(name: "MarkdownCore", path: "MarkdownCore"),
        .testTarget(
            name: "MarkdownCoreTests",
            dependencies: ["MarkdownCore"],
            path: "Tests/MarkdownCoreTests"
        )
    ]
)

