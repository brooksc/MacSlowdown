import Darwin
import Foundation
import Security
import Synchronization

/// Everything we can learn about *what* a process is, as opposed to what it is using.
///
/// Two independent sources, both recorded, so a policy survives one becoming
/// unavailable (FR-016):
///   - `appBundlePath`, derived from the executable path. Available for 1042/1063
///     processes and unaffected by the sandbox, including for processes whose
///     metrics are denied.
///   - `bundleID` + `teamID`, from the code signature. Available for 810/1063
///     sandboxed. Stable across app updates and path changes, so it is the better
///     key when present.
public struct ResolvedIdentity: Sendable, Equatable {
    public let executablePath: String?
    /// The **outermost** `.app` in the executable path — the user-meaningful
    /// application family. Helpers live at
    /// `Parent.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper`, and it is
    /// the outermost bundle that groups them (FR-003).
    public let appBundlePath: String?
    public let bundleID: String?
    public let teamID: String?
    /// A human-meaningful name, when one exists on disk or in Launch Services.
    /// Nil for the ~77% of the table that are daemons and XPC services with no
    /// display name anywhere — see `ProcessNaming`.
    public let friendlyName: String?

    /// Defaults `friendlyName` to nil so that "we have no better name than the
    /// command" stays the explicit, unsurprising case at every construction site.
    public init(executablePath: String?, appBundlePath: String?,
                bundleID: String?, teamID: String?, friendlyName: String? = nil) {
        self.executablePath = executablePath
        self.appBundlePath = appBundlePath
        self.bundleID = bundleID
        self.teamID = teamID
        self.friendlyName = friendlyName
    }

    /// True when the process belongs to no application bundle. About 85% of the
    /// process table — daemons and command-line tools. These are standalone
    /// processes in their own right, not families of one.
    public var isStandalone: Bool { appBundlePath == nil }

    /// Whether this process **is an application**, rather than merely living inside
    /// one (TASK-86).
    ///
    /// `isStandalone` answers a grouping question — which family does this row
    /// belong to — and it is the wrong predicate for FR-046's subject. Xcode ships
    /// its entire toolchain at `Xcode.app/Contents/Developer/usr/bin/`, so `clang`,
    /// `git`, `ld` and `swift-frontend` all have a non-nil `appBundlePath`. Under
    /// `!isStandalone` a single build produced 419 recorded "exits of an
    /// application" for `swift-frontend` alone, and opened incidents for `git`.
    ///
    /// The rule is: the executable is the main executable of the **outermost**
    /// bundle — `Foo.app/Contents/MacOS/Foo`, where `Foo.app` is `appBundlePath`.
    ///
    /// This was briefly wider, admitting the main executable of *any* nested
    /// bundle, on the reasoning that a helper application crash-looping is exactly
    /// what FR-046 is about. The product owner's machine refuted that within the
    /// hour: "LM Studio Helper" — an Electron renderer inside `LM Studio.app` —
    /// opened an incident for recycling normally. Chromium-derived applications
    /// spawn and retire helpers as a matter of routine, so that is the same class
    /// of noise as the compiler churn, wearing a `.app` suffix.
    ///
    /// So the subject of a repeated-quit finding is the application itself. "LM
    /// Studio quit and reopened four times" is a finding; "its renderer recycled"
    /// is not. Helper exits are still recorded as lifecycle events and still
    /// visible in the process inspector — only the incident is withheld.
    ///
    /// `.appex` is excluded by construction: an app extension's directory ends in
    /// `.appex`, which is not `.app`, and an extension is not an application.
    public var isApplicationMainExecutable: Bool {
        guard let executablePath, let appBundlePath else { return false }
        return Self.isMainExecutable(executablePath, of: appBundlePath)
    }

    /// Pure, so the rule is testable against a path without a live process.
    ///
    /// Requires the binary to sit *directly* in the given bundle's `Contents/MacOS`:
    /// a nested path under it is a resource the application carries, and a
    /// `Contents/MacOS` belonging to some inner bundle is a helper rather than the
    /// application.
    static func isMainExecutable(_ path: String, of bundlePath: String) -> Bool {
        guard bundlePath.hasSuffix(".app") else { return false }
        let prefix = bundlePath + "/Contents/MacOS/"
        guard path.hasPrefix(prefix) else { return false }
        let remainder = path.dropFirst(prefix.count)
        return !remainder.isEmpty && !remainder.contains("/")
    }
}

/// Resolves and caches process identity.
///
/// Resolution is the dominant cost in the system: a full pass costs roughly 760ms
/// against ~2.6ms for a metrics sweep, about 300x. It is therefore done **once per
/// process lifetime**, keyed by `(pid, start time)`, and never on the per-sweep hot
/// path. Because the key includes start time, a reused PID misses the cache and is
/// resolved afresh, so two unrelated processes can never be merged.
public final class ProcessIdentityResolver: Sendable {
    private struct State {
        var cache: [ProcessIdentity: ResolvedIdentity] = [:]
        var resolutions = 0
    }

    private let state = Mutex(State())

    public init() {}

    /// Number of times identity was actually resolved, as opposed to served from
    /// cache. Exposed so overhead regressions are observable rather than inferred.
    public var resolutionCount: Int {
        state.withLock { $0.resolutions }
    }

    public var cachedCount: Int {
        state.withLock { $0.cache.count }
    }

    /// Cached identity for a process, resolving it on first request.
    public func identity(for identity: ProcessIdentity) -> ResolvedIdentity {
        if let cached = state.withLock({ $0.cache[identity] }) {
            return cached
        }
        // Resolve outside the lock: these are syscalls, and holding a lock across
        // them would serialise every caller behind the slowest one.
        let resolved = Self.resolve(pid: identity.pid)
        state.withLock {
            $0.cache[identity] = resolved
            $0.resolutions += 1
        }
        return resolved
    }

    /// What we already know about a process, or nil — **never resolves** (TASK-84).
    ///
    /// Two callers need an answer for a process that is about to stop existing, and
    /// for them `identity(for:)` is the wrong door. Resolution reads `proc_pidpath`
    /// and the code signature, which for a dead PID returns nothing at best and at
    /// worst answers about whoever inherits the number next; and it would put ~1 ms
    /// of syscalls per exiting process on the sampling path, which CLAUDE.md's
    /// "resolve once per process lifetime, never per sweep" rule exists to keep off.
    ///
    /// This is cheap and correct because the sweep's grouping pass has already asked
    /// `identity(for:)` about every process in the snapshot, so a process that was
    /// alive a moment ago is a cache hit. A miss means we genuinely never saw it
    /// resolved, and the caller must treat that as "not known to be an application"
    /// rather than resolving it here.
    public func cachedIdentity(for identity: ProcessIdentity) -> ResolvedIdentity? {
        state.withLock { $0.cache[identity] }
    }

    /// Drops cache entries for processes that no longer exist.
    ///
    /// Without this the cache grows without bound on a machine that churns through
    /// short-lived processes, which would eventually breach the FR-030 memory budget.
    public func prune(keeping live: Set<ProcessIdentity>) {
        state.withLock { state in
            state.cache = state.cache.filter { live.contains($0.key) }
        }
    }

    // MARK: - Resolution

    static func resolve(pid: pid_t) -> ResolvedIdentity {
        let path = executablePath(pid: pid)
        let appBundlePath = path.flatMap(outermostAppBundle)

        // The signature is asked for only when it can change an answer.
        //
        // Measured: it is 774 ms of the 819 ms a cold pass over 801 processes
        // costs — 94%, at 0.97 ms per call, against 0.003 ms for the path and
        // 0.023 ms for naming. The only thing it decides is how confident a
        // family membership is, and `classify` runs solely for processes inside a
        // `.app`. About 85% of the table is standalone, where membership is
        // trivially certain because the process is its own family, so paying for a
        // signature there buys nothing.
        let signature = appBundlePath == nil
            ? (bundleID: nil, teamID: nil)
            : codeSignature(pid: pid)

        return ResolvedIdentity(
            executablePath: path,
            appBundlePath: appBundlePath,
            bundleID: signature.bundleID,
            teamID: signature.teamID,
            // Resolved here so it lands in the same (pid, start time) cache as
            // everything else. It is filesystem work and must never run per sweep.
            friendlyName: ProcessNaming.resolve(pid: pid, executablePath: path)
        )
    }

    static func executablePath(pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        let written = buffer.withUnsafeMutableBytes {
            proc_pidpath(pid, $0.baseAddress, UInt32($0.count))
        }
        guard written > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(written)), as: UTF8.self)
    }

    /// The outermost `.app` in a path, which is the application family.
    ///
    /// Deliberately *not* the signed bundle identifier: helpers report their own
    /// identifier (`net.imput.helium.helper.renderer`), not the parent's, so the
    /// signature identifies a process but does not group it.
    static func outermostAppBundle(_ path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else {
            return nil
        }
        return components[...index].joined(separator: "/")
    }

    static func codeSignature(pid: pid_t) -> (bundleID: String?, teamID: String?) {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code
        else { return (nil, nil) }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            unsafeBitCast(code, to: SecStaticCode.self),
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
            let dictionary = information as? [String: Any]
        else { return (nil, nil) }

        return (
            dictionary[kSecCodeInfoIdentifier as String] as? String,
            dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        )
    }
}
