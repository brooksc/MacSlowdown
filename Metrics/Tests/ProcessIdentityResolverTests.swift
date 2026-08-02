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
        let helper = "/Applications/Helium.app/Contents/Frameworks/Helium Helper.app/Contents/MacOS/Helium Helper"
        #expect(ProcessIdentityResolver.outermostAppBundle(helper) == "/Applications/Helium.app")

        let plain = "/Applications/Helium.app/Contents/MacOS/Helium"
        #expect(ProcessIdentityResolver.outermostAppBundle(plain) == "/Applications/Helium.app")
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
