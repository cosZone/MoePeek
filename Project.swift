import ProjectDescription

let project = Project(
    name: "MoePeek",
    settings: .settings(
        base: [
            "INFOPLIST_KEY_LSUIElement": "YES",
            "INFOPLIST_KEY_NSAccessibilityUsageDescription":
                "MoePeek needs accessibility access to read selected text.",
            "INFOPLIST_KEY_NSScreenCaptureUsageDescription":
                "MoePeek needs screen capture for OCR translation.",
            "SWIFT_STRICT_CONCURRENCY": "complete",
        ],
        configurations: [
            .debug(name: "Debug", xcconfig: "Configurations/Signing.xcconfig"),
            .release(name: "Release", xcconfig: "Configurations/Signing.xcconfig"),
        ]
    ),
    targets: [
        .target(
            name: "MoePeek",
            destinations: .macOS,
            product: .app,
            bundleId: "com.nahida.MoePeek",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDevelopmentRegion": "en",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "SUFeedURL": "https://github.com/cosZone/MoePeek/releases/latest/download/appcast.xml",
                "SUPublicEDKey": "$(SPARKLE_ED_PUBLIC_KEY)",
                "CFBundleURLTypes": [
                    [
                        "CFBundleURLName": "com.nahida.MoePeek",
                        "CFBundleURLSchemes": ["mopeek"],
                    ],
                ],
            ]),
            sources: [
                "Sources/App/**",
                "Sources/Core/**",
                "Sources/Services/**",
                "Sources/UI/**",
                "Sources/Utilities/**",
            ],
            resources: ["Resources/**"],
            entitlements: .file(path: "Entitlements/MoePeek.entitlements"),
            scripts: [
                .post(
                    script: """
                    mkdir -p "$BUILT_PRODUCTS_DIR/$PRODUCT_NAME.app/Contents/MacOS"
                    cp "$BUILT_PRODUCTS_DIR/MoePeekOCRWorker" "$BUILT_PRODUCTS_DIR/$PRODUCT_NAME.app/Contents/MacOS/MoePeekOCRWorker"
                    """,
                    name: "Embed OCR Worker",
                    basedOnDependencyAnalysis: false
                ),
            ],
            dependencies: [
                .external(name: "KeyboardShortcuts"),
                .external(name: "Defaults"),
                .external(name: "Sparkle"),
                .external(name: "Textual"),
                .target(name: "MoePeekOCRWorker"),
            ],
            settings: .settings(
                base: [
                    "CODE_SIGN_STYLE": "$(MOEPEEK_CODE_SIGN_STYLE)",
                    "CODE_SIGN_IDENTITY": "$(MOEPEEK_CODE_SIGN_IDENTITY)",
                    "DEVELOPMENT_TEAM": "$(MOEPEEK_DEVELOPMENT_TEAM)",
                    "MARKETING_VERSION": "0.21.4",
                    "CURRENT_PROJECT_VERSION": "4",
                ],
                configurations: [
                    .debug(name: "Debug", xcconfig: "Configurations/Signing.xcconfig"),
                    .release(name: "Release", xcconfig: "Configurations/Signing.xcconfig"),
                ]
            )
        ),
        .target(
            name: "MoePeekOCRWorker",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "com.nahida.MoePeek.OCRWorker",
            deploymentTargets: .macOS("15.0"),
            sources: [
                "Sources/OCRShared/**",
                "Sources/OCRWorkerSources/**",
            ],
            settings: .settings(
                base: [
                    "LD_RUNPATH_SEARCH_PATHS": [
                        "$(inherited)",
                        "@executable_path",
                        "@executable_path/../Frameworks",
                    ],
                ]
            )
        ),
        .target(
            name: "MoePeekTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.nahida.MoePeekTests",
            deploymentTargets: .macOS("15.0"),
            sources: ["Tests/**"],
            dependencies: [
                .target(name: "MoePeek"),
            ]
        ),
    ]
)
