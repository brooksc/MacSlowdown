import AppKit
import Darwin
import Foundation
import UniformTypeIdentifiers

/// Turns a process into a name a person recognises (FR-003, FR-013).
///
/// The kernel's `p_comm` is truncated to 16 bytes, which produces names like
/// `Spotify Helper (` and `Helium Helper (R` — cut mid-word, with nothing to say
/// anything was lost. Presenting that as the name breaks FR-002's rule that a
/// value we cannot fully report is labelled rather than quietly abbreviated.
///
/// Measured sandboxed (probe/FINDINGS.md): reading an installed application's
/// `Info.plist` is **not** denied, so 145 of 151 processes in a `.app` yield a
/// real name, and with `NSRunningApplication` 187 of 800 processes do.
///
/// The remaining ~77% are daemons and XPC services that have no display name
/// anywhere on disk. No API invents one. For those the honest answer is the
/// command, marked as truncated when it is.
public enum ProcessNaming {
    /// `p_comm` is `MAXCOMLEN + 1` bytes, so anything at 16 was cut.
    public static let commandLimit = 16

    /// Whether the kernel truncated this command.
    ///
    /// Length is the only signal available — the kernel does not report that it
    /// cut anything — so a genuine 16-character name is indistinguishable from a
    /// truncated one. Marking a complete name as truncated is the safer error:
    /// it understates certainty rather than overstating it.
    public static func isTruncated(_ command: String) -> Bool {
        command.utf8.count >= commandLimit
    }

    /// The command as it should be shown when nothing better exists.
    ///
    /// An ellipsis is how truncation is conventionally signalled, and it is the
    /// difference between "this process is called `Spotify Helper (`" and "this
    /// name was cut off".
    public static func labelled(command: String) -> String {
        isTruncated(command) ? command + "…" : command
    }

    /// Spoken form, since an ellipsis conveys nothing to VoiceOver (FR-034).
    public static func accessibilityLabel(command: String) -> String {
        isTruncated(command)
            ? "\(command), name shortened by the system"
            : command
    }

    /// Bundle kinds that carry a usable display name. `.framework` is deliberately
    /// absent: 269 processes ran from inside one during the probe and it almost
    /// never yields anything better than the command.
    static let namedBundleSuffixes = [".app", ".appex"]

    /// The outermost bundle of a kind that names things. Also the icon source.
    public static func namingBundle(for path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard let index = components.firstIndex(where: { component in
            namedBundleSuffixes.contains { component.hasSuffix($0) }
        }) else { return nil }
        return components[...index].joined(separator: "/")
    }

    /// `CFBundleDisplayName`, falling back to `CFBundleName`.
    static func bundleName(atPath path: String) -> String? {
        let plist = path + "/Contents/Info.plist"
        guard let data = FileManager.default.contents(atPath: plist),
              let contents = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any]
        else { return nil }

        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let value = contents[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    /// The name macOS itself uses for a running application.
    ///
    /// Preferred over the bundle when both exist, because it is localised and says
    /// what the process *is* as well as what it is called — the probe saw
    /// `AppleIDSettings` resolve to "Apple Account (System Settings)".
    static func runningApplicationName(pid: pid_t) -> String? {
        guard let name = NSRunningApplication(processIdentifier: pid)?.localizedName,
              !name.isEmpty else { return nil }
        return name
    }

    /// Resolves a friendly name, or nil when none exists.
    ///
    /// Filesystem and Launch Services work. Call once per process lifetime through
    /// `ProcessIdentityResolver`'s cache, never on the sampling path (FR-030).
    static func resolve(pid: pid_t, executablePath: String?) -> String? {
        if let name = runningApplicationName(pid: pid) { return name }
        guard let executablePath, let bundle = namingBundle(for: executablePath) else {
            return nil
        }
        return bundleName(atPath: bundle)
    }
}

/// Real application icons, or nothing (FR-002).
///
/// `NSWorkspace.icon(forFile:)` **never returns nil** — it returns a generic
/// document or executable icon when it cannot read the bundle. Treating non-nil
/// as success would put a fake icon beside three quarters of the process table
/// and imply we identified something we did not.
@MainActor
public final class ProcessIconCache {
    /// Cached by bundle path rather than by process: every Helium helper shares
    /// one icon, and the table redraws on every sample.
    private var cache: [String: NSImage?] = [:]
    private lazy var generic = NSWorkspace.shared.icon(for: .unixExecutable)
        .tiffRepresentation

    public init() {}

    public var cachedCount: Int { cache.count }

    /// The application's own icon, or nil when only a generic one is available.
    public func icon(forExecutablePath path: String?) -> NSImage? {
        guard let path, let bundle = ProcessNaming.namingBundle(for: path) else { return nil }
        if let cached = cache[bundle] { return cached }

        let candidate = NSWorkspace.shared.icon(forFile: bundle)
        let resolved: NSImage? =
            candidate.tiffRepresentation == generic ? nil : candidate
        cache[bundle] = resolved
        return resolved
    }
}

extension ResolvedIdentity {
    /// The best name available for this process, with the command as the floor.
    ///
    /// Takes the command rather than storing it because the command belongs to the
    /// sample and the identity does not: identity is resolved once per process
    /// lifetime, and duplicating a field across both would let them disagree.
    public func displayName(command: String) -> String {
        friendlyName ?? ProcessNaming.labelled(command: command)
    }

    public func accessibilityName(command: String) -> String {
        friendlyName ?? ProcessNaming.accessibilityLabel(command: command)
    }

    /// True when we fell through to the kernel's truncated command.
    public func nameIsTruncatedCommand(command: String) -> Bool {
        friendlyName == nil && ProcessNaming.isTruncated(command)
    }
}
