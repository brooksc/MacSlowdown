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
            Tab("Apps", systemImage: "square.grid.2x2") {
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

    var body: some View {
        Form {
            if !settings.isAppliedToMonitoring {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Saved, but not yet in effect")
                            Text("MacSlowdown keeps your choice, but the running monitor "
                                 + "has not been wired to read it and is still using the "
                                 + "built-in figures shown under Exact thresholds.")
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
    @State private var showsSuppressed = false

    var body: some View {
        Form {
            Section {
                Text("Rules you've set. These change what gets flagged — "
                     + "they never change what's recorded.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if rules.isEmpty {
                    Text("No rules yet. Add an application whose heavy use is normal, "
                         + "and MacSlowdown will keep recording it without interrupting you.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(rules) { rule in
                    ruleRow(rule)
                }

                Menu("Add an app…") {
                    if addableApplications.isEmpty {
                        Text("No other applications are running")
                    }
                    ForEach(addableApplications, id: \.identifier) { candidate in
                        Button(candidate.name) { add(candidate) }
                    }
                }
            }

            Section {
                Text("Suppressed slowdowns still appear in Incidents, marked "
                     + "\"not alerted\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Review what these rules hid…") { showsSuppressed = true }
            }
        }
        .formStyle(.grouped)
        .onAppear { rules = MonitorStore.shared.policies.policies }
        .sheet(isPresented: $showsSuppressed) { SuppressedDetectionsSheet() }
    }

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
                .accessibilityLabel("Remove the rule for \(rule.displayName)")
            }
        } label: {
            HStack(spacing: 6) {
                if let icon = icon(for: rule) {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                Text(rule.displayName)
            }
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

    private var addableApplications: [Candidate] {
        let existing = Set(rules.map(\.id))
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
            .filter { !existing.contains($0.identifier) && seen.insert($0.identifier).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func add(_ candidate: Candidate) {
        MonitorStore.shared.policies.setPolicy(ApplicationPolicy(
            bundleID: candidate.bundleID,
            bundlePath: candidate.bundlePath,
            displayName: candidate.name,
            classification: .expected))
        rules = MonitorStore.shared.policies.policies
    }
}

/// The audit trail behind a rule (FR-016).
///
/// A suppression that hides its own effects is how a monitoring tool quietly
/// stops working, so this list exists even when — as now — nothing has been
/// suppressed. The empty state says which of the two it is.
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
                     + "such as being below the severity you asked about.")
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

                Toggle(isOn: $settings.recordFilePaths) {
                    Text("Record file paths")
                    Text("Helps identify which copy of an app was running. Off by default.")
                }

                // Not a control. Whether history survives a restart is an open
                // product decision, and shipping the switch would settle it by
                // accident. What the app does today is stated instead.
                LabeledContent {
                    Text("This session only").foregroundStyle(.secondary)
                } label: {
                    Text("Keep history across restarts")
                    Text("History is held in memory and discarded when MacSlowdown quits. "
                         + "Whether to keep it, and how, has not been decided.")
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
            Text("Your per-app rules are kept. Incidents from this session are held in "
                 + "memory and are discarded when you quit either way.")
        }
    }

    /// Reports what was removed rather than assuming the call did something — the
    /// same rule FR-050 applies to actions taken on the user's behalf.
    private func delete() {
        let removed = StoredData.deleteRecordedEvidence()
        usage = StoredData.usageDescription()
        deletionOutcome = removed == 0
            ? "There was nothing recorded on disk to delete."
            : "Deleted \(removed) stored file\(removed == 1 ? "" : "s")."
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
