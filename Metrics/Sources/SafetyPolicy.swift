import Darwin
import Foundation

/// Why an action is withheld for something that is not an application.
///
/// Not a `ProtectionReason`: nothing is being protected here. There is simply
/// nothing to bring forward, and saying so is more useful than a button that fails.
extension SafetyPolicy {
    static let notAnApplication =
        "This runs in the background and has no window, so there is nothing to "
        + "bring to the front."
}

/// Why a process is protected from user-directed action (FR-018).
public enum ProtectionReason: String, Sendable, Equatable {
    case systemOwned
    case kernel
    case criticalService

    /// Explained at a category level, never as a lecture about a specific process.
    public var explanation: String {
        switch self {
        case .systemOwned:
            "This is part of macOS and is owned by the system, not by you."
        case .kernel:
            "This is the kernel itself."
        case .criticalService:
            "macOS depends on this to keep the interface, audio or login working."
        }
    }
}

/// What MacSlowdown may do with a process.
///
/// The available set is small on purpose. The Mac App Store build has no process
/// control at all (§7, DR-06), so this is not a list that grows once protection is
/// cleared — it is the complete set for every process, and protection only removes
/// from it.
public enum ProcessAction: String, Sendable, CaseIterable, Identifiable, Codable {
    /// Bring the application to the front.
    case activate
    /// Reveal the executable in Finder.
    case revealInFinder
    /// Hand off to Activity Monitor, which is unsandboxed and sees more than we do.
    case openActivityMonitor
    /// Copy the measurements to the clipboard.
    case copyDiagnostics
    /// Mark the application's load as expected (FR-016).
    case markExpected

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .activate: "Bring to front"
        case .revealInFinder: "Show in Finder"
        case .openActivityMonitor: "Open Activity Monitor"
        case .copyDiagnostics: "Copy diagnostics"
        case .markExpected: "Treat this load as expected"
        }
    }

    /// Every action here observes or hands off. None of them changes how a
    /// process runs, which is what makes the whole set safe by construction.
    public var isDestructive: Bool { false }
}

/// Whether an action is offered, and why not when it is withheld.
public enum ActionAvailability: Sendable, Equatable {
    case available
    /// FR-017: an unavailable action is never shown as though it worked.
    case unavailable(reason: String)

    public var isAvailable: Bool { self == .available }
}

/// Decides what may be done with a process (FR-018).
///
/// This is a **non-overridable** policy. It deliberately takes no user settings:
/// FR-018 requires the classification update independently of user preferences, so
/// there is no path by which a preference can weaken it.
public struct SafetyPolicy: Sendable {
    /// Services macOS depends on for the interface, audio, input or login. Named
    /// explicitly rather than inferred, because getting this wrong destabilises
    /// the machine and the list changes rarely.
    static let criticalServices: Set<String> = [
        "WindowServer", "loginwindow", "launchd", "kernel_task", "coreaudiod",
        "hidd", "SystemUIServer", "Dock", "Finder", "systemstats", "opendirectoryd",
        "securityd", "syspolicyd", "configd", "diskarbitrationd", "notifyd",
    ]

    public init() {}

    /// Why this process is protected, or nil if it is an ordinary user process.
    public func protection(for record: ProcessRecord) -> ProtectionReason? {
        if record.identity.pid <= 1 { return .kernel }
        if Self.criticalServices.contains(record.command) { return .criticalService }
        // Owned by root or a system service account rather than the user.
        if record.uid != getuid() { return .systemOwned }
        return nil
    }

    /// Whether an action may be offered for a process.
    ///
    /// Protection currently withholds only `activate` and `revealInFinder`, because
    /// those are the only actions that touch the process at all. Observation and
    /// hand-off remain available for everything — refusing to let a user copy
    /// diagnostics about WindowServer would be safety theatre, not safety.
    /// - Parameter resolved: the process's identity, where the caller has it.
    ///   Supplying it lets the policy withhold `activate` for a process that has no
    ///   application to bring forward. Activation goes through
    ///   `NSRunningApplication`, which exists only for bundled applications, so
    ///   offering it for a daemon produces a control whose only possible outcome is
    ///   an apology — "Bring to front did not work. node is not a foreground
    ///   application." The rule lives here rather than in each view because it was
    ///   fixed at one call site (TASK-94) and left standing at two others.
    public func availability(
        of action: ProcessAction,
        for record: ProcessRecord,
        resolved: ResolvedIdentity? = nil
    ) -> ActionAvailability {
        if action == .activate, let resolved, resolved.appBundlePath == nil {
            return .unavailable(reason: Self.notAnApplication)
        }
        guard let reason = protection(for: record) else { return .available }

        switch action {
        case .activate, .revealInFinder, .markExpected:
            return .unavailable(reason: reason.explanation)
        case .openActivityMonitor, .copyDiagnostics:
            return .available
        }
    }

    /// The actions to offer for a process. Withheld ones are excluded rather than
    /// shown disabled-but-tempting; the caller can still ask `availability` to
    /// explain the absence.
    public func availableActions(
        for record: ProcessRecord, resolved: ResolvedIdentity? = nil
    ) -> [ProcessAction] {
        ProcessAction.allCases.filter {
            availability(of: $0, for: record, resolved: resolved).isAvailable
        }
    }

    /// What to tell a user who asks why an action is missing. Explains at the
    /// category level and offers what remains, rather than simply refusing.
    public func explanation(for record: ProcessRecord) -> String? {
        guard let reason = protection(for: record) else { return nil }
        return reason.explanation
            + " MacSlowdown will not act on it, but you can still see what it is doing "
            + "and open Activity Monitor for more detail."
    }
}
