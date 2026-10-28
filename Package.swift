// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Autocomplete",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Autocomplete", targets: ["Autocomplete"])],
    targets: [
        .target(name: "CompletionCore"),
        .executableTarget(name: "Autocomplete", dependencies: ["CompletionCore"]),
        .testTarget(name: "CompletionCoreTests", dependencies: ["CompletionCore"])
    ]
)
