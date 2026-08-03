import AppKit
import Metrics

/// Runs the safe actions (FR-017).
///
/// Every action here either brings something forward, reveals it, hands off to
/// another tool, or copies text. None of them changes how a process runs — there
/// is no code path in this file that could, which is what makes FR-037's "no
/// dormant privileged paths" true by inspection rather than by promise.
@MainActor
struct ActionPerformer {
    let safety = SafetyPolicy()

    /// Performs an action, reporting what actually happened rather than assuming
    /// the request succeeded (FR-017).
    func perform(
        _ action: ProcessAction,
        on record: ProcessRecord,
        resolved: ResolvedIdentity?,
        diagnostics: @autoclosure () -> String = ""
    ) -> ActionResult {
        let availability = safety.availability(of: action, for: record)
        if case .unavailable(let reason) = availability {
            return .withheld(reason: reason)
        }

        switch action {
        case .activate:
            guard let application = NSRunningApplication(
                processIdentifier: record.identity.pid) else {
                // The process exists in our snapshot but has no GUI presence, or
                // exited between sampling and acting.
                return .failed(reason: "\(record.command) is not a foreground application.")
            }
            return application.activate(options: [])
                ? .succeeded
                : .failed(reason: "macOS did not bring \(record.command) forward.")

        case .revealInFinder:
            guard let path = resolved?.executablePath else {
                return .failed(reason: "The location of \(record.command) is not available.")
            }
            let url = URL(fileURLWithPath: resolved?.appBundlePath ?? path)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return .succeeded

        case .openActivityMonitor:
            let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
            guard FileManager.default.fileExists(atPath: url.path) else {
                return .failed(reason: "Activity Monitor was not found on this Mac.")
            }
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
            return .succeeded

        case .copyDiagnostics:
            let text = diagnostics()
            guard !text.isEmpty else {
                return .failed(reason: "There is nothing to copy yet.")
            }
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setString(text, forType: .string)
                ? .succeeded
                : .failed(reason: "The clipboard did not accept the text.")

        case .markExpected:
            // Handled by the caller, which owns the policy store. Reaching here
            // means the caller forgot, so say so rather than silently succeeding.
            return .failed(reason: "Marking as expected is handled in settings.")
        }
    }
}
