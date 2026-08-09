import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import Metrics

@Suite("Truncated command names")
struct TruncationTests {
    /// `p_comm` is 16 bytes. The kernel does not tell us it cut anything, so
    /// length is the only signal — which is why the boundary itself is the test.
    @Test("A command at the 16-byte limit is treated as truncated")
    func boundary() {
        #expect(ProcessNaming.commandLimit == 16)
        #expect(!ProcessNaming.isTruncated(String(repeating: "a", count: 15)))
        #expect(ProcessNaming.isTruncated(String(repeating: "a", count: 16)))

        // The names that prompted this, measured on a real machine.
        #expect(ProcessNaming.isTruncated("Spotify Helper ("))
        #expect(ProcessNaming.isTruncated("Helium Helper (R"))
        #expect(!ProcessNaming.isTruncated("bash"))
    }

    /// The point of the whole exercise: a fragment must never be shown as though
    /// it were the complete name (FR-002).
    @Test("A truncated command is shown with an ellipsis, a short one unchanged")
    func labelling() {
        #expect(ProcessNaming.labelled(command: "Spotify Helper (") == "Spotify Helper (…")
        #expect(ProcessNaming.labelled(command: "bash") == "bash")
    }

    /// An ellipsis is silent to VoiceOver, so the spoken form has to say it.
    @Test("VoiceOver is told the name was shortened, not given a bare fragment")
    func spokenForm() {
        let spoken = ProcessNaming.accessibilityLabel(command: "Spotify Helper (")
        #expect(spoken.contains("shortened"))
        #expect(!spoken.hasSuffix("…"))
        #expect(ProcessNaming.accessibilityLabel(command: "bash") == "bash")
    }

    /// Multi-byte names must be measured in bytes, as the kernel does, not in
    /// characters — otherwise a name cut at 16 bytes reads as short enough.
    @Test("Truncation is measured in bytes, matching the kernel")
    func bytesNotCharacters() {
        let eightEmoji = String(repeating: "🙂", count: 4)  // 16 bytes, 4 characters
        #expect(eightEmoji.count == 4)
        #expect(eightEmoji.utf8.count == 16)
        #expect(ProcessNaming.isTruncated(eightEmoji))
    }
}

/// TASK-57.1. Four rows of the inventory were called `2.1.220`, and a fifth
/// `com.apple.Safari…`. Both are strings the resolution order produced as a last
/// resort, and both read as names when they are not.
@Suite("Commands that are not names")
struct NonNameTests {
    /// Measured: `~/.local/bin/claude` links to
    /// `~/.local/share/claude/versions/2.1.226`, so the executable file *is* the
    /// version and the kernel's `p_comm` is `2.1.226`.
    @Test("A bare version number is recognised, an ordinary name is not")
    func versionNumbers() {
        #expect(ProcessNaming.isVersionNumber("2.1.226"))
        #expect(ProcessNaming.isVersionNumber("150.0.7871.186"))
        #expect(ProcessNaming.isVersionNumber("26"))
        #expect(!ProcessNaming.isVersionNumber("node"))
        #expect(!ProcessNaming.isVersionNumber("python3.13"))
        #expect(!ProcessNaming.isVersionNumber(""))
        #expect(!ProcessNaming.isVersionNumber("..."))
    }

    @Test("A reverse-DNS identifier is recognised without sweeping up dotted names")
    func bundleIdentifiers() {
        #expect(ProcessNaming.isBundleIdentifier("com.apple.Safari.History"))
        #expect(ProcessNaming.isBundleIdentifier("io.tailscale.ipn.macsys"))
        #expect(ProcessNaming.isBundleIdentifier("com.apple.geod"))
        // Two segments is a file name, not an identifier.
        #expect(!ProcessNaming.isBundleIdentifier("python3.13"))
        // A long first segment is a program name that happens to have dots.
        #expect(!ProcessNaming.isBundleIdentifier("SimLaunchHost.arm64.xpc"))
        #expect(!ProcessNaming.isBundleIdentifier("mdworker_shared"))
        #expect(!ProcessNaming.isBundleIdentifier("com..apple"))
    }

    /// The rule that matters: neither shape may be shown as though it were a name.
    @Test("A version number and an identifier are labelled unidentified")
    func labelling() {
        #expect(ProcessNaming.labelled(command: "2.1.220")
                == "Unidentified process (2.1.220)")
        #expect(ProcessNaming.labelled(command: "com.apple.Safari")
                == "Unidentified process (com.apple.Safari…)")
        // Everything else is untouched: an ordinary daemon still reads as itself.
        #expect(ProcessNaming.labelled(command: "mdworker_shared") == "mdworker_shared")
        #expect(ProcessNaming.labelled(command: "MTLCompilerServi") == "MTLCompilerServi…")
    }

    @Test("VoiceOver hears that the process is unidentified, not a version number")
    func spokenForm() {
        let spoken = ProcessNaming.accessibilityLabel(command: "2.1.220")
        #expect(spoken.hasPrefix("Unidentified process"))
        #expect(spoken.contains("2.1.220"))
        #expect(!spoken.contains("…"))

        let identifier = ProcessNaming.accessibilityLabel(command: "com.apple.Safari")
        #expect(identifier.hasPrefix("Unidentified process"))
        #expect(identifier.contains("shortened"))
    }

    /// The real path, from the machine that produced the defect.
    @Test("A version-numbered install directory names the program it installed")
    func installationName() {
        #expect(ProcessNaming.installationName(
            forExecutablePath: "/Users/someone/.local/share/claude/versions/2.1.226")
            == "claude")
        #expect(ProcessNaming.installationName(
            forExecutablePath: "/opt/homebrew/Cellar/pmg/0.17.0") == "pmg")
    }

    /// The guard against inventing a name: structural directories say nothing about
    /// the program, and the search stops before it reaches a user account name.
    @Test("A layout directory is never used as a name")
    func structuralDirectoriesRejected() {
        #expect(ProcessNaming.installationName(forExecutablePath: "/usr/local/2.1.1") == nil)
        #expect(ProcessNaming.installationName(
            forExecutablePath: "/Users/someone/2.1.1") == nil)
        // Not a version at all: this fallback must not fire.
        #expect(ProcessNaming.installationName(
            forExecutablePath: "/opt/homebrew/Cellar/node/26.0.0/bin/node") == nil)
    }

    /// End to end through the resolution order, for a path with no bundle anywhere in
    /// it — the case that produced four identical `2.1.220` rows.
    @Test("Resolution names a version-numbered executable after its install directory")
    func resolvesThroughInstallPath() {
        // pid 0 has no running application, so this exercises the path fallback.
        let name = ProcessNaming.resolve(
            pid: -1,
            executablePath: "/Users/someone/.local/share/claude/versions/2.1.226")
        #expect(name == "claude")
    }

    @Test("An unrecoverable version number resolves to unidentified, not to itself")
    func resolvesToUnidentified() {
        #expect(ProcessNaming.resolve(pid: -1, executablePath: "/usr/local/2.1.1")
                == "Unidentified process (2.1.1)")
    }

    /// `p_comm` is cut at 16 bytes; the executable file name is not. Recovering it
    /// turns `com.apple.Safari…` — which reads as Safari — into the whole identifier.
    @Test("A bundle-identifier executable is shown whole, and as unidentified")
    func resolvesIdentifierFromPath() {
        let name = ProcessNaming.resolve(
            pid: -1,
            executablePath: "/System/Volumes/Preboot/Cryptexes/App/usr/libexec/"
                + "com.apple.Safari.History")
        #expect(name == "Unidentified process (com.apple.Safari.History)")
    }

    /// Having a source for a string does not make it a name. Measured on this
    /// machine: `PressAndHold.app` declares `CFBundleName` = `com.apple.PressAndHold`,
    /// and `CoreSimulatorService` registers with Launch Services under its own
    /// identifier — so the check has to sit after the declared name, not only on the
    /// path fallback.
    @Test("A declared name that is itself an identifier is still not shown as a name")
    func declaredIdentifierRejected() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("naming-\(UUID().uuidString)")
        let bundle = root.appendingPathComponent("Thing.app")
        let contents = bundle.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(
            at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let plist: [String: Any] = ["CFBundleName": "com.example.thing"]
        try PropertyListSerialization
            .data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))

        let executable = contents.path + "/MacOS/Thing"
        #expect(ProcessNaming.bundleName(atPath: bundle.path) == "com.example.thing")
        #expect(ProcessNaming.resolve(pid: -1, executablePath: executable)
                == "Unidentified process (com.example.thing)")
    }

    /// Everything that is not one of the two shapes keeps falling through to the
    /// command, exactly as before.
    @Test("An ordinary daemon still resolves to no name at all")
    func ordinaryDaemonUnchanged() {
        #expect(ProcessNaming.resolve(pid: -1, executablePath: "/usr/sbin/notifyd") == nil)
        #expect(ProcessNaming.resolve(pid: -1, executablePath: nil) == nil)
    }
}

@Suite("Naming bundles")
struct NamingBundleTests {
    @Test("The outermost .app is the naming bundle, not a nested helper")
    func outermostApp() {
        let path = "/Applications/Helium.app/Contents/Frameworks/"
            + "Helium Helper.app/Contents/MacOS/Helium Helper"
        #expect(ProcessNaming.namingBundle(for: path) == "/Applications/Helium.app")
    }

    /// System Settings panes live in `.appex`, and it is the only reason 38 of
    /// them get a real name rather than a fragment.
    @Test("An .appex is a naming bundle")
    func appExtension() {
        let path = "/System/Library/ExtensionKit/Extensions/AppleIDSettings.appex/"
            + "Contents/MacOS/AppleIDSettings"
        #expect(ProcessNaming.namingBundle(for: path)?.hasSuffix("AppleIDSettings.appex") == true)
    }

    /// Deliberately excluded: 269 processes ran from inside a framework during the
    /// probe and it essentially never yields a better name than the command.
    @Test("A framework is not a naming bundle")
    func frameworkExcluded() {
        let path = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/"
            + "com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent"
        #expect(ProcessNaming.namingBundle(for: path) == nil)
    }

    @Test("A plain daemon has no naming bundle")
    func daemonHasNone() {
        #expect(ProcessNaming.namingBundle(for: "/usr/sbin/notifyd") == nil)
        #expect(ProcessNaming.namingBundle(for: "/bin/zsh") == nil)
    }

    /// The app we are running from is a real bundle on disk, so this exercises the
    /// actual Info.plist read rather than a fabricated path.
    @Test("A real bundle on disk yields its declared name")
    func readsRealBundle() throws {
        let ourBundle = try #require(Bundle.main.bundlePath as String?)
        guard ourBundle.hasSuffix(".app") else { return }  // not app-hosted
        let name = ProcessNaming.bundleName(atPath: ourBundle)
        #expect(name != nil)
        #expect(name?.isEmpty == false)
    }

    @Test("A path that is not a bundle yields no name rather than a guess")
    func missingBundle() {
        #expect(ProcessNaming.bundleName(atPath: "/no/such/thing.app") == nil)
    }
}

@Suite("Resolved names")
struct ResolvedNameTests {
    private func identity(friendlyName: String?) -> ResolvedIdentity {
        ResolvedIdentity(executablePath: "/Applications/Thing.app/Contents/MacOS/Thing",
                         appBundlePath: "/Applications/Thing.app",
                         bundleID: "com.example.thing", teamID: nil,
                         friendlyName: friendlyName)
    }

    @Test("A resolved name wins over the command")
    func resolvedWins() {
        let resolved = identity(friendlyName: "Spotify")
        #expect(resolved.displayName(command: "Spotify Helper (") == "Spotify")
        #expect(!resolved.nameIsTruncatedCommand(command: "Spotify Helper ("))
    }

    /// The honest floor: a daemon with no name anywhere gets its command, marked.
    @Test("With no resolved name the command is used and marked as truncated")
    func fallsBackToCommand() {
        let resolved = identity(friendlyName: nil)
        #expect(resolved.displayName(command: "MTLCompilerServi") == "MTLCompilerServi…")
        #expect(resolved.nameIsTruncatedCommand(command: "MTLCompilerServi"))
        #expect(resolved.accessibilityName(command: "MTLCompilerServi").contains("shortened"))
    }

    @Test("A short command needs no marking")
    func shortCommandUnmarked() {
        let resolved = identity(friendlyName: nil)
        #expect(resolved.displayName(command: "zsh") == "zsh")
        #expect(!resolved.nameIsTruncatedCommand(command: "zsh"))
    }

    /// FR-003's four cases in one place: a bundled app, an extension, a daemon
    /// with a short name, and a daemon with a truncated one.
    @Test("Every naming case produces something showable")
    func everyCaseIsShowable() {
        let cases: [(friendly: String?, command: String)] = [
            ("Helium", "Helium Helper (R"),
            ("Apple Account (System Settings)", "AppleIDSettings"),
            (nil, "notifyd"),
            (nil, "SetStoreUpdateSe"),
        ]
        for subject in cases {
            let name = identity(friendlyName: subject.friendly)
                .displayName(command: subject.command)
            #expect(!name.isEmpty)
            #expect(name != subject.command || !ProcessNaming.isTruncated(subject.command))
        }
    }
}

@Suite("Contributor labels")
struct ContributorLabelTests {
    private func usage(command: String, displayName: String?) -> ProcessCPUUsage {
        ProcessCPUUsage(identity: ProcessIdentity(pid: 1, startTime: 1),
                        command: command, displayName: displayName,
                        percentOfOneCore: 10, residentBytes: 0)
    }

    /// The defect this whole change exists to fix: the popover read
    /// "Spotify Helper (" because it took the command directly.
    @Test("A contributor's label is the resolved name when there is one")
    func labelPrefersResolved() {
        #expect(usage(command: "Spotify Helper (", displayName: "Spotify").label == "Spotify")
    }

    @Test("A contributor with no resolved name is labelled as truncated")
    func labelMarksTruncation() {
        #expect(usage(command: "Spotify Helper (", displayName: nil).label
                == "Spotify Helper (…")
    }

    /// Every surface reads `label`, so none of them can drift back to `command`.
    @Test("A short command passes through unchanged")
    func shortCommandUnchanged() {
        #expect(usage(command: "bash", displayName: nil).label == "bash")
    }
}

@MainActor
@Suite("Icons")
struct IconCacheTests {
    /// `NSWorkspace.icon(forFile:)` never returns nil — it returns a generic icon.
    /// Treating that as success would put a fake icon beside three quarters of the
    /// process table.
    @Test("A path with no real icon returns nil rather than a generic one")
    func genericIconRejected() {
        let cache = ProcessIconCache()
        #expect(cache.icon(forExecutablePath: "/usr/sbin/notifyd") == nil)
        #expect(cache.icon(forExecutablePath: nil) == nil)
        #expect(cache.icon(forExecutablePath: "/bin/zsh") == nil)
    }

    @Test("A real application yields its own icon")
    func realIcon() throws {
        let cache = ProcessIconCache()
        let finder = "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"
        try #require(FileManager.default.fileExists(atPath: finder))
        #expect(cache.icon(forExecutablePath: finder) != nil)
    }

    /// The table redraws every sample and Helium has 18 helpers, so resolution has
    /// to be shared by bundle rather than repeated per process.
    @Test("Icons are cached per bundle, not per process")
    func cachedPerBundle() {
        let cache = ProcessIconCache()
        let helpers = [
            "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder",
            "/System/Library/CoreServices/Finder.app/Contents/Helpers/One",
            "/System/Library/CoreServices/Finder.app/Contents/Helpers/Two",
        ]
        for path in helpers { _ = cache.icon(forExecutablePath: path) }
        #expect(cache.cachedCount == 1, "three processes in one bundle is one lookup")
    }

    @Test("A missing bundle is cached as absent rather than retried every sample")
    func absenceIsCached() {
        let cache = ProcessIconCache()
        _ = cache.icon(forExecutablePath: "/no/such/App.app/Contents/MacOS/App")
        _ = cache.icon(forExecutablePath: "/no/such/App.app/Contents/MacOS/App")
        #expect(cache.cachedCount == 1)
    }

    /// The negative control for the 32 pt fingerprint that replaced comparing
    /// `tiffRepresentation` (TASK-55.1).
    ///
    /// The failure mode being guarded is not "too expensive", it is a comparison
    /// that answers *real* for everything — that would put a generic placeholder
    /// beside three quarters of the process table and call it the application's
    /// icon, which is worse than the 70 MB-per-call allocation it replaced.
    /// Every bundle on the measured machine classified as real, so agreement with
    /// the old method could not distinguish a working comparison from one that
    /// never says "generic". These two do.
    @Test("Plain executables still fingerprint as generic, so the comparison discriminates")
    func fingerprintRejectsGenericIcons() throws {
        for path in ["/bin/ls", "/usr/bin/true"] {
            try #require(FileManager.default.fileExists(atPath: path))
            let icon = NSWorkspace.shared.icon(forFile: path)
            #expect(ProcessIconCache.fingerprint(icon)
                == ProcessIconCache.fingerprint(
                    NSWorkspace.shared.icon(for: .unixExecutable)),
                "\(path) has no icon of its own and must compare equal to the generic one")
        }
    }

    /// The other half of the control: a real application must *not* collide with
    /// the generic icon at 32 pt. A fingerprint small enough to be free is only
    /// useful if it is still large enough to tell two icons apart.
    @Test("A real application's icon does not collide with the generic one")
    func fingerprintSeparatesRealIcons() throws {
        let finder = "/System/Library/CoreServices/Finder.app"
        try #require(FileManager.default.fileExists(atPath: finder))
        let generic = ProcessIconCache.fingerprint(
            NSWorkspace.shared.icon(for: .unixExecutable))
        let real = ProcessIconCache.fingerprint(NSWorkspace.shared.icon(forFile: finder))
        #expect(real != nil)
        #expect(real != generic)
    }
}
