// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SoundcoreMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SoundcoreMac", targets: ["SoundcoreMac"]),
        .executable(name: "SoundcoreWidget", targets: ["SoundcoreWidget"]),
        .library(name: "SoundcoreKit", targets: ["SoundcoreKit"]),
    ],
    targets: [
        // Pure protocol layer: framing, per-model parsing, packet builders. No Bluetooth, no UI.
        .target(name: "SoundcoreKit"),
        // Native macOS app: IOBluetooth RFCOMM transport + SwiftUI.
        .executableTarget(
            name: "SoundcoreMac",
            dependencies: ["SoundcoreKit"],
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("WidgetKit"),
            ]
        ),
        // Desktop widget, packaged as an app extension inside the app bundle by scripts/build-app.sh.
        .executableTarget(
            name: "SoundcoreWidget",
            dependencies: ["SoundcoreKit"],
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [
                .linkedFramework("WidgetKit"),
                // App extensions start in NSExtensionMain, which registers the extension type before
                // handing over to the WidgetBundle; a plain `main` crashes in ExtensionFoundation.
                .unsafeFlags(["-Xlinker", "-application_extension", "-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"]),
            ]
        ),
        .testTarget(name: "SoundcoreKitTests", dependencies: ["SoundcoreKit"]),
    ]
)
