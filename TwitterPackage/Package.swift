// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "TwitterPackage",
    platforms: [
        .iOS("27.2")
    ],
    products: [
        .library(name: "AppFeature", targets: ["AppFeature"]),
        .library(name: "ColumnNavigation", targets: ["ColumnNavigation"]),
        .library(name: "ComposeFeature", targets: ["ComposeFeature"]),
        .library(name: "FeedFeature", targets: ["FeedFeature"]),
        .library(name: "ImagePipeline", targets: ["ImagePipeline"]),
        .library(name: "MainFeature", targets: ["MainFeature"]),
        .library(name: "Models", targets: ["Models"]),
        .library(name: "ProfileFeature", targets: ["ProfileFeature"]),
        .library(name: "Routing", targets: ["Routing"]),
        .library(name: "SearchFeature", targets: ["SearchFeature"]),
        .library(name: "SignInFeature", targets: ["SignInFeature"]),
        .library(name: "TabStackFeature", targets: ["TabStackFeature"]),
        .library(name: "TweetEngagement", targets: ["TweetEngagement"]),
        .library(name: "TwitterClient", targets: ["TwitterClient"]),
        .library(name: "TwitterClientLive", targets: ["TwitterClientLive"]),
        .library(name: "TwitterDatabase", targets: ["TwitterDatabase"]),
        .library(name: "TwitterUI", targets: ["TwitterUI"]),
        .library(name: "UserListFeature", targets: ["UserListFeature"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.26.2"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.17.1"),
        .package(url: "https://github.com/pointfreeco/swift-identified-collections", from: "1.1.1"),
        .package(url: "https://github.com/EmergeTools/Pow", from: "0.3.1"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.10.1"),
        .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.9.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.7")
    ],
    targets: [
        .target(
            name: "AppFeature",
            dependencies: [
                "ImagePipeline",
                "MainFeature",
                "Routing",
                "SignInFeature",
                "TweetEngagement",
                "TwitterClientLive",
                "TwitterDatabase",
                "TwitterUI",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ]
        ),
        .target(
            name: "ColumnNavigation",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances")
            ]
        ),
        .target(
            name: "ComposeFeature",
            dependencies: [
                "Routing",
                "TwitterUI",
                "TwitterClient",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ]
        ),
        .target(
            name: "FeedFeature",
            dependencies: [
                "ImagePipeline",
                "PostText",
                "Routing",
                "TweetEngagement",
                "TwitterClient",
                "TwitterDatabase",
                "TwitterUI",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ]
        ),
        .target(
            name: "ImagePipeline",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies")
            ]
        ),
        .target(
            name: "MainFeature",
            dependencies: [
                "ComposeFeature",
                "TabStackFeature",
                "TwitterUI",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ]
        ),
        .target(
            name: "Models",
            dependencies: [
                .product(name: "IdentifiedCollections", package: "swift-identified-collections")
            ]
        ),
        .target(
            name: "ProfileFeature",
            dependencies: [
                "FeedFeature",
                "TwitterDatabase",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ]
        ),
        .target(
            name: "Routing",
            dependencies: [
                "Models"
            ]
        ),
        .target(
            name: "SearchFeature",
            dependencies: [
                "FeedFeature",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ]
        ),
        .target(
            name: "SignInFeature",
            dependencies: [
                "TwitterUI",
                "TwitterClient",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ]
        ),
        .target(
            name: "TabStackFeature",
            dependencies: [
                "ColumnNavigation",
                "FeedFeature",
                "ProfileFeature",
                "SearchFeature",
                "TwitterUI",
                "UserListFeature",
                "WebFeature",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ]
        ),
        .target(
            name: "UserListFeature",
            dependencies: [
                "Routing",
                "TwitterClient",
                "TwitterUI",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ]
        ),
        .target(
            name: "WebFeature",
            dependencies: [
                "Routing",
                "TwitterUI",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ]
        ),
        .target(
            name: "TweetEngagement",
            dependencies: [
                "Models",
                "TwitterClient",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "Sharing", package: "swift-sharing")
            ]
        ),
        .target(
            name: "PostText",
            dependencies: [
                "Models",
                "Routing"
            ]
        ),
        .testTarget(
            name: "PostTextTests",
            dependencies: [
                "PostText"
            ]
        ),
        .target(
            name: "TwitterUI",
            dependencies: [
                "ImagePipeline",
                "Models",
                "PostText",
                "Routing",
                "TwitterClient",
                "TwitterDatabase",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Pow", package: "Pow")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "TwitterClient",
            dependencies: [
                "Models",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "Sharing", package: "swift-sharing")
            ]
        ),
        .target(
            name: "TwitterDatabase",
            dependencies: [
                "Models",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "SQLiteData", package: "sqlite-data")
            ]
        ),
        .target(
            name: "TwitterClientLive",
            dependencies: [
                "Models",
                "TwitterClient",
                .product(name: "Dependencies", package: "swift-dependencies")
            ]
        ),
        .testTarget(
            name: "AppFeatureTests",
            dependencies: [
                "AppFeature",
                .product(name: "DependenciesTestSupport", package: "swift-dependencies")
            ]
        ),
        .testTarget(
            name: "ComposeFeatureTests",
            dependencies: [
                "ComposeFeature",
                .product(name: "DependenciesTestSupport", package: "swift-dependencies")
            ]
        ),
        .testTarget(
            name: "FeedFeatureTests",
            dependencies: [
                "FeedFeature",
                .product(name: "DependenciesTestSupport", package: "swift-dependencies")
            ]
        ),
        .testTarget(
            name: "MainFeatureTests",
            dependencies: [
                "MainFeature",
                .product(name: "DependenciesTestSupport", package: "swift-dependencies")
            ]
        ),
        .testTarget(
            name: "ModelsTests",
            dependencies: [
                "Models"
            ]
        ),
        .testTarget(
            name: "ProfileFeatureTests",
            dependencies: [
                "ProfileFeature"
            ]
        ),
        .testTarget(
            name: "SearchFeatureTests",
            dependencies: [
                "SearchFeature"
            ]
        ),
        .testTarget(
            name: "TwitterDatabaseTests",
            dependencies: [
                "TwitterDatabase",
                .product(name: "DependenciesTestSupport", package: "swift-dependencies")
            ]
        ),
        .testTarget(
            name: "TweetEngagementTests",
            dependencies: [
                "TweetEngagement",
                .product(name: "DependenciesTestSupport", package: "swift-dependencies")
            ]
        ),
        .testTarget(
            name: "SnapshotTests",
            dependencies: [
                "MainFeature",
                "ProfileFeature",
                "TabStackFeature",
                "TwitterDatabase",
                "TwitterUI",
                .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            exclude: ["__Snapshots__"]
        ),
        .testTarget(
            name: "UserListFeatureTests",
            dependencies: [
                "UserListFeature"
            ]
        ),
        .testTarget(
            name: "TabStackFeatureTests",
            dependencies: [
                "TabStackFeature"
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
