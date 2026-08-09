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
    ///
    /// Some commands are not names at all — a bare version number, or a reverse-DNS
    /// bundle identifier. Those are shown as unidentified rather than presented as
    /// though they were what the application is called (FR-002).
    public static func labelled(command: String) -> String {
        let shown = isTruncated(command) ? command + "…" : command
        return isNonName(command) ? unidentified(shown) : shown
    }

    /// Spoken form, since an ellipsis conveys nothing to VoiceOver (FR-034).
    public static func accessibilityLabel(command: String) -> String {
        let suffix = isTruncated(command) ? ", name shortened by the system" : ""
        return isNonName(command)
            ? "Unidentified process, \(command)\(suffix)"
            : command + suffix
    }

    // MARK: - Strings that are not names

    /// How a value we could not turn into a name is presented.
    ///
    /// The evidence is kept beside the label rather than dropped: "we could not
    /// identify this, and here is what the system told us" is a stronger statement
    /// than either half alone, and it is what FR-038 asks for.
    public static func unidentified(_ evidence: String) -> String {
        "Unidentified process (\(evidence))"
    }

    /// A bare version number: `2.1.226`, `150.0.7871.186`.
    ///
    /// Measured on this machine: `~/.local/bin/claude` links to
    /// `~/.local/share/claude/versions/2.1.226`, so the executable **file** is named
    /// after the version and `p_comm` is `2.1.226`. Eight such processes appeared in
    /// the inventory under four indistinguishable version numbers.
    public static func isVersionNumber(_ value: String) -> Bool {
        guard value.contains(where: \.isNumber) else { return false }
        return value.allSatisfy { $0.isNumber || $0 == "." }
    }

    /// A reverse-DNS bundle identifier: `com.apple.Safari.History`.
    ///
    /// Deliberately narrow. The first segment must be a short lowercase token, which
    /// is what a top-level domain looks like, so `SimLaunchHost.arm64.xpc` and
    /// `python3.13` are not swept up. Three segments minimum, for the same reason.
    public static func isBundleIdentifier(_ value: String) -> Bool {
        let segments = value.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 3, segments.allSatisfy({ !$0.isEmpty }),
              !value.contains(" ")
        else { return false }
        let first = segments[0]
        return (2...4).contains(first.count)
            && first.allSatisfy { $0.isLowercase && $0.isLetter }
    }

    /// True when this string tells the user nothing about what the process is, and
    /// worse, looks like it does.
    ///
    /// A version number and a truncated identifier are both more harmful than an
    /// obviously-technical command such as `mdworker_shared`: `2.1.220` reads as a
    /// name, and `com.apple.Safari…` reads as Safari when it is in fact
    /// `com.apple.Safari.History`.
    public static func isNonName(_ value: String) -> Bool {
        isVersionNumber(value) || isBundleIdentifier(value)
    }

    /// Path components that name a layout, not a program.
    private static let structuralComponents: Set<String> = [
        "bin", "sbin", "libexec", "lib", "share", "local", "opt", "usr", "var",
        "versions", "current", "contents", "macos", "helpers", "resources",
        "frameworks", "applications", "users", "library", "node_modules", ".local",
    ]

    /// The program a version-named executable belongs to, taken from its install path.
    ///
    /// `~/.local/share/claude/versions/2.1.226` is the program `claude` installed at
    /// version 2.1.226 — the directory above the version says so. Only two levels are
    /// searched: further up lies the home directory, and a user account name is not a
    /// process name and does not belong on screen.
    ///
    /// Returns nil rather than reaching for something weaker, so the caller can say
    /// "unidentified" instead of showing a fragment.
    static func installationName(forExecutablePath path: String) -> String? {
        var components = path.split(separator: "/").map(String.init)
        guard let executable = components.popLast(), isVersionNumber(executable) else {
            return nil
        }
        for index in components.indices.suffix(2).reversed() {
            let candidate = components[index]
            // A directory directly under /Users or /home is an account name. It is
            // not a process name and it does not belong on screen (A-05, FR-029).
            let parent = index > 0 ? components[index - 1].lowercased() : ""
            guard !isVersionNumber(candidate),
                  !structuralComponents.contains(candidate.lowercased()),
                  parent != "users", parent != "home"
            else { continue }
            return candidate
        }
        return nil
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

    /// The name the system declares for this process: Launch Services first, then
    /// the outermost naming bundle's `Info.plist`.
    static func declaredName(pid: pid_t, executablePath: String?) -> String? {
        if let name = runningApplicationName(pid: pid) { return name }
        guard let executablePath, let bundle = namingBundle(for: executablePath) else {
            return nil
        }
        return bundleName(atPath: bundle)
    }

    /// Resolves a friendly name, or nil when none exists.
    ///
    /// Filesystem and Launch Services work. Call once per process lifetime through
    /// `ProcessIdentityResolver`'s cache, never on the sampling path (FR-030).
    static func resolve(pid: pid_t, executablePath: String?) -> String? {
        // A declared name can itself be an identifier: measured on this machine,
        // `PressAndHold.app` declares `CFBundleName` = `com.apple.PressAndHold`, and
        // `CoreSimulatorService` registers with Launch Services under its own
        // identifier. Having a source for a string does not make it a name.
        if let name = declaredName(pid: pid, executablePath: executablePath) {
            return isNonName(name) ? unidentified(name) : name
        }
        guard let executablePath else { return nil }

        // No display name exists. The command alone would now be shown, and for two
        // shapes of command that is worse than saying nothing: the path can do
        // better, and it is a measurement rather than a guess.
        let executable = (executablePath as NSString).lastPathComponent
        if isVersionNumber(executable) {
            // `2.1.226` is a version, not a program. The install path names the
            // program; where it does not, the row says so.
            return installationName(forExecutablePath: executablePath)
                ?? unidentified(executable)
        }
        if isBundleIdentifier(executable) {
            // The file name is the whole identifier, where `p_comm` is cut at 16
            // bytes — `com.apple.Safari.History` rather than `com.apple.Safari…`,
            // which reads as Safari and is not.
            return unidentified(executable)
        }
        return nil
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
    private lazy var generic = ProcessIconCache.fingerprint(
        NSWorkspace.shared.icon(for: .unixExecutable))

    public init() {}

    public var cachedCount: Int { cache.count }

    /// The application's own icon, or nil when only a generic one is available.
    public func icon(forExecutablePath path: String?) -> NSImage? {
        guard let path, let bundle = ProcessNaming.namingBundle(for: path) else { return nil }
        if let cached = cache[bundle] { return cached }

        let candidate = NSWorkspace.shared.icon(forFile: bundle)
        // Fails closed: an icon we cannot fingerprint is treated as generic, so
        // the interface omits an icon rather than claiming a placeholder is the
        // application's own (FR-002).
        let resolved: NSImage? = {
            guard let generic,
                  let mark = ProcessIconCache.fingerprint(candidate),
                  mark != generic
            else { return nil }
            return candidate
        }()
        cache[bundle] = resolved
        return resolved
    }

    /// A small raster of an icon, for equality only — never shown to anyone.
    ///
    /// This used to compare `tiffRepresentation` directly, which was correct and
    /// cost **70 MB per call**: an icon from IconServices carries representations
    /// up to 1024×1024 at every scale, and asking for TIFF flattens all of them
    /// into one contiguous `Data`. Once per cache miss across a full process table
    /// that moved ~8 GB through malloc, and draining the autorelease pool did not
    /// give it back — it left the app at a 292 MB footprint against FR-030's
    /// 100 MB budget (TASK-55.1; measurements in `probe/FINDINGS.md`).
    ///
    /// 32 pt is large enough that two different icons do not collide and small
    /// enough to be free: 4 KB per raster, and 0.17 MB to classify every bundle on
    /// the measured machine against 1693 MB for the TIFF comparison. It agreed
    /// with that comparison on all 117 bundles, and on the negative control —
    /// `/bin/ls` and `/usr/bin/true` still classify as generic, which is what
    /// proves it discriminates rather than answering "real" for everything.
    static func fingerprint(_ image: NSImage) -> Data? {
        let side = 32
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32)
        else { return nil }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        return rep.representation(using: .png, properties: [:])
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
