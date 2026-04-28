// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacTortoiseSVN",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "CoreTypes", targets: ["CoreTypes"]),
        .library(name: "SVNCore", targets: ["SVNCore"]),
        .library(name: "StatusCenter", targets: ["StatusCenter"]),
        .library(name: "StatusService", targets: ["StatusService"]),
        .library(name: "StatusServiceXPC", targets: ["StatusServiceXPC"]),
        .library(name: "CommitKit", targets: ["CommitKit"]),
        .library(name: "FinderSyncBridge", targets: ["FinderSyncBridge"]),
        .library(name: "IntegrationKit", targets: ["IntegrationKit"]),
        .executable(name: "mtsvn", targets: ["MacSVNCLI"]),
        .executable(name: "macsvn-statusd", targets: ["MacSVNStatusServiceCLI"]),
        .executable(name: "MacSVNStatusXPCService", targets: ["MacSVNStatusXPCService"]),
        .executable(name: "MacSVNFinderSync", targets: ["MacSVNFinderSync"]),
        .executable(name: "MacTortoiseSVN", targets: ["MacSVNWorkbench"]),
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "CoreTypes"),
        .target(name: "SVNCore", dependencies: ["CoreTypes"]),
        .target(name: "StatusCenter", dependencies: ["CoreTypes", "SVNCore"]),
        .target(name: "StatusService", dependencies: ["CoreTypes", "SVNCore", "StatusCenter", "CSQLite"]),
        .target(name: "FinderSyncBridge", dependencies: ["CoreTypes"]),
        .target(
            name: "StatusServiceXPC",
            dependencies: ["CoreTypes", "SVNCore", "StatusService", "FinderSyncBridge"]
        ),
        .target(name: "CommitKit", dependencies: ["CoreTypes", "SVNCore", "StatusCenter"]),
        .target(name: "IntegrationKit", dependencies: ["CoreTypes"]),
        .executableTarget(
            name: "MacSVNStatusServiceCLI",
            dependencies: ["CoreTypes", "StatusService"]
        ),
        .executableTarget(
            name: "MacSVNStatusXPCService",
            dependencies: ["StatusServiceXPC"]
        ),
        .executableTarget(
            name: "MacSVNFinderSync",
            dependencies: ["FinderSyncBridge", "StatusServiceXPC"],
            path: "Apps/MacSVNFinderSync/Sources"
        ),
        .executableTarget(
            name: "MacSVNWorkbench",
            dependencies: [
                "CoreTypes",
                "FinderSyncBridge",
                "IntegrationKit",
                "StatusService",
                "StatusServiceXPC",
                "SVNCore",
            ],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "MacSVNCLI",
            dependencies: ["CoreTypes", "SVNCore", "StatusCenter", "CommitKit", "IntegrationKit"]
        ),
        .testTarget(
            name: "StatusCenterTests",
            dependencies: ["CoreTypes", "SVNCore", "StatusCenter"]
        ),
        .testTarget(
            name: "SVNCoreTests",
            dependencies: ["CoreTypes", "SVNCore", "StatusCenter"]
        ),
        .testTarget(
            name: "StatusServiceTests",
            dependencies: ["CoreTypes", "SVNCore", "StatusCenter", "StatusService"]
        ),
        .testTarget(
            name: "FinderSyncBridgeTests",
            dependencies: ["CoreTypes", "FinderSyncBridge"]
        ),
        .testTarget(
            name: "IntegrationKitTests",
            dependencies: ["IntegrationKit"]
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["CoreTypes", "SVNCore", "StatusCenter", "StatusService"]
        ),
    ]
)
