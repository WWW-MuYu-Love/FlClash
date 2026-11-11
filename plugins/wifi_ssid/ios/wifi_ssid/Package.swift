// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "wifi_ssid",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "wifi-ssid", targets: ["wifi_ssid"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "wifi_ssid",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            linkerSettings: [
                .linkedFramework("NetworkExtension")
            ]
        )
    ]
)
