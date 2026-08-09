import ProjectDescription

// MacSlowdown — Mac App Store target only.
//
// FR-037: the shipping build must contain no privileged-helper code paths and no
// unreachable privileged UI. There is deliberately no second target, no build
// configuration, and no compilation condition for a privileged tier. Adding one
// requires a separate approved specification.

let bundleID = "com.brooksc.MacSlowdown"
let teamID = "SU999VT2G2"

/// Manual signing with the Apple Development identity, matching what
/// probe/build-sandboxed.sh proved works for a sandboxed local build. Avoids
/// needing provisioning updates during CLI builds.
/// App icon (TASK-65.18). The artwork is authored as SVG in `design/icons/` and
/// rasterised by `design/icons/build.sh` into
/// `MacSlowdown/Resources/Assets.xcassets/AppIcon.appiconset`. Regenerate with
/// that script rather than editing the PNGs.
let appIcon: SettingsDictionary = [
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
]

let signing: SettingsDictionary = [
    "CODE_SIGN_STYLE": "Manual",
    "CODE_SIGN_IDENTITY": "Apple Development",
    "DEVELOPMENT_TEAM": .string(teamID),
    "PROVISIONING_PROFILE_SPECIFIER": "",
]

let shared: SettingsDictionary = [
    "SWIFT_VERSION": "6.0",
    // DR-10: concurrency isolation around samplers and persistence.
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "MACOSX_DEPLOYMENT_TARGET": "26.0",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_TREAT_WARNINGS_AS_ERRORS": "YES",
    "SWIFT_TREAT_WARNINGS_AS_ERRORS": "YES",
]

let project = Project(
    name: "MacSlowdown",
    organizationName: "Brooks Cutter",
    settings: .settings(base: shared, configurations: [
        .debug(name: "Debug"),
        .release(name: "Release"),
    ]),
    targets: [
        .target(
            name: "MacSlowdown",
            destinations: [.mac],
            product: .app,
            bundleId: bundleID,
            deploymentTargets: .macOS("26.0"),
            infoPlist: .extendingDefault(with: [
                // Menu bar utility: no Dock icon, no default menu bar.
                "LSUIElement": true,
                "CFBundleShortVersionString": "0.1",
                "CFBundleVersion": "1",
                "NSHumanReadableCopyright": "Copyright © 2026 Brooks Cutter",
                "LSApplicationCategoryType": "public.app-category.utilities",
            ]),
            sources: ["MacSlowdown/Sources/**"],
            resources: ["MacSlowdown/Resources/**"],
            entitlements: "MacSlowdown/Support/MacSlowdown.entitlements",
            dependencies: [.target(name: "Metrics")],
            settings: .settings(
                base: signing.merging(appIcon) { _, new in new },
                configurations: [
                    // Debug keeps Xcode's injected get-task-allow so the debugger
                    // can attach.
                    .debug(name: "Debug"),
                    // Release must not carry get-task-allow — App Review rejects a
                    // submission that has it. Xcode injects it unless this is off,
                    // so the shipping build's entitlements are exactly the ones in
                    // MacSlowdown.entitlements.
                    .release(name: "Release", settings: [
                        "CODE_SIGN_INJECT_BASE_ENTITLEMENTS": "NO",
                    ]),
                ]
            )
        ),
        .target(
            name: "Metrics",
            destinations: [.mac],
            product: .framework,
            bundleId: "\(bundleID).Metrics",
            deploymentTargets: .macOS("26.0"),
            sources: ["Metrics/Sources/**"],
            settings: .settings(base: signing)
        ),
        // App-layer tests. Hosted by the app because MonitorStore, the intents and
        // the notification adapter live in the app target and cannot be linked
        // without it. The host's launch work is skipped under XCTest — see
        // AppDelegate — so running tests does not start monitoring or put a status
        // item in the user's menu bar.
        .target(
            name: "MacSlowdownTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "\(bundleID).MacSlowdownTests",
            deploymentTargets: .macOS("26.0"),
            sources: ["MacSlowdown/Tests/**"],
            dependencies: [.target(name: "MacSlowdown")],
            settings: .settings(base: signing)
        ),
        .target(
            name: "MetricsTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "\(bundleID).MetricsTests",
            deploymentTargets: .macOS("26.0"),
            sources: ["Metrics/Tests/**"],
            dependencies: [.target(name: "Metrics")],
            settings: .settings(base: signing)
        ),
    ],
    schemes: [
        // Tuist's auto-generated app scheme has no test action, and the tests land
        // in the per-framework scheme, which is not discoverable. This is the one
        // entry point: `tuist xcodebuild test -scheme AllTests`.
        .scheme(
            name: "AllTests",
            shared: true,
            buildAction: .buildAction(targets: ["MacSlowdown", "Metrics"]),
            testAction: .targets(["MetricsTests", "MacSlowdownTests"])
        ),
    ]
)
