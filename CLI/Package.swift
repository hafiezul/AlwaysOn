// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "AlwaysOnCLI", platforms: [.macOS(.v13)], products: [.executable(name: "alwayson", targets: ["alwayson"])], targets: [.executableTarget(name: "alwayson")])
