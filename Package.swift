// swift-tools-version: 5.9
import PackageDescription
import Foundation

let frameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let libraries = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
let clt = FileManager.default.fileExists(atPath: frameworks)
let package = Package(
    name: "Bug",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "Bug", targets: ["Bug"])],
    targets: [
        .executableTarget(name: "Bug"),
        .testTarget(name: "BugTests", dependencies: ["Bug"],
            swiftSettings: clt ? [.unsafeFlags(["-F", frameworks])] : [],
            linkerSettings: clt ? [.unsafeFlags(["-F", frameworks, "-Xlinker", "-rpath", "-Xlinker", frameworks, "-Xlinker", "-rpath", "-Xlinker", libraries])] : [])
    ]
)
