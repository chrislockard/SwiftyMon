// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftyMon",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SwiftyMon",
            path: "SwiftyMon",
            exclude: [
                "Info.plist",
                "SwiftyMon.entitlements",
                "Assets.xcassets",
            ]
        )
    ]
)
