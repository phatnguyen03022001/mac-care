// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MacCare",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacCareCore", targets: ["MacCareCore"]),
        .executable(name: "MacCare", targets: ["MacCareApp"]),
        .executable(name: "mac-care-mcp", targets: ["MacCareMCP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
    ],
    targets: [
        .target(name: "MacCareCore"),
        .executableTarget(name: "MacCareApp", dependencies: ["MacCareCore"]),
        .executableTarget(name: "MacCareMCP", dependencies: ["MacCareCore", .product(name: "MCP", package: "swift-sdk")]),
        .testTarget(name: "MacCareCoreTests", dependencies: ["MacCareCore"]),
    ]
)
