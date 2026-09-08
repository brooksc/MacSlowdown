import Darwin
import Foundation
import Testing

@testable import Metrics

@Suite("Identity resolution")
struct IdentityResolutionTests {
    @Test("Resolves the running test process")
    func resolvesSelf() {
        let resolver = ProcessIdentityResolver()
        let snapshot = ProcessSampler().snapshot()
        guard let mine = snapshot.records.values.first(where: { $0.identity.pid == getpid() })
        else { Issue.record("own pid missing"); return }

        let resolved = resolver.identity(for: mine.identity)
        #expect(resolved.executablePath != nil)
        #expect(resolved.bundleID != nil, "the test bundle is signed, so it has an identifier")
    }

    /// AC#5: both sources recorded, so a policy survives one becoming unavailable.
    @Test("Records both path and signature identity across the process table")
    func recordsBothSources() {
        let resolver = ProcessIdentityResolver()
        let snapshot = ProcessSampler().snapshot()
        var withPath = 0, withSignature = 0, withBundle = 0

        for record in snapshot.records.values.prefix(120) {
            let resolved = resolver.identity(for: record.identity)
            if resolved.executablePath != nil { withPath += 1 }
            if resolved.bundleID != nil { withSignature += 1 }
            if resolved.appBundlePath != nil { withBundle += 1 }
        }

        // Path is the more reliable of the two and is unaffected by the sandbox.
        #expect(withPath > 0)
        #expect(withSignature > 0)
        #expect(withPath >= withBundle, "every bundled process must also have a path")
    }
}

@Suite("Identity caching")
struct IdentityCachingTests {
    /// AC#3 and AC#4: resolution happens once per process lifetime, never per
    /// sweep. Resolution costs ~300x a metrics sweep, so repeating it would breach
    /// the FR-030 budget on its own.
    @Test("Repeated lookups resolve once and are served from cache thereafter")
    func resolvesOncePerProcess() {
        let resolver = ProcessIdentityResolver()
        let snapshot = ProcessSampler().snapshot()
        let sample = Array(snapshot.records.keys.prefix(40))

        for identity in sample { _ = resolver.identity(for: identity) }
        let afterFirstPass = resolver.resolutionCount
        #expect(afterFirstPass == sample.count)

        // Simulate nine further sweeps over the same processes.
        for _ in 0..<9 {
            for identity in sample { _ = resolver.identity(for: identity) }
        }
        #expect(resolver.resolutionCount == afterFirstPass,
                "identity was re-resolved on a later sweep")
    }

    @Test("Cached lookups are dramatically cheaper than resolving")
    func cacheIsFaster() {
        let resolver = ProcessIdentityResolver()
        let snapshot = ProcessSampler().snapshot()
        let sample = Array(snapshot.records.keys.prefix(60))
        let clock = ContinuousClock()

        let cold = clock.measure { for id in sample { _ = resolver.identity(for: id) } }
        let warm = clock.measure { for id in sample { _ = resolver.identity(for: id) } }

        #expect(warm.totalSeconds < cold.totalSeconds,
                "warm \(warm.totalSeconds)s was not faster than cold \(cold.totalSeconds)s")
    }

    /// AC#1: a reused PID must not inherit the previous process's identity.
    @Test("A reused pid misses the cache and is resolved afresh")
    func reusedPidIsNotMerged() {
        let resolver = ProcessIdentityResolver()
        let pid = getpid()
        let original = ProcessIdentity(pid: pid, startTime: 1_000)
        let reused = ProcessIdentity(pid: pid, startTime: 2_000)

        _ = resolver.identity(for: original)
        let afterFirst = resolver.resolutionCount
        _ = resolver.identity(for: reused)

        #expect(resolver.resolutionCount == afterFirst + 1,
                "the reused pid was served the previous process's cached identity")
        #expect(resolver.cachedCount == 2)
    }

    /// AC#2: identity is keyed by (pid, start time), so a family's history is
    /// anchored to something that survives PID replacement.
    @Test("Pruning drops dead processes and keeps live ones")
    func pruningKeepsLiveOnly() {
        let resolver = ProcessIdentityResolver()
        let live = ProcessIdentity(pid: getpid(), startTime: 1_000)
        let dead = ProcessIdentity(pid: getpid(), startTime: 2_000)

        _ = resolver.identity(for: live)
        _ = resolver.identity(for: dead)
        #expect(resolver.cachedCount == 2)

        resolver.prune(keeping: [live])
        #expect(resolver.cachedCount == 1)

        // The survivor is still cached: pruning must not force re-resolution.
        let before = resolver.resolutionCount
        _ = resolver.identity(for: live)
        #expect(resolver.resolutionCount == before)
    }
}

@Suite("Application family grouping helpers")
struct AppBundleTests {
    @Test("Outermost .app wins, so helpers group to their parent application")
    func outermostBundleWins() {
        let helper = "/Applications/BrowserApp.app/Contents/Frameworks/BrowserApp Helper.app/Contents/MacOS/BrowserApp Helper"
        #expect(ProcessIdentityResolver.outermostAppBundle(helper) == "/Applications/BrowserApp.app")

        let plain = "/Applications/BrowserApp.app/Contents/MacOS/BrowserApp"
        #expect(ProcessIdentityResolver.outermostAppBundle(plain) == "/Applications/BrowserApp.app")
    }

    @Test("Daemons and command-line tools belong to no bundle")
    func standaloneProcessesHaveNoBundle() {
        #expect(ProcessIdentityResolver.outermostAppBundle("/usr/sbin/mds_stores") == nil)
        #expect(ProcessIdentityResolver.outermostAppBundle("/bin/zsh") == nil)
    }

    @Test("A helper and its parent resolve to the same family")
    func helperAndParentShareFamily() {
        let parent = ProcessIdentityResolver.outermostAppBundle(
            "/Applications/Xcode.app/Contents/MacOS/Xcode")
        let helper = ProcessIdentityResolver.outermostAppBundle(
            "/Applications/Xcode.app/Contents/Developer/usr/bin/swift-frontend")
        #expect(parent == helper)
        #expect(parent == "/Applications/Xcode.app")
    }
}

/// TASK-86. The predicate that decides whether a repeated-exit subject is an
/// *application*, as opposed to something that merely lives inside one.
///
/// The distinction is not academic: on the machine this was found on, one build
/// recorded 419 exits of `swift-frontend`, 141 of `clang` and 21 of `git`, and all
/// three satisfied the old `!isStandalone` test because Xcode ships them inside its
/// own bundle. See `AppBundleTests.helperAndParentShareFamily`, which asserts that
/// same grouping and is still correct — grouping and subject are different questions.
@Suite("Application main executable")
struct ApplicationMainExecutableTests {
    private func identity(_ path: String?) -> ResolvedIdentity {
        ResolvedIdentity(
            executablePath: path,
            appBundlePath: path.flatMap(ProcessIdentityResolver.outermostAppBundle),
            bundleID: nil, teamID: nil)
    }

    @Test("An application's own executable is an application")
    func mainExecutableQualifies() {
        #expect(identity("/Applications/Xcode.app/Contents/MacOS/Xcode")
            .isApplicationMainExecutable)
        #expect(identity("/System/Applications/Mail.app/Contents/MacOS/Mail")
            .isApplicationMainExecutable)
    }

    @Test("A toolchain binary shipped inside a bundle is not")
    func toolchainBinariesAreExcluded() {
        let toolchain = [
            "/Applications/Xcode.app/Contents/Developer/usr/bin/swift-frontend",
            "/Applications/Xcode.app/Contents/Developer/usr/bin/clang",
            "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
            "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild",
            "/Applications/Xcode.app/Contents/Developer/Toolchains/"
                + "XcodeDefault.xctoolchain/usr/bin/ld",
        ]
        for path in toolchain {
            // Grouped into Xcode, which is right, and not an application, which is
            // the whole of TASK-86.
            #expect(identity(path).appBundlePath == "/Applications/Xcode.app")
            #expect(!identity(path).isApplicationMainExecutable, "\(path)")
        }
    }

    /// Reversed on 2026-08-25 by the product owner's machine rather than by
    /// argument: "LM Studio Helper" — an Electron renderer inside `LM Studio.app` —
    /// opened a repeated-quit incident for recycling normally, within an hour of the
    /// wider rule shipping. Chromium-derived applications retire helpers as routine
    /// work, so admitting them is the compiler-churn defect in a `.app` suffix.
    @Test("A bundled helper application is not the application")
    func helperApplicationsAreExcluded() {
        let helper = "/Applications/Google Chrome.app/Contents/Frameworks/"
            + "Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
        // Still grouped into Chrome — the family is right, the subject is not.
        #expect(identity(helper).appBundlePath == "/Applications/Google Chrome.app")
        #expect(!identity(helper).isApplicationMainExecutable)

        #expect(!identity("/Applications/LM Studio.app/Contents/Frameworks/"
            + "LM Studio Helper.app/Contents/MacOS/LM Studio Helper")
            .isApplicationMainExecutable)
        // The application itself still does.
        #expect(identity("/Applications/LM Studio.app/Contents/MacOS/LM Studio")
            .isApplicationMainExecutable)
    }

    @Test("An app extension is not an application")
    func extensionsAreExcluded() {
        #expect(!identity("/Applications/Notes.app/Contents/PlugIns/"
            + "NotesShare.appex/Contents/MacOS/NotesShare")
            .isApplicationMainExecutable)
    }

    @Test("Daemons, command-line tools and an unknown path are not applications")
    func nonBundledProcessesAreExcluded() {
        #expect(!identity("/usr/sbin/mds_stores").isApplicationMainExecutable)
        #expect(!identity("/bin/zsh").isApplicationMainExecutable)
        #expect(!identity("/usr/bin/git").isApplicationMainExecutable)
        // No path at all: 21 of 1063 processes, and the answer must be "no" so an
        // incident is withheld rather than opened on a guess.
        #expect(!identity(nil).isApplicationMainExecutable)
    }

    @Test("A resource nested below Contents/MacOS is not the application")
    func nestedResourcesAreExcluded() {
        #expect(!identity("/Applications/Thing.app/Contents/MacOS/support/helper")
            .isApplicationMainExecutable)
        // A directory path rather than a binary.
        #expect(!identity("/Applications/Thing.app/Contents/MacOS/")
            .isApplicationMainExecutable)
    }
}
