import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        // The spec targets macOS 26 and 27, so the toolchain requirement says the
        // same. It previously read `.upToNextMajor("27.0")`, which meant Xcode
        // 27 or nothing — and Xcode 27 is a beta, so in practice the project
        // could only be built on a machine that had opted into it. CI found this
        // on its first real run: a macOS 26 runner with Xcode 26.6 was refused
        // before a line was compiled.
        compatibleXcodeVersions: .list([.upToNextMajor("26.0"), .upToNextMajor("27.0")]),
        swiftVersion: "6.0"
    )
)
