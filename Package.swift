import PackageDescription

let package = Package(
    name: "ChainMark",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "ChainMark",
            targets: ["ChainMark"]
        )
    ],
    dependencies: [
        // Supabase client (needed for Stage C — backend integration)
        // Uncomment when connecting to backend:
        // .package(url: "https://github.com/supabase-community/supabase-swift.git", from: "2.0.0"),
        
        // System dependencies managed via Xcode/SPM
    ],
    targets: [
        .target(
            name: "ChainMark",
            dependencies: [
                // Add dependencies as needed:
                // .product(name: "Supabase", package: "supabase-swift"),
            ],
            resources: [
                .process("Info.plist")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .unsafeFlags(["-enable-library-evolution"])
            ]
        )
    ]
)