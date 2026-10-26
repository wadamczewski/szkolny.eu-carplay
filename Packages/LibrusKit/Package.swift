// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LibrusKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LibrusKit", targets: ["LibrusKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "LibrusKit",
            dependencies: ["SwiftSoup"]
        ),
        // Offline self-check on synthetic (fake) fixtures: `swift run LibrusKitCheck`.
        .executableTarget(
            name: "LibrusKitCheck",
            dependencies: ["LibrusKit"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
