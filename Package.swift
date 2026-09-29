// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ForgetIt",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "ForgetIt", targets: ["ForgetIt"])],
    targets: [
        .executableTarget(name: "ForgetIt")
    ],
    swiftLanguageModes: [.v5]
)
