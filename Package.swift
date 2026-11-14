// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EasyPeasy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "EasyPeasy",
            path: "Sources/EasyPeasy"
        )
    ]
)
