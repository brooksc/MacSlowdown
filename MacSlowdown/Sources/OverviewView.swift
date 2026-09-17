import Metrics
import SwiftUI

/// The opening view: what is happening now and what happened earlier, together
/// (TASK-113, designs 5a/5b/5c/6c).
///
/// The screen the product did not have. "Is it still happening?" and "what
/// happened earlier?" were two sidebar destinations joined by navigation, and the
/// second one — S-2's question, the reason to build this rather than a nicer
/// Activity Monitor — was reachable only by someone who already suspected there
/// was something to find.
///
/// Underneath both is a question the product could not answer at all: **were we
/// watching?** The coverage strip is here rather than a badge because "we were
/// watching" is a claim about a period, and a period needs a length (design 5a).
///
/// Render-only, like every screen here: it reads the store and formats. It never
/// samples, ranks or caches.
struct OverviewView: View {
    let store: MonitorStore
    /// Switches the window to the Incidents screen, so the last condition can be
    /// opened without this view knowing what the sidebar selection is.
    var showIncidents: () -> Void = {}

    @State private var scale = OverviewPresentation.Scale.today
    /// The clock the times on this screen are measured against.
    ///
    /// Ticks slowly and deliberately. Nothing here is a live gauge — the whole
    /// point of the screen is that the answer is the same if you come back in ten
    /// minutes — so it advances once a minute, which is enough for a clock time and
    /// a coverage total and is not enough to make the screen feel like something
    /// worth watching (S-6: do not build for engagement).
    @State private var now = Date()
    /// What the last action actually did (FR-017). Never assumed from the call
    /// returning.
    @State private var outcome: String?

    private var calendar: Calendar { .current }

    private var log: CoverageLog { store.coverage.log }

    private var windowStart: Date { scale.start(now: now, calendar: calendar) }

    private var inputs: OverviewPresentation.Inputs {
        var inputs = OverviewPresentation.Inputs(log: log)
        inputs.scale = scale
        inputs.now = now
        inputs.calendar = calendar
        inputs.openIncident = store.openIncident
        inputs.openHeadline = store.openIncident.map {
            IncidentSummarizer.summarize(incident: $0, attribution: store.attribution).headline
        }
        inputs.recentIncidents = store.recentIncidents
        inputs.wasNotAnnounced = wasNotAnnounced
        return inputs
    }

    /// Whether the open condition was recorded without interrupting anybody.
    ///
    /// Derived from the rules actually in force — the gate's own settings and
    /// `IncidentCondition.announcesByDefault` — rather than from an assumption that
    /// CPU never announces. A user who has opted CPU back into announcements must
    /// not be told we stayed quiet when we did not (FR-014 amendment 1, FR-063).
    private var wasNotAnnounced: Bool {
        guard let incident = store.openIncident else { return false }
        let settings = store.notificationSettingsInForce
        guard settings.announcesIncidents else { return true }
        if store.mute.remaining(at: now) != nil { return true }
        return !incident.conditions.contains {
            $0.announcesByDefault || settings.announcedConditions.contains($0)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                coveragePanel
                if scale == .today { tracePanel }
                summaryRow
                if store.openIncident != nil { contributors }
                if let outcome {
                    Text(outcome)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                footnote
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await tickClock() }
        .navigationTitle("Overview")
        .navigationSubtitle(NowPresentation.machineIdentity(store.machine))
    }

    /// Once a minute, and only while this screen is on screen. Cancelled by SwiftUI
    /// with the view, so nothing ticks for a screen nobody is looking at (FR-061).
    private func tickClock() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            now = Date()
        }
    }

    // MARK: - Header

    private var header: some View {
        let headline = OverviewPresentation.headline(inputs)
        return HStack(alignment: .top, spacing: 12) {
            // Symbol and words together: state is never carried by colour or by a
            // glyph alone (FR-034).
            Image(systemName: headline.symbolName)
                .imageScale(.large)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(headline.text)
                        .font(.title2).bold()
                        .fixedSize(horizontal: false, vertical: true)
                    if let chip = headline.chip {
                        Text(chip)
                            .font(.caption).bold()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(headline.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(headline.spoken)

            Spacer(minLength: 12)
            actions
        }
    }

    /// The two things only the person can tell us (FR-063, FR-064).
    ///
    /// Both live at the top of the opening screen rather than in Settings, because
    /// S-4 and S-7 are both about a moment: nobody goes looking through preferences
    /// while irritated, and a control that is not there when the feeling is is a
    /// control that is never used.
    @ViewBuilder
    private var actions: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // The one name for this action, from the one place it is written.
            // Two agents built this control in the same session and gave it two
            // labels — "It feels slow now" here, "It feels slow right now" in the
            // popover — which is FR-060's failure in miniature: one gesture, two
            // surfaces, drifting apart on the first day of their existence.
            Button(SlowdownReportPresentation.reportNowTitle) {
                let report = store.reportSlowdown(at: Date())
                // Says what was recorded, not that a call returned (FR-017). And a
                // report matching nothing we detected is stated as the useful case
                // it is, rather than apologised for (FR-064, S-7).
                outcome = report.coincidedWithDetection
                    ? "Recorded, with the readings from around now, alongside the "
                        + "condition we were already recording."
                    : "Recorded, with the readings from around now. Nothing we watch was "
                        + "over a line at the time — which is exactly the case we have no "
                        + "other way of hearing about."
            }
            .help("Files a report with the readings around this moment. No form, no "
                  + "category — and a report that matches nothing we detected is the "
                  + "point of it rather than a failure.")
            if store.openIncident != nil, let leader = expectedWorkloadSubject {
                Button(NowPresentation.expectedPolicyActionTitle(leader.displayName)) {
                    markExpected(leader)
                }
                .help("Records that heavy load is normal for this application. It stops "
                      + "the alerts, not the monitoring.")
            }
        }
        .fixedSize()
    }

    private var expectedWorkloadSubject: IncidentContributor? {
        guard let incident = store.openIncident,
              NowPresentation.leadingRelaunchPattern(incident) == nil
        else { return nil }
        return incident.attribution?.leadingApplication
    }

    /// FR-016. Written through the store and then **read back**: `setPolicy`
    /// returning is not evidence that a rule exists (FR-017, FR-050).
    private func markExpected(_ leader: IncidentContributor) {
        let policy = ApplicationPolicy(
            bundleID: leader.bundleID, bundlePath: leader.bundlePath,
            displayName: leader.displayName, classification: .expected)
        store.policies.setPolicy(policy)
        let saved = store.policies.policies.contains {
            $0.id == policy.id && $0.classification == .expected
        }
        outcome = NowPresentation.expectedPolicyOutcome(
            name: leader.displayName, saved: saved)
    }

    // MARK: - Coverage

    private var coveragePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(scale == .today ? "Today" : "The last 30 days").bold()
                Spacer(minLength: 12)
                Text(OverviewPresentation.coverageSummary(
                    log: log, scale: scale, now: now, calendar: calendar))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Scale", selection: $scale) {
                    ForEach(OverviewPresentation.Scale.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(12)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                switch scale {
                case .today: dayStrip
                case .thirtyDays: monthStrip
                }
                legend
                if let note = OverviewPresentation.gapNote(
                    log: log, scale: scale, now: now, calendar: calendar) {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let note = OverviewPresentation.recordBeginsNote(
                    log: log, scale: scale, now: now, calendar: calendar) {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if scale == .thirtyDays {
                    Text(OverviewPresentation.dayScaleNote(dayCells))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                gapReportAction
            }
            .padding(12)
        }
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }

    /// Design 5c's "Something happened then" (TASK-120).
    ///
    /// **Present only when there is a gap**, for the same reason `gapNote` is nil
    /// without one: an always-visible control here would invite a report against a
    /// stretch we did in fact watch, where the readings we kept are the better
    /// evidence and "It feels slow right now" is the gesture that keeps them.
    ///
    /// The report it files carries no samples — `SlowdownReport.make` resolves the
    /// window to `.noSamplesInWindow` on its own, because there genuinely are
    /// none — so nothing here has to fabricate an absence, and nothing has to
    /// suppress an evidence section that was never going to have rows.
    @ViewBuilder
    private var gapReportAction: some View {
        if let gap = OverviewPresentation.reportableGap(
            log: log, scale: scale, now: now, calendar: calendar) {
            let range = OverviewPresentation.clockRange(gap, calendar: calendar)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button(SlowdownReportPresentation.gapReportTitle) {
                    reportGap(gap)
                }
                .help(SlowdownReportPresentation.gapReportHelp(range: range))
                // The button's own name does not say which stretch it means, and
                // the caption beside it is a separate element, so the spoken label
                // carries the range (FR-034).
                .accessibilityLabel(
                    "\(SlowdownReportPresentation.gapReportTitle), \(range)")
                Text(SlowdownReportPresentation.gapReportCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Files the report, dated from the gap rather than from this moment.
    private func reportGap(_ gap: CoverageSpan) {
        let filedAt = Date()
        let report = store.reportSlowdown(
            timing: .recently(
                secondsAgo: OverviewPresentation.secondsAgo(ofMiddleOf: gap, now: filedAt)),
            at: filedAt)
        // What was kept is read back **off the report the store returned**, never
        // asserted from the gap we aimed at — the same rule `markExpected`
        // follows (FR-017, FR-050). A gap resolves to `.noSamplesInWindow` and
        // `keptReadings` puts that in words; writing "no readings" here instead
        // would be a sentence that stayed true only by luck.
        outcome = SlowdownReportPresentation.gapReportOutcome(
            range: OverviewPresentation.clockRange(gap, calendar: calendar),
            kept: SlowdownReportPresentation.keptReadings(report))
    }

    private var dayCells: [OverviewPresentation.DayCell] {
        OverviewPresentation.dayCells(
            log: log, incidents: store.recentIncidents, now: now, calendar: calendar)
    }

    private var dayStrip: some View {
        let spans = log.spans(from: windowStart, to: now)
        let marks = OverviewPresentation.conditions(in: inputs).map(\.beganAt)
        return VStack(alignment: .leading, spacing: 4) {
            CoverageStrip(spans: spans, from: windowStart, to: now, conditionMarks: marks)
                .frame(height: 18)
                .accessibilityElement()
                .accessibilityLabel(stripAccessibility(spans))
            HStack {
                Text(OverviewPresentation.clock(windowStart))
                Spacer()
                Text("now \(OverviewPresentation.clock(now))")
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }

    private func stripAccessibility(_ spans: [CoverageSpan]) -> String {
        var parts = ["Coverage \(scale.sinceClause)",
                     OverviewPresentation.coverageSummary(
                        log: log, scale: scale, now: now, calendar: calendar)]
        for gap in log.gaps(from: windowStart, to: now) {
            let reason = gap.state.reason ?? .noReadings
            parts.append("Not watching \(OverviewPresentation.clockRange(gap, calendar: calendar)) — "
                         + reason.sentence)
        }
        let conditions = OverviewPresentation.conditions(in: inputs)
        if !conditions.isEmpty {
            parts.append("\(OverviewPresentation.countPhrase(conditions.count, "condition")) "
                         + "recorded, marked on the strip")
        }
        return parts.joined(separator: ". ")
    }

    private var monthStrip: some View {
        // A grid rather than a canvas: each day is a control-sized target with its
        // own spoken label, which a single drawn strip could not offer VoiceOver.
        let cells = dayCells
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                ForEach(cells) { cell in
                    DayCellView(cell: cell)
                }
            }
            .frame(height: 26)
            HStack {
                Text(cells.first.map { OverviewPresentation.day($0.date) } ?? "")
                Spacer()
                Text("today")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }

    /// Design 5c's three-state grammar, on the screen rather than left to be
    /// inferred from the hatching.
    private var legend: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(OverviewPresentation.legend.enumerated()), id: \.offset) { index, entry in
                HStack(spacing: 6) {
                    LegendSwatch(kind: index)
                    Text(entry.label).bold()
                    Text(entry.detail).foregroundStyle(.secondary)
                }
                .font(.caption2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(entry.label). \(entry.detail)")
            }
        }
    }

    // MARK: - The retained curve

    /// The readings we actually kept, on their own axis and with their own span
    /// stated.
    ///
    /// Deliberately **not** drawn across the day axis above. `MetricsHistory`
    /// retains about fifteen minutes and is not persisted, so a curve on a
    /// fourteen-hour axis would be either a smear or an invention, and a flat line
    /// where nothing is retained would be the exact failure FR-002 forbids.
    private var tracePanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The readings we retain").font(.caption).bold()
            HistorySparklineBlock(
                title: "Total CPU",
                points: SparklinePresentation.totalBusySeries(store.retainedSamples),
                markers: store.openIncident.map { [$0.beganAt] } ?? [],
                cadence: store.cadence?.interval ?? MetricsHistory.defaultCadence,
                height: 44)
            Text(OverviewPresentation.traceScopeNote(retained: store.retainedHistorySpan))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Right now, and the last condition

    private var summaryRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                rightNowCard
                lastConditionCard
            }
            VStack(alignment: .leading, spacing: 12) {
                rightNowCard
                lastConditionCard
            }
        }
    }

    private var rightNowCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Right now").bold().padding(12)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                figure("CPU busy", value: cpuFigure,
                       qualifier: "mean over the last minute, of "
                        + "\(store.machine.logicalCores) cores")
                figure("Memory pressure", value: store.memoryPressure.label,
                       qualifier: NowPresentation.stateHold(
                        since: store.memoryPressureHeldSince,
                        monitoringBeganAt: store.monitoringBeganAt, now: now)?.lowercased())
                figure("Disk", value: NowPresentation.diskWrite(store.diskRates),
                       qualifier: "written, over the last sampling interval")
                figure("Storage free", value: storageFigure, qualifier: "on the startup volume")
            }
            .padding(12)
            Divider()
            Text(sampledCaption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }

    /// The CPU figure is a **stated statistic over a stated window** (FR-057), and
    /// the window is the one the status word is judged over, so the number and the
    /// word on this screen cannot disagree (FR-060).
    private var cpuFigure: String {
        guard let share = store.trailingBusyShare(window: .seconds(60), now: now) else {
            return "No readings retained"
        }
        return String(format: "%.0f%% of the machine", share * 100)
    }

    private var storageFigure: String {
        guard let volume = store.startupVolume else { return "Not reported" }
        return ByteCountFormatStyle(style: .file).format(Int64(volume.availableBytes))
    }

    private var sampledCaption: String {
        guard let lastUpdate = store.lastUpdate else {
            return "No reading yet. CPU is measured between two samples, so the first "
                + "figure appears after one interval."
        }
        let age = NowPresentation.ageInWords(.seconds(max(0, now.timeIntervalSince(lastUpdate))))
        return "Sampled \(age) ago. The Now screen carries the same readings with their "
            + "per-metric ages."
    }

    private func figure(_ label: String, value: String, qualifier: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).frame(width: 130, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).bold().monospacedDigit()
                if let qualifier {
                    Text(qualifier).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)\(qualifier.map { ", \($0)" } ?? "")")
    }

    /// The last condition, inline — which is what makes Incidents a detail behind
    /// this screen rather than a place to navigate to (TASK-113).
    @ViewBuilder
    private var lastConditionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last condition recorded").bold()
                if let incident = store.recentIncidents.first {
                    Text(OverviewPresentation.lastConditionAge(incident, now: now))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            Divider()
            if let incident = store.recentIncidents.first {
                let summary = IncidentSummarizer.summarize(
                    incident: incident, attribution: nil)
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(OverviewPresentation.conditionWindow(incident))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("Open it", action: showIncidents)
                        Button("All \(store.recentIncidents.count) recorded",
                               action: showIncidents)
                    }
                    .padding(.top, 2)
                }
                .padding(12)
            } else {
                Text(OverviewPresentation.noConditionsNote(
                    watched: log.watched(from: windowStart, to: now)))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Contributors, while a condition is being recorded

    /// Design 5b's table, and it is the *same* table the Now screen draws — the
    /// same rows from the same store through the same row view. Two surfaces
    /// describing one fact must not be able to disagree (FR-060), and the fastest
    /// way to break that is to write a second contributor list here.
    private var contributors: some View {
        VStack(alignment: .leading, spacing: 0) {
            ContributorHeader()
            Divider()
            ForEach(NowPresentation.contributorRows(store.inventory, limit: 4)) { row in
                ContributorRow(
                    row: row, store: store, isExpanded: false, toggle: {},
                    retained: store.retainedSamples,
                    cadence: store.cadence?.interval ?? MetricsHistory.defaultCadence)
                Divider()
            }
            Text("The largest few, plus everything we may not measure. The full list is "
                 + "in Apps & Processes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
        }
        // The same table means the same narrow-window behaviour: scroll sideways
        // rather than compress. Applied here too because this is a second call
        // site of one view, and the rule belongs to the table, not to the screen.
        .horizontallyScrollableBelowTableMinimum()
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var footnote: some View {
        Text("Nothing on this screen says the Mac was fine. It says what we measured, "
             + "over the window named, and where we have no measurement it says that "
             + "instead.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The coverage strip: one bar, every moment of the window accounted for.
///
/// Watched is a solid fill and not-watched is hatched, so the two are told apart by
/// **pattern** and not by colour — which is what keeps the strip readable under
/// Increase Contrast and for a person who cannot distinguish the two greys
/// (FR-034). The words are underneath it either way.
struct CoverageStrip: View {
    let spans: [CoverageSpan]
    let from: Date
    let to: Date
    /// Moments a condition was recorded, from the incident history — never inferred
    /// from the shape of anything on this strip.
    var conditionMarks: [Date] = []

    var body: some View {
        Canvas { context, size in
            let total = to.timeIntervalSince(from)
            guard total > 0 else { return }

            for span in spans {
                let x = size.width * CGFloat(span.from.timeIntervalSince(from) / total)
                let width = max(1, size.width * CGFloat(span.duration.totalSeconds / total))
                let rect = CGRect(x: x, y: 0, width: width, height: size.height)
                if span.state.isWatched {
                    context.fill(Path(roundedRect: rect, cornerRadius: 2),
                                 with: .color(.secondary.opacity(0.45)))
                } else {
                    hatch(rect, in: &context)
                }
            }

            for mark in conditionMarks {
                let offset = mark.timeIntervalSince(from) / total
                guard offset >= 0, offset <= 1 else { continue }
                let x = size.width * CGFloat(offset)
                // A darker notch through the strip, not a colour change: severity and
                // occurrence are never carried by hue alone (FR-034).
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.primary),
                               style: StrokeStyle(lineWidth: 2))
            }
        }
    }

    /// Diagonal hatching, drawn rather than tiled so it scales with the strip.
    private func hatch(_ rect: CGRect, in context: inout GraphicsContext) {
        context.fill(Path(roundedRect: rect, cornerRadius: 2),
                     with: .color(.secondary.opacity(0.08)))
        var lines = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            lines.move(to: CGPoint(x: x, y: rect.maxY))
            lines.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += 5
        }
        context.clip(to: Path(roundedRect: rect, cornerRadius: 2))
        context.stroke(lines, with: .color(.secondary.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 1))
    }
}

/// One day on the 30-day scale (design 6c).
struct DayCellView: View {
    let cell: OverviewPresentation.DayCell

    var body: some View {
        VStack(spacing: 2) {
            // The condition mark sits above the cell rather than inside it, so a day
            // that both had a condition and has a gap can say both things.
            Circle()
                .fill(cell.hasCondition ? Color.primary : .clear)
                .frame(width: 4, height: 4)
            Group {
                if cell.isWatchedThroughout {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.secondary.opacity(cell.hasCondition ? 0.7 : 0.35))
                } else {
                    CoverageStrip(
                        spans: [CoverageSpan(from: cell.date,
                                             to: cell.date.addingTimeInterval(1),
                                             state: .notWatched(.noReadings))],
                        from: cell.date, to: cell.date.addingTimeInterval(1))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel(cell.spoken)
    }
}

/// The legend's swatch: solid, solid-with-a-mark, hatched — the same three
/// treatments the strip uses.
struct LegendSwatch: View {
    let kind: Int

    var body: some View {
        Group {
            switch kind {
            case 0:
                RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.45))
            case 1:
                RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.45))
                    .overlay(Rectangle().fill(Color.primary).frame(width: 2))
            default:
                CoverageStrip(
                    spans: [CoverageSpan(from: .distantPast, to: .distantPast.addingTimeInterval(1),
                                         state: .notWatched(.noReadings))],
                    from: .distantPast, to: .distantPast.addingTimeInterval(1))
            }
        }
        .frame(width: 22, height: 10)
        .accessibilityHidden(true)
    }
}
