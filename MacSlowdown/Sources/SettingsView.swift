import AppKit
import Metrics
import ServiceManagement
import SwiftUI

/// Settings (design 1i and 1j).
///
/// Four tabs rather than the design's five: **Advanced** has no content the app
/// can honestly fill yet, and an empty tab claims more than a missing one does.
///
/// The structural idea across the whole surface is two layers. A plain-language
/// choice is what an ordinary person touches; the exact figures stay reachable
/// behind a disclosure, in the same units incident detail quotes them, so nothing
/// is hidden from someone who wants to check the working (FR-054).
struct SettingsView: View {
    @Binding var showMenuBarItem: Bool

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsTab(showMenuBarItem: $showMenuBarItem)
            }
            Tab("Alerts", systemImage: "bell") {
                AlertsSettingsTab()
            }
            // "Rules" rather than "Apps" since FR-016 amendment 1: what lives here
            // is no longer a list of applications but a list of rules, each naming
            // an application *and* a condition, plus the session-scoped one that
            // names no application at all.
            Tab("Rules", systemImage: "list.bullet") {
                AppRulesSettingsTab()
            }
            Tab("Privacy", systemImage: "hand.raised") {
                PrivacySettingsTab()
            }
        }
        .frame(width: 560, height: 470)
    }
}

// MARK: - General

/// TASK-64: every row here is a `Toggle` or a `LabeledContent` inside one grouped
/// `Form`. The previous pane mixed a bare `Text` caption with a `LabeledContent`,
/// which is why the Notifications label sat outside the alignment the toggles
/// established — the form read as two unrelated halves.
private struct GeneralSettingsTab: View {
    @Binding var showMenuBarItem: Bool
    @AppStorage(MenuBarReadout.storageKey)
    private var menuBarReadout = MenuBarReadout.default.rawValue
    @State private var loginItem = LoginItem()
    private var notifications: NotificationDelivery { MonitorStore.shared.notifications }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $showMenuBarItem) {
                    Text("Show in menu bar")
                    Text(showMenuBarItem
                         ? "Monitoring continues whether or not the status item is shown."
                         : "MacSlowdown keeps a Dock icon while the menu bar item is hidden, "
                           + "so you can still reach this window.")
                }
                .onChange(of: showMenuBarItem) { _, shown in
                    ActivationPolicy.menuBarItemVisibilityChanged(isVisible: shown)
                }

                // Design 2d's optional readouts (TASK-65.17). Off by default: the
                // icon is ~16 pt in a crowded strip, and a figure beside it is a
                // choice rather than the baseline.
                Picker("Menu bar readout", selection: $menuBarReadout) {
                    ForEach(MenuBarReadout.allCases) { readout in
                        Text(readout.label).tag(readout.rawValue)
                    }
                }
                .accessibilityHint("Adds a CPU percentage or a 60-second trend "
                                   + "beside the menu bar icon.")
                .disabled(!showMenuBarItem)
            }

            Section {
                Toggle(isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                )) {
                    Text("Start at login")
                    Text(loginItem.explanation)
                }
                .disabled(!loginItem.isAdjustable)

                if loginItem.state == .requiresApproval {
                    Button("Open Login Items in System Settings") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
            }

            Section {
                // Asking here rather than at launch: the prompt is a system dialog,
                // and a monitor that interrupts you before it has measured anything
                // has nothing to say yet. FR-014's alerts are useful only once there
                // is an incident to alert about.
                LabeledContent {
                    switch notifications.authorisation {
                    case .notDetermined:
                        Button("Allow notifications…") {
                            Task { await notifications.requestAuthorisation() }
                        }
                    case .denied:
                        Button("Open Notification Settings") {
                            if let url = URL(string:
                                "x-apple.systempreferences:com.apple.preference.notifications") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    case .authorised, .provisional:
                        Text("Allowed").foregroundStyle(.secondary)
                    }
                } label: {
                    Text("Notifications")
                    Text(notifications.authorisation.explanation)
                }
            }
        }
        .formStyle(.grouped)
        // Read the live system state whenever this appears, so a change made in
        // System Settings is reflected rather than whatever we last set (FR-033).
        .onAppear {
            loginItem.refresh()
            Task { await notifications.refreshAuthorisation() }
        }
    }
}

// MARK: - Alerts

private struct AlertsSettingsTab: View {
    @Bindable private var settings = AlertSettings.shared
    @State private var showsThresholds = false

    /// The conditions a switch here can act on: the resource ones.
    ///
    /// Repeated quits is deliberately absent. It cannot open an incident at all
    /// (FR-046 amendment 5), so a switch for it would be a control with nothing to
    /// govern — and a settings screen that offers one teaches the reader that the
    /// others might be the same.
    /// Ordered by the default rather than hand-written, so the ones that interrupt
    /// out of the box read first and a condition added later cannot be forgotten.
    static let interruptibleConditions: [IncidentCondition] = {
        let resource = IncidentCondition.allCases.filter(\.isResourceCondition)
        return resource.filter(\.announcesByDefault)
            + resource.filter { !$0.announcesByDefault }
    }()

    var body: some View {
        Form {
            if !settings.isAppliedToMonitoring {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Saved, but not yet in effect")
                            // TASK-69 wired the monitor to these settings, and
                            // `isAppliedToMonitoring` flips on the first apply and
                            // never returns to false — so this banner is now only
                            // reachable before monitoring has started. It used to
                            // describe a defect that no longer exists (TASK-96
                            // finding 23); it now describes the state it is in.
                            Text("MacSlowdown keeps your choice. Monitoring has not "
                                 + "started yet, so nothing is being judged against "
                                 + "it — it takes effect as soon as monitoring runs.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                }
            }

            Section {
                Toggle(isOn: $settings.announceIncidents) {
                    Text("Tell me about slowdowns")
                    Text("One notification per slowdown, unless it gets noticeably worse.")
                }

                LabeledContent {
                    Picker("Sensitivity", selection: $settings.sensitivity) {
                        ForEach(AlertSensitivity.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                } label: {
                    Text("How sensitive should I be?")
                    Text(settings.sensitivity.restatement)
                }

                // Not a toggle. No public API reports the current Focus to a
                // sandboxed app, so we never decide this — macOS holds the banner.
                // A switch here would take credit for someone else's behaviour.
                LabeledContent {
                    Text("Held by macOS").foregroundStyle(.secondary)
                } label: {
                    Text("Quiet during Focus")
                    Text("Slowdowns are still recorded and waiting when you come back. "
                         + "MacSlowdown cannot read your Focus, so macOS decides this.")
                }

                Toggle(isOn: $settings.deferDuringAudio) {
                    Text("Don't interrupt during calls or playback")
                    Text("Holds notifications while an app is playing audio or "
                         + "using the microphone. The slowdown is still recorded.")
                }
            }

            // Design 5g. Detection and interruption are separated on screen because
            // they are separate in the code: the section above moves where the line
            // sits, this one decides whether crossing it interrupts. Everything is
            // recorded either way, and the caption says so at the top rather than
            // leaving the reader to infer it from four repetitions below.
            Section("Which of these should interrupt you?") {
                Text("Everything is recorded either way. The test we apply is "
                     + "whether there is something you could decide.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(AlertsSettingsTab.interruptibleConditions, id: \.self) { condition in
                    Toggle(isOn: Binding(
                        get: { settings.interrupts(condition) },
                        set: { settings.setInterrupts(condition, $0) }
                    )) {
                        Text(condition.label)
                        Text(condition.interruptionRationale)
                    }
                }
            }

            Section {
                DisclosureGroup(isExpanded: $showsThresholds) {
                    thresholdRows
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Exact thresholds")
                        Text(settings.usesCustomThresholds
                             ? "Edited — these override the \(settings.sensitivity.label) figures."
                             : "The figures \"\(settings.sensitivity.label)\" stands for.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Text("Incidents are judged against these fixed figures. Comparing them "
                     + "with what is normal for this Mac is not built yet, so no incident "
                     + "claims a learned baseline.")
                Text("These settings apply to MacSlowdown as a whole. Separate profiles "
                     + "for heavy build sessions or battery use do not exist yet.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    /// Stated in the units incident detail uses: CPU as a share of this Mac's
    /// capacity, durations spelled out by the same formatter (FR-004, FR-054).
    @ViewBuilder private var thresholdRows: some View {
        LabeledContent {
            HStack {
                Slider(value: customised(\.cpuBusyFractionThreshold), in: 0.5...1.0, step: 0.01)
                    .frame(width: 180)
                Text(AlertSettings.spellCPU(fraction: settings.cpuBusyFractionThreshold))
                    .monospacedDigit()
                    .frame(width: 170, alignment: .leading)
            }
        } label: {
            Text("Total CPU above")
        }

        LabeledContent {
            HStack {
                Slider(value: customised(\.cpuSustainedSeconds), in: 30...600, step: 15)
                    .frame(width: 180)
                Text(AlertSettings.spell(.seconds(settings.cpuSustainedSeconds)))
                    .monospacedDigit()
                    .frame(width: 170, alignment: .leading)
            }
        } label: {
            Text("…for at least")
        }

        LabeledContent {
            Text("Warning or above").foregroundStyle(.secondary)
        } label: {
            Text("Memory pressure")
            Text("Fixed. MacSlowdown treats warning-or-above as the condition, "
                 + "and reads no other level.")
        }

        LabeledContent {
            HStack {
                Slider(value: customised(\.memorySustainedSeconds), in: 15...600, step: 15)
                    .frame(width: 180)
                Text(AlertSettings.spell(.seconds(settings.memorySustainedSeconds)))
                    .monospacedDigit()
                    .frame(width: 170, alignment: .leading)
            }
        } label: {
            Text("…for at least")
        }

        if settings.usesCustomThresholds {
            Button("Use the \(settings.sensitivity.label) figures") {
                settings.useThresholdsFromSensitivity()
            }
        }

        // TASK-69. A user who tightens a threshold does it because something is
        // bothering them now, and an incident that then appears immediately and
        // claims to have started minutes ago would look like a mistake. It is not:
        // it is dated from readings already kept. Saying so here is what stops that
        // being a surprise, since it is the only moment the choice is being made.
        Text("A changed threshold is judged against the CPU readings MacSlowdown "
             + "has already kept, so a slowdown that was under way is recorded from "
             + "when it began — which can be earlier than the moment you changed "
             + "this. Nothing is assumed for stretches that were not measured. "
             + "Memory pressure is not in the retained readings, so its clock "
             + "starts here.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Editing any figure is what marks the thresholds custom, so the plain choice
    /// and the numbers never silently disagree about which one is in force.
    private func customised(_ keyPath: ReferenceWritableKeyPath<AlertSettings, Double>)
        -> Binding<Double> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                settings.usesCustomThresholds = true
                settings[keyPath: keyPath] = newValue
            })
    }
}

// MARK: - Apps

private struct AppRulesSettingsTab: View {
    @State private var rules: [ApplicationPolicy] = []
    @State private var corrections: [GroupingCorrection] = []
    @State private var showsSuppressed = false
    @State private var showsOffer = false
    @Bindable private var settings = AlertSettings.shared
    @Bindable private var session = SessionQuiet.shared

    var body: some View {
        Form {
            // Design 5f: silent to set and silent to expire, but visible while it
            // runs. A suppression nobody can see is indistinguishable from a broken
            // detector, and this one has no end time for the user to look up.
            if session.isActive {
                Section("Active this session") {
                    LabeledContent {
                        Button("End now") { session.end() }
                    } label: {
                        Text(SessionQuiet.title)
                        if let detail = session.statusDetail() {
                            Text(detail)
                        }
                    }
                }
            }

            Section {
                Text("Rules you've set. These change what interrupts you — "
                     + "they never change what's recorded, kept, or shown in the "
                     + "overview.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if rules.isEmpty {
                    Text("No rules yet. Add an application and the one condition "
                         + "whose alerts you don't want from it — MacSlowdown will "
                         + "keep recording it, and will still tell you about that "
                         + "application's other conditions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(rules) { rule in
                    ruleRow(rule)
                }

                // Application *then* condition, in one gesture. A rule names both,
                // so a control that could add one without the other would be able
                // to produce the application-wide rule the amendment removed.
                Menu("Add a rule…") {
                    if addableApplications.isEmpty {
                        Text("No other applications are running")
                    }
                    ForEach(addableApplications, id: \.identifier) { candidate in
                        Menu(candidate.name) {
                            ForEach(
                                AlertsSettingsTab.interruptibleConditions, id: \.self
                            ) { condition in
                                Button(condition.label) { add(candidate, condition) }
                            }
                        }
                    }
                }

                // The sheet's real home is the moment of annoyance — the
                // notification, the condition in the overview, the incident detail.
                // This is the Settings-side entry, and it is honest about needing a
                // subject: with nothing under way there is nothing for the three
                // sentences to be about, and inventing one would put the user back
                // in front of the pickers 5f exists to remove.
                LabeledContent {
                    Button("Stop telling me…") { showsOffer = true }
                        .disabled(liveOffer == nil)
                } label: {
                    Text("Something happening right now")
                    Text(liveOffer.map(\.subtitle)
                         ?? "Nothing is under way, so there is nothing to silence "
                            + "from here. This offer also appears with the slowdown "
                            + "itself, which is where it is usually wanted.")
                }
            }

            Section {
                Text("Every rule names one condition, and no rule silences another. "
                     + "A rule about an application's CPU load leaves its memory "
                     + "pressure alone. Suppressed slowdowns still appear in "
                     + "Incidents, marked \"not alerted\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Review what these rules hid…") { showsSuppressed = true }
            }

            // The conditions switched off for every application live on the Alerts
            // tab, and a rules list that did not mention them would be incomplete —
            // which is the same defect, one screen along.
            if !silencedEverywhere.isEmpty {
                Section("Silenced for every application") {
                    ForEach(silencedEverywhere, id: \.self) { condition in
                        LabeledContent {
                            Button("Turn back on") {
                                settings.setInterrupts(condition, true)
                            }
                        } label: {
                            Text(condition.label)
                            Text("Set on the Alerts tab. Still detected, still "
                                 + "recorded, still in the overview.")
                        }
                    }
                }
            }

            // FR-039: every correction the user has made, in one place, undoable.
            // The inspector shows the ones about the application in front of you;
            // this is where a correction whose application is no longer running —
            // or which moved a process out of sight — remains findable.
            Section("Grouping corrections") {
                Text("Where you have told MacSlowdown that its own grouping was "
                     + "wrong. These change how processes are added up on screen. "
                     + "They never change a reading, and never change what an "
                     + "incident already recorded.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if corrections.isEmpty {
                    Text("None. MacSlowdown groups processes by the application "
                         + "bundle their executable lives in; you can correct that "
                         + "from an application's Grouping section in Apps & "
                         + "processes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(corrections) { correction in
                    correctionRow(correction)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            rules = MonitorStore.shared.policies.policies
            corrections = MonitorStore.shared.groupingCorrections
        }
        .sheet(isPresented: $showsSuppressed) { SuppressedDetectionsSheet() }
        .sheet(isPresented: $showsOffer) {
            if let offer = liveOffer {
                SuppressionOfferView(offer: offer) { _ in
                    rules = MonitorStore.shared.policies.policies
                }
            }
        }
    }

    /// The conditions switched off for every application, in the order the Alerts
    /// tab lists them.
    private var silencedEverywhere: [IncidentCondition] {
        AlertsSettingsTab.interruptibleConditions.filter {
            settings.hasDecided(about: $0) && !settings.interrupts($0)
        }
    }

    /// The offer for whatever is under way, or nil when nothing is.
    ///
    /// The application comes from the incident's own recorded attribution and may
    /// legitimately be absent — FR-055's unattributable share is frequently the
    /// largest part of a reading — in which case the sheet drops its
    /// application-scoped sentence rather than guessing at a subject.
    private var liveOffer: SuppressionOffer? {
        guard let incident = MonitorStore.shared.openIncident,
              let condition = incident.conditions
                  .sorted(by: { $0.label < $1.label }).first
        else { return nil }
        return SuppressionOffer(
            application: incident.attribution?.applications.first?.displayName,
            condition: condition)
    }

    @ViewBuilder private func correctionRow(_ correction: GroupingCorrection) -> some View {
        LabeledContent {
            Button {
                MonitorStore.shared.removeGroupingCorrection(id: correction.id)
                corrections = MonitorStore.shared.groupingCorrections
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Undo this correction")
            .accessibilityLabel("Undo your correction: "
                                + GroupingCorrectionCopy.describe(correction))
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(GroupingCorrectionCopy.describe(correction))
                if let scope = GroupingCorrectionCopy.scope(correction) {
                    Text(scope).font(.caption).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Design 5f's two columns — application, then condition — with what the rule
    /// *does* kept as the picker it always was.
    ///
    /// The condition is a caption rather than a third control: a rule's subject is
    /// chosen when it is made, and offering to re-point an existing rule at another
    /// condition would be a way to silence something the user never looked at.
    /// Removing it and making another says the same thing out loud.
    @ViewBuilder private func ruleRow(_ rule: ApplicationPolicy) -> some View {
        LabeledContent {
            HStack(spacing: 8) {
                Picker("Rule", selection: Binding(
                    get: { rule.classification },
                    set: { reclassify(rule, to: $0) }
                )) {
                    ForEach(PolicyClassification.allCases, id: \.self) { classification in
                        Text(classification.label).tag(classification)
                    }
                }
                .labelsHidden()
                .frame(width: 190)

                Button {
                    MonitorStore.shared.policies.removePolicy(id: rule.id)
                    rules = MonitorStore.shared.policies.policies
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove this rule")
                .accessibilityLabel("Remove the rule: \(rule.summary)")
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let icon = icon(for: rule) {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    }
                    Text(rule.displayName)
                }
                Text(rule.conditions.map(\.label).sorted().joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(rule.summary)
        }
    }

    private func icon(for rule: ApplicationPolicy) -> NSImage? {
        guard let path = rule.bundlePath else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }

    private func reclassify(_ rule: ApplicationPolicy, to classification: PolicyClassification) {
        var updated = rule
        updated.classification = classification
        MonitorStore.shared.policies.setPolicy(updated)
        rules = MonitorStore.shared.policies.policies
    }

    /// Candidates come from the running applications rather than a file panel.
    /// The app holds no user-selected-file entitlement, and asking for one to
    /// populate a picker is exactly the kind of scope creep App Review punishes.
    private struct Candidate {
        let name: String
        let bundleID: String?
        let bundlePath: String?
        var identifier: String { bundleID ?? bundlePath ?? name }
    }

    /// Applications with a rule are **not** filtered out. A rule is one condition,
    /// so an application that already has one is a perfectly ordinary subject for a
    /// second — and removing it from the menu is how the old application-wide shape
    /// would quietly reassert itself.
    private var addableApplications: [Candidate] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { application -> Candidate? in
                guard let name = application.localizedName else { return nil }
                return Candidate(
                    name: name,
                    bundleID: application.bundleIdentifier,
                    bundlePath: application.bundleURL?.path)
            }
            .filter { seen.insert($0.identifier).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Adding a condition to an application that already has a rule *merges*: two
    /// statements about the same application are two statements, and replacing the
    /// first would silently revoke a decision the user never revisited.
    private func add(_ candidate: Candidate, _ condition: IncidentCondition) {
        let existing = MonitorStore.shared.policies.policies
            .first { $0.id == candidate.identifier }
        MonitorStore.shared.policies.setPolicy(ApplicationPolicy(
            bundleID: candidate.bundleID,
            bundlePath: candidate.bundlePath,
            displayName: candidate.name,
            classification: existing?.classification ?? .expected,
            conditions: (existing?.conditions ?? []).union([condition])))
        rules = MonitorStore.shared.policies.policies
    }
}

/// The audit trail behind a rule (FR-016).
///
/// A suppression that hides its own effects is how a monitoring tool quietly stops
/// working, so this list exists even when nothing has been suppressed, and the
/// empty state says which of the two it is. Until TASK-76 that was the *only* state
/// it could show: the gate withheld alerts and nothing recorded that it had, so the
/// sentence below was printed whether or not it was true.
///
/// Only per-application rules appear here. A muted alert and one held during audio
/// were withheld too, but neither is a rule about an application — see
/// `SuppressionCause`.
private struct SuppressedDetectionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    private var detections: [SuppressedDetection] {
        MonitorStore.shared.policies.suppressedDetections
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What your rules hid").font(.headline)
            if detections.isEmpty {
                Text("Nothing has been suppressed by a rule. Every slowdown MacSlowdown "
                     + "detected was either announced or held back for another reason, "
                     + "such as being below the severity you asked about, muted, or "
                     + "held during audio — none of which are listed here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                List(detections) { detection in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(detection.summary)
                        Text(detection.at.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                .frame(minHeight: 200)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

// MARK: - Privacy

private struct PrivacySettingsTab: View {
    @Bindable private var settings = AlertSettings.shared
    @State private var usage = StoredData.usageDescription()
    @State private var showsStoredCategories = false
    @State private var confirmsDeletion = false
    @State private var deletionOutcome: String?

    var body: some View {
        Form {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nothing has left this Mac")
                        Text(PrivacySettings.dataHandlingStatement)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "checkmark.seal")
                }
            }

            Section {
                LabeledContent {
                    Picker("Retention", selection: $settings.retention) {
                        ForEach(PrivacySettings.Retention.allCases, id: \.self) { retention in
                            Text(retention.label).tag(retention)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                } label: {
                    Text("Keep incident history for")
                    Text(usage)
                }

                // TASK-79. The old copy — "Helps identify which copy of an app was
                // running" — described a control that did nothing: paths were
                // recorded either way. What is actually a choice is whether a
                // location is written into the incident history that persists for
                // up to ninety days, and the second sentence says plainly what is
                // not a choice, because path *resolution* is how processes are
                // grouped and icons found and cannot be switched off.
                Toggle(isOn: $settings.recordFilePaths) {
                    Text("Record file paths with incidents")
                    Text("Saves where each app was launched from alongside a recorded "
                         + "incident, so you can tell which copy was running. "
                         + "MacSlowdown always reads locations while monitoring — that "
                         + "is how it groups an app's processes and finds its icon — so "
                         + "this changes only what is written to disk. Off by default.")
                }

                // Not a control, and no longer an open question: the product
                // decision is that history persists, on by default (TASK-72).
                // Stated rather than switched, because a toggle whose off position
                // silently throws away recorded evidence is not a privacy control —
                // the retention picker above and "Delete all history" below are.
                LabeledContent {
                    Text("Always").foregroundStyle(.secondary)
                } label: {
                    Text("Keep history across restarts")
                    Text("Incidents are saved \(StoredData.containerStatement), and "
                         + "kept for the period above or the "
                         + "\(MonitorStore.retainedIncidents) most recent, whichever "
                         + "comes first.")
                }
            }

            Section {
                HStack {
                    Button("See exactly what's stored…") { showsStoredCategories = true }
                    Button("Delete all history…", role: .destructive) { confirmsDeletion = true }
                }
                if let deletionOutcome {
                    Text(deletionOutcome).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { usage = StoredData.usageDescription() }
        .sheet(isPresented: $showsStoredCategories) { StoredCategoriesSheet() }
        .confirmationDialog(
            "Delete everything MacSlowdown has written to disk?",
            isPresented: $confirmsDeletion, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your per-app rules are kept. Every recorded incident is removed, "
                 + "from disk and from the screens showing it.")
        }
    }

    /// Reports what was removed rather than assuming the call did something — the
    /// same rule FR-050 applies to actions taken on the user's behalf.
    private func delete() {
        let removed = MonitorStore.shared.deleteRecordedHistory()
        usage = StoredData.usageDescription()
        guard !removed.isEmpty else {
            deletionOutcome = "There was nothing recorded to delete."
            return
        }
        let size = ByteCountFormatter.string(
            fromByteCount: Int64(removed.bytes), countStyle: .file)
        let incidents = removed.incidents == 0
            ? "no recorded incidents"
            : "\(removed.incidents) recorded incident\(removed.incidents == 1 ? "" : "s")"
        deletionOutcome = "Deleted \(incidents) and "
            + "\(removed.files) other stored file\(removed.files == 1 ? "" : "s"), "
            + "freeing \(size)."
    }
}

private struct StoredCategoriesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What MacSlowdown stores").font(.headline)
            ForEach(PrivacySettings.storedCategories, id: \.category) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.category).bold()
                    Text(entry.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            Text(StoredData.usageDescription())
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

#if DEBUG
// MARK: - Previews
//
// Settings is recorded in TASK-65.24 as never having been seen on screen at all,
// and it is four tabs deep. These render each tab separately, because a TabView
// preview only ever shows the first one — and the three that are not General are
// exactly the ones nobody has looked at.
//
// The tab views are `private` to this file, which is why the previews live here
// rather than in a separate *Previews.swift.
//
// A preview settles layout: whether controls fit, whether labels truncate,
// whether a tab's content overflows its frame. It cannot settle whether the
// window comes forward, or what the real Settings scene's chrome does to the
// size — `Settings {}` supplies its own frame that this does not reproduce.

#Preview("Settings — all four tabs") {
    @Previewable @State var showMenuBarItem = true
    SettingsView(showMenuBarItem: $showMenuBarItem)
}

#Preview("Settings — General") {
    @Previewable @State var showMenuBarItem = true
    GeneralSettingsTab(showMenuBarItem: $showMenuBarItem)
}

/// Carries the sensitivity control the owner asked for and could not find
/// (TASK-108). Worth reading this render for whether it is discoverable.
#Preview("Settings — Alerts") {
    AlertsSettingsTab()
}

/// Condition-scoped suppression (FR-016 amendment 1). Its empty state matters as
/// much as its populated one.
#Preview("Settings — Rules") {
    AppRulesSettingsTab()
}

#Preview("Settings — Privacy") {
    PrivacySettingsTab()
}
#endif
