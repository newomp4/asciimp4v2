// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ASCIImp4",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ASCIImp4",
            path: "Sources/ASCIImp4"
        )
    ]
)
