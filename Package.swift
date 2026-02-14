// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InkForge",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(
            name: "WacomAPI",
            path: "Sources/WacomAPI",
            sources: ["src"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon")
            ]
        ),
        .executableTarget(
            name: "InkForge",
            dependencies: ["WacomAPI"],
            path: "Sources/InkForge",
            exclude: ["Wacom/WacomTabletDriver.h", "Wacom/WacomTabletDriver.m",
                       "Wacom/TabletAEDictionary.h",
                       "Wacom/NSAppleEventDescriptorHelperCategory.h",
                       "Wacom/NSAppleEventDescriptorHelperCategory.m",
                       "Wacom/InkForge-Bridging-Header.h"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreImage"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        )
    ]
)
