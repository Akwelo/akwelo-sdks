// swift-tools-version:5.9
// Root manifest so SPM can resolve this repo by URL. Mirrors ios/Package.swift.
import PackageDescription

let package = Package(
    name: "Akwelo",
    // iOS is the product. macOS is listed only so `swift test` can run the Foundation-only logic
    // tests on a Mac; the capture screen (UIKit) is not compiled there.
    platforms: [.iOS(.v14), .macOS(.v12)],
    products: [.library(name: "Akwelo", targets: ["Akwelo"])],
    targets: [
        .target(name: "Akwelo", path: "ios/Sources/Akwelo"),
        .testTarget(name: "AkweloTests", dependencies: ["Akwelo"], path: "ios/Tests/AkweloTests"),
    ]
)
