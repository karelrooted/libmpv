// swift-tools-version: 5.7.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "libmpv",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .executable(
            name: "MPVBuild",
            targets: ["MPVBuild"])
    ],
    dependencies: [
            // Dependencies declare other packages that this package depends on.
            .package(url: "https://github.com/apple/swift-argument-parser.git",
                     from: "0.4.4")
        ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        
        .executableTarget(
            name: "MPVBuild",
            dependencies: [
                           .product(name: "ArgumentParser",
                                    package: "swift-argument-parser")
            ]
        )       
    ]
)
