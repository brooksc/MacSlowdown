import AppKit
import Foundation
import Testing

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
}
