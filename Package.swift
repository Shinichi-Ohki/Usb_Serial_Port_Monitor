// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SerialPortMenuApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SerialPortMenuApp", targets: ["SerialPortMenuApp"])
    ],
    targets: [
        .executableTarget(
            name: "SerialPortMenuApp",
            path: "SerialPortMenuApp",
            exclude: ["Info.plist"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("IOKit")
            ]
        )
    ]
)
