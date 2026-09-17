#if DEBUG
import Metrics
import SwiftUI

/// Previews for the surfaces a VM capture run cannot reach.
///
/// **The division of labour.** `probe/vm-capture.sh` photographs the *running*
/// app's main-window sections, which is the only way to settle anything about the
/// real window frame, `LSUIElement` behaviour or live data. It cannot reach a
/// sheet, because reaching one means clicking, and SwiftUI's accessibility tree
/// is not walkable by System Events on macOS 26. So the sheets are previewed
/// instead, and the previews carry the constraint with them: they answer layout,
/// truncation and copy, and they answer nothing about presentation, focus or
/// dismissal. A criterion about *being shown* is not met by a render here.
///
/// Every fixture below is a placeholder in its numbers and deliberate in its
/// shape. Where a figure comes from a measured sweep it says so.

// MARK: - Shared fixtures

private let origin = Date(timeIntervalSince1970: 1_700_000_000)
private let contributorIdentity = ProcessIdentity(pid: 4242, startTime: 99)

/// A store with nothing attached to the running user's container. `url: nil` and
/// `evidenceDirectory: nil` matter: a preview must not read, and must not write,
/// the real recorded incidents.
@MainActor
private func previewStore() -> MonitorStore {
    MonitorStore(
        policies: PolicyStore(),
        storage: StorageScreenModel(history: StorageHistory()),
        incidentHistory: IncidentHistoryStore(url: nil),
        evidenceDirectory: nil)
}

/// A closed CPU incident carrying its own recorded attribution — which is what a
/// closed incident is always narrated from, never from the live reading, because
/// that describes a machine which has since recovered.
private func closedIncident() -> Incident {
    Incident.preview(
        beganAt: origin, triggeredAt: origin.addingTimeInterval(180),
        recoveryStartedAt: origin.addingTimeInterval(540),
        closedAt: origin.addingTimeInterval(600),
        conditions: [.cpuSaturation], severity: .high,
        peakCPUBusyFraction: 0.94, peakMemoryPressure: .warning,
        attribution: IncidentAttribution(
        sample: AttributionSample(
            applications: [
                IncidentContributor(
                    applicationID: "/Applications/Brave Browser.app",
                    displayName: "Brave Browser", peakPercentOfOneCore: 412),
                IncidentContributor(
                    applicationID: "/Applications/Xcode.app",
                    displayName: "Xcode", peakPercentOfOneCore: 188),
            ],
            totalBusyPercentOfOneCore: 800,
            attributedPercentOfOneCore: 700,
            // ~40 percentage points of a busy machine is unattributable by uid in
            // the MAS build, and every surface has to show it rather than let the
            // contributors silently fail to sum (FR-013, FR-038).
            unattributedPercentOfOneCore: 100,
            logicalCoreCount: 8),
        at: origin))
}

private func attribution() -> CPUAttribution {
    CPUAttribution.preview(
        totalBusyPercentOfOneCore: 800, attributedPercentOfOneCore: 700,
        unattributedPercentOfOneCore: 100,
        contributors: [ProcessCPUUsage(
            identity: contributorIdentity, command: "Brave Browser",
            percentOfOneCore: 412, residentBytes: 1 << 30)],
        logicalCoreCount: 8)
}

// MARK: - The mute sheet (design 1g, middle)

/// The sentence under the options is the reason this is a sheet and not an
/// `NSMenu`: it is what stops "mute" reading as "stop watching". If it is not
/// legible here, the sheet has failed at the only thing it is for.
#Preview("Mute alerts sheet") {
    MuteAlertsView(store: previewStore())
}

// MARK: - The export sheet (design 1k)

/// **Read the preview pane against the choices.** FR-028's whole claim is that
/// the file the user receives is byte for byte the document shown here, so the
/// two halves disagreeing is the defect this screen exists to prevent.
#Preview("Export a report — defaults") {
    let subject = closedIncident()
    return ExportReportView(
        model: ExportReportModel(
            incident: subject,
            summary: IncidentSummarizer.summarize(
                incident: subject, attribution: attribution()),
            attribution: attribution(),
            contributorPaths: [contributorIdentity:
                "/Users/someone/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"],
            generatedAt: origin),
        onClose: {})
}

/// Everything redacted. The preview must visibly change, or the controls are
/// decoration — and a redaction control that does nothing is worse than none.
#Preview("Export a report — fully redacted") {
    let subject = closedIncident()
    let model = ExportReportModel(
        incident: subject,
        summary: IncidentSummarizer.summarize(
            incident: subject, attribution: attribution()),
        attribution: attribution(),
        contributorPaths: [contributorIdentity:
            "/Users/someone/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"],
        generatedAt: origin)
    model.options = RedactionOptions(
        hideUserName: true, hideFilePaths: true, hideProcessNames: true)
    return ExportReportView(model: model, onClose: {})
}

// MARK: - Incident detail (design 1e)

/// The evidence room, against a closed incident with a recorded attribution and
/// an unattributable remainder.
#Preview("Incident detail — a closed CPU incident") {
    IncidentDetailView(incident: closedIncident(), store: previewStore())
        .frame(width: 820, height: 720)
}

/// The same screen at the window's minimum width. Incident detail is the densest
/// surface in the product and the one most likely to reflow badly.
#Preview("Incident detail — at 480 pt") {
    IncidentDetailView(incident: closedIncident(), store: previewStore())
        .frame(width: 480, height: 720)
}

// MARK: - First run

/// **A render here cannot settle TASK-65.20.** That task is about whether the
/// window comes *forward* on a cold launch under `LSUIElement`, which is a fact
/// about the running application and not about this layout. What this does
/// settle is what the window says once it is up.
#Preview("First run") {
    FirstRunView(state: FirstRunState(
        defaults: UserDefaults(suiteName: "preview.firstRun") ?? .standard))
}

// MARK: - The menu bar popover (design 1a, 1b)

/// The popover is the triage moment, and it is the surface with the least room:
/// design 1b puts a headline, contributors and three actions into a fixed width.
/// TASK-88 records its action labels truncating to "See the evide…".
#Preview("Menu bar popover") {
    MenuBarContentView(store: previewStore())
}
#endif
