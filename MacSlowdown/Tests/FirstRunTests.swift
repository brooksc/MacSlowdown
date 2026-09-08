import Foundation
import Testing

@testable import MacSlowdown

/// A throwaway defaults suite, so the first-run path is exercised on a machine
/// that has already run the app.
///
/// This is the reason `FirstRunState` takes its `UserDefaults`: without the seam,
/// the only computer that could test a first launch would be one that had never
/// had a first launch, and the screen would ship unexercised.
private func emptyDefaults() -> UserDefaults {
    let suite = "MacSlowdownTests.firstRun.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@MainActor
@Suite("First run, when it appears")
struct FirstRunStateTests {
    @Test("A machine that has never run the app is owed the screen")
    func freshInstallIsOwedTheScreen() {
        let state = FirstRunState(defaults: emptyDefaults())
        #expect(!state.hasCompleted)
        #expect(state.shouldPresent)
    }

    @Test("Starting to watch records that the screen is no longer owed")
    func completingRecordsIt() {
        let defaults = emptyDefaults()
        let state = FirstRunState(defaults: defaults)
        state.complete()

        #expect(state.hasCompleted)
        #expect(!state.shouldPresent)
        #expect(defaults.bool(forKey: FirstRunState.defaultsKey))
    }

    @Test("The record survives a relaunch")
    func survivesRelaunch() {
        let defaults = emptyDefaults()
        FirstRunState(defaults: defaults).complete()
        #expect(!FirstRunState(defaults: defaults).shouldPresent)
    }

    @Test("The window is opened on a fresh install and never on a returning one")
    func opensOnlyWhenOwed() {
        var opens = 0
        FirstRunWindowOpener.action = { opens += 1 }
        defer { FirstRunWindowOpener.action = nil }

        let defaults = emptyDefaults()
        let state = FirstRunState(defaults: defaults)
        #expect(FirstRunWindowOpener.presentIfNeeded(state: state))
        #expect(opens == 1)

        state.complete()
        #expect(!FirstRunWindowOpener.presentIfNeeded(state: state))
        #expect(opens == 1, "a returning user must not be introduced again")
    }

    /// TASK-65.20's criterion #4, and the reason the invisible window was survivable
    /// rather than fatal: the screen was never *seen*, and because only the button
    /// records anything, it was still owed at the next launch. A dismissal, a crash,
    /// or a window nobody could see all leave the same state.
    @Test("A first run that was never completed is presented again next launch")
    func unseenFirstRunIsStillOwed() {
        var opens = 0
        FirstRunWindowOpener.action = { opens += 1 }
        defer { FirstRunWindowOpener.action = nil }

        let defaults = emptyDefaults()
        #expect(FirstRunWindowOpener.presentIfNeeded(state: FirstRunState(defaults: defaults)))
        #expect(opens == 1)

        // A relaunch: a new state over the same container, nothing recorded.
        let next = FirstRunState(defaults: defaults)
        #expect(next.shouldPresent, "nothing but the button may retire the screen")
        #expect(FirstRunWindowOpener.presentIfNeeded(state: next))
        #expect(opens == 2)

        // And once, finally, it is read and answered.
        next.complete()
        #expect(!FirstRunState(defaults: defaults).shouldPresent)
    }

    /// Distinguishing "no window was asked for" from "a window was asked for and
    /// nothing happened" — the same reason `MainWindowOpener.open` reports.
    @Test("With no scene registered, presenting reports that nothing happened")
    func noSceneReportsFailure() {
        FirstRunWindowOpener.action = nil
        let state = FirstRunState(defaults: emptyDefaults())
        #expect(!FirstRunWindowOpener.presentIfNeeded(state: state))
    }
}

@MainActor
@Suite("First run, what it promises")
struct FirstRunCopyTests {
    /// A-05 and FR-029. The screen that asks for two permissions is the screen
    /// where the local-only guarantee has to be made, and it has to be made twice:
    /// once as the standing promise, once where the user might wonder about a
    /// server.
    @Test("The local-only guarantee is stated, and no account or server is implied")
    func localOnlyGuarantee() {
        // The standing promise moved out of the subtitle when the subtitle became
        // "worth 30 seconds now" (design 6b); the guarantee itself is unchanged
        // and still made twice — in the closing paragraph, and in the report
        // statement, which is the one place a user might wonder where their own
        // words go.
        #expect(FirstRunCopy.closing.contains("stays on this Mac"))
        let closing = FirstRunCopy.closing.lowercased()
        #expect(closing.contains("nothing uploaded"))
        #expect(closing.contains("no account"))
        #expect(closing.contains("no server"))
    }

    /// FR-013 and FR-038, and the reason this screen is worth more than it looks.
    /// `probe/FINDINGS.md`: measurability is decided by uid, and roughly 40
    /// percentage points of busy CPU on a real machine belong to processes the
    /// sandboxed build is not permitted to measure. Meeting that gap for the first
    /// time inside a contributor list reads as broken arithmetic; meeting it here
    /// reads as a limit the app was honest about.
    @Test("The unattributable share is explained before the user can encounter it")
    func unattributableExpectationIsSet() {
        let text = FirstRunCopy.unattributable.lowercased()
        // Named, so the limit is concrete rather than a shrug about "system stuff".
        #expect(text.contains("backups"))
        #expect(text.contains("indexing"))
        #expect(text.contains("window server"))
        // And the *reason*, which is what stops it reading as an excuse: it is a
        // uid boundary, not a shortcoming we could code around.
        #expect(text.contains("another user"))
        #expect(text.contains("app store"))
        // The promise that goes with the limitation: the share is always shown,
        // never silently dropped, which is what stops contributor lists failing to
        // sum without saying so.
        #expect(text.contains("show you how much that is"))
        #expect(FirstRunCopy.unattributableTitle.contains("invisible to us"),
                "stated as a headline, not buried in a caveat")
    }

    @Test("Both permissions are named, with the reason each is wanted")
    func bothPermissionsExplained() {
        // The toggle now names *which* conditions interrupt rather than promising
        // notifications in general, because CPU no longer interrupts (FR-014
        // amendment 1) and a general promise would be one we break by design.
        #expect(FirstRunCopy.notificationsTitle.lowercased().contains("memory"))
        #expect(FirstRunCopy.notificationsTitle.lowercased().contains("disk"))
        #expect(FirstRunCopy.notificationsDetail.contains("Not CPU"),
                "the sentence that prevents 'why didn't you tell me' later")
        #expect(FirstRunCopy.notificationsDetail.lowercased().contains("recorded"),
                "FR-014 amendment 1: not interrupting is not not-watching")
        #expect(FirstRunCopy.loginItemTitle == "Start watching at login")
        #expect(!FirstRunCopy.loginItemDetail.isEmpty)
    }

    @Test("Nothing on the screen uses the forbidden vocabulary")
    func languageRules() {
        let all = [
            FirstRunCopy.title, FirstRunCopy.promise,
            FirstRunCopy.notificationsTitle, FirstRunCopy.notificationsDetail,
            FirstRunCopy.loginItemTitle, FirstRunCopy.loginItemDetail,
            FirstRunCopy.unattributable, FirstRunCopy.closing, FirstRunCopy.startButton,
        ].joined(separator: " ").lowercased()

        for word in ["optimize", "optimise", "clean up", "boost", "free up memory", "speed up"] {
            #expect(!all.contains(word), "\"\(word)\" overclaims what the app does")
        }
        #expect(!all.isEmpty)
    }

    /// It is an introduction, not a second Settings screen. `SettingsView` owns
    /// sensitivity, thresholds, per-app rules, retention and the menu bar item;
    /// first run introduces exactly the two permissions the app cannot grant
    /// itself.
    @Test("First run introduces two things, and does not restate Settings")
    func doesNotDuplicateSettings() {
        let all = [FirstRunCopy.title, FirstRunCopy.unattributable, FirstRunCopy.closing]
            .joined(separator: " ").lowercased()
        for setting in ["sensitivity", "threshold", "retention", "menu bar"] {
            #expect(!all.contains(setting), "\(setting) belongs to Settings")
        }
        #expect(FirstRunCopy.closing.lowercased().contains("changeable later"),
                "and it says the choices are not final")
    }
}

@MainActor
@Suite("First run, the login item it cannot promise")
struct FirstRunLoginItemTests {
    /// TASK-16 is parked and a build outside an Applications folder genuinely
    /// cannot register a login item. The screen must show the real state rather
    /// than a toggle that looks operable and silently does nothing.
    @Test("A copy outside Applications reports the state honestly and is not adjustable")
    func unregisterableLocationIsSurfaced() throws {
        let home = URL(fileURLWithPath: "/Users/someone")
        let derived = URL(fileURLWithPath: "/Users/someone/code/.build/Debug/MacSlowdown.app")
        let directory = try #require(
            LoginItem.unregisterableLocation(bundleURL: derived, home: home))

        let state = LoginItem.State.unavailableFromThisLocation(directory: directory)
        #expect(!LoginItem.isAdjustable(state))
        let explanation = LoginItem.explanation(for: state)
        #expect(explanation.contains("Applications"))
        #expect(explanation.contains("Nothing is wrong with the app"))
    }

    @Test("An installed copy is adjustable")
    func installedCopyIsAdjustable() {
        let home = URL(fileURLWithPath: "/Users/someone")
        let installed = URL(fileURLWithPath: "/Applications/MacSlowdown.app")
        #expect(LoginItem.unregisterableLocation(bundleURL: installed, home: home) == nil)
        #expect(LoginItem.isAdjustable(.disabled))
        #expect(LoginItem.isAdjustable(.enabled))
    }
}
