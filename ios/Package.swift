// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Akwelo",
    platforms: [.iOS(.v14)],
    products: [.library(name: "Akwelo", targets: ["Akwelo"])],
    targets: [
        .target(name: "Akwelo", path: "Sources/Akwelo"),
        .testTarget(name: "AkweloTests", dependencies: ["Akwelo"], path: "Tests/AkweloTests"),
    ]
)
