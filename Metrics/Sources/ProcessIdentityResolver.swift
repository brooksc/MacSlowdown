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
