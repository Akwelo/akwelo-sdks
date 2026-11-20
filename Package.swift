// swift-tools-version:5.9
// Root manifest so SPM can resolve this repo by URL. Mirrors ios/Package.swift.
import PackageDescription

let package = Package(
    name: "Akwelo",
    platforms: [.iOS(.v14)],
    products: [.library(name: "Akwelo", targets: ["Akwelo"])],
    targets: [
        .target(name: "Akwelo", path: "ios/Sources/Akwelo"),
        .testTarget(name: "AkweloTests", dependencies: ["Akwelo"], path: "ios/Tests/AkweloTests"),
    ]
)
