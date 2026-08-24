import Darwin
import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

private func attribution(total: Double, attributed: Double) -> CPUAttribution {
    CPUAttribution(
        totalBusyPercentOfOneCore: total,
        attributedPercentOfOneCore: attributed,
        unattributedPercentOfOneCore: max(0, total - attributed),
        contributors: [],
        protectedProcesses: [],
        logicalCoreCount: 8)
}

private func row(
    _ id: String, name: String, kind: InventoryRow.Kind, cpu: Double,
    measurable: Bool = true, qualification: String? = nil,
    children: [InventoryRow] = []
) -> InventoryRow {
    InventoryRow(
        id: id, name: name, executablePath: nil, kind: kind,
        percentOfOneCore: cpu, residentBytes: 0, isMeasurable: measurable,
        processCount: max(1, children.count), qualification: qualification,
        children: children)
}

@Suite("The Now verdict")
struct NowVerdictTests {
    /// FR-001: the screen opens with the condition, not a bare number. And the
    /// verdict never names a cause — that claim belongs to the incident summary,
    /// where it can carry a confidence label (FR-013).
    @Test("A normal machine is described as normal, with the measured figure behind it")
    func normalVerdict() {
        let verdict = NowPresentation.verdict(
            severity: .normal, attribution: attribution(total: 90, attributed: 60),
            incidentOpen: false)
        #expect(verdict.headline == "Nothing sustained is slowing this Mac down")
        #expect(verdict.detail.contains("90%"))
    }

    @Test("An open incident leads the verdict regardless of the instantaneous severity")
    func incidentVerdict() {
        let verdict = NowPresentation.verdict(
            severity: .normal, attribution: attribution(total: 700, attributed: 400),
            incidentOpen: true)
        #expect(verdict.headline == "A slowdown is in progress")
    }

    /// FR-002: before the first interval there is no CPU figure, and the screen
    /// says why rather than showing a zero that would read as an idle machine.
    @Test("With no attribution yet the verdict explains the wait, not a zero")
    func firstReading() {
        let verdict = NowPresentation.verdict(
            severity: .normal, attribution: nil, incidentOpen: false)
        #expect(verdict.headline == "Taking the first reading")
        #expect(!verdict.detail.contains("0%"))
    }

    @Test("Severity is reflected in the words, not only in a colour")
    func severityWords() {
        let elevated = NowPresentation.verdict(
            severity: .elevated, attribution: attribution(total: 500, attributed: 300),
            incidentOpen: false)
        let severe = NowPresentation.verdict(
            severity: .severe, attribution: attribution(total: 750, attributed: 300),
            incidentOpen: false)
        #expect(elevated.headline != severe.headline)
    }
}

@Suite("Now metric cards")
struct NowCardTests {
    /// FR-007 and DR-08: inactive pages are reclaimable cache. Counting them as
    /// "in use" is the misreport this figure exists to avoid.
    @Test("Memory in use excludes inactive pages")
    func memoryExcludesInactive() {
        let gb = UInt64(1_073_741_824)
        let statistics = MemoryStatistics(
            free: gb, active: 4 * gb, inactive: 8 * gb, wired: 2 * gb,
            compressed: gb, pageSize: 16384)
        let text = NowPresentation.memoryInUse(statistics, physicalMemoryBytes: 16 * gb)
        // 4 + 2 + 1 = 7 GB, not 15.
        #expect(text?.contains("7") == true)
        #expect(text?.contains("15") == false)
    }

    /// FR-002: an unreadable counter is an omission, never a zero.
    @Test("Unavailable memory statistics produce no figure at all")
    func memoryUnavailable() {
        #expect(NowPresentation.memoryInUse(nil, physicalMemoryBytes: 16_000_000_000) == nil)
        #expect(NowPresentation.memoryInUse(
            MemoryStatistics(free: 0, active: 0, inactive: 0, wired: 0,
                             compressed: 0, pageSize: 16384),
            physicalMemoryBytes: 0) == nil)
    }

    /// FR-009: a rate, over the measured interval. The counters behind it are
    /// cumulative and must never appear as-is.
    @Test("Disk figures are per-second rates")
    func diskRates() {
        let rates = DiskRates(readBytesPerSecond: 2_000_000, writeBytesPerSecond: 5_000_000)
        #expect(NowPresentation.diskWrite(rates).hasSuffix("/s"))
        #expect(NowPresentation.diskRead(rates).contains("read"))
    }
}

@Suite("Now cadence and identity")
struct NowFooterTests {
    /// FR-031: the user can inspect the cadence in force.
    @Test("The cadence line names the interval and the mode")
    func cadenceLine() {
        let cadence = SamplingCadence(
            mode: .investigation, interval: .seconds(1), reason: "an incident is open")
        #expect(NowPresentation.cadenceLine(cadence) == "Sampling every 1 s (investigation cadence)")
    }

    @Test("Before the first sample the cadence is stated as not yet established")
    func cadenceUnknown() {
        #expect(NowPresentation.cadenceLine(nil) == "Sampling cadence not established yet")
    }

    /// FR-049: model, cores, memory and OS — and nothing that identifies the
    /// machine persistently.
    @Test("Machine identity carries the measured model, never a marketing name")
    func machineIdentity() {
        let machine = MachineContext(
            osVersion: "Version 27.0", hardwareModel: "Mac14,15", architecture: "arm64",
            logicalCores: 8, performanceCores: 4, efficiencyCores: 4,
            physicalMemoryBytes: 24 * 1_073_741_824, appVersion: "0.1", appBuild: "1",
            schemaVersion: 1)
        let identity = NowPresentation.machineIdentity(machine)
        #expect(identity.contains("Mac14,15"))
        #expect(identity.contains("8 cores"))
        #expect(identity.contains("24 GB"))
        #expect(identity.contains("Version 27.0"))
    }
}

@Suite("Now contributor rows")
struct NowContributorTests {
    /// FR-013, FR-038: the visible list must account for the whole machine. The
    /// system group is what makes it sum, so truncation must never remove it.
    @Test("The system group survives truncation even when it is the smallest row")
    func systemRowSurvives() {
        var rows = (1...6).map { row("app\($0)", name: "App \($0)", kind: .application,
                                     cpu: Double(100 - $0)) }
        rows.append(row("system-processes", name: "System processes",
                        kind: .systemProcesses, cpu: 0.1))
        let shown = NowPresentation.contributorRows(rows, limit: 3)
        #expect(shown.count == 4)
        #expect(shown.contains { $0.kind == .systemProcesses })
    }

    @Test("Rows come back busiest first")
    func busiestFirst() {
        let rows = [
            row("a", name: "Quiet", kind: .application, cpu: 3),
            row("b", name: "Busy", kind: .application, cpu: 300),
        ]
        #expect(NowPresentation.contributorRows(rows, limit: 5).first?.name == "Busy")
    }

    @Test("The system group is not duplicated when it already made the cut")
    func noDuplicate() {
        let rows = [
            row("system-processes", name: "System processes",
                kind: .systemProcesses, cpu: 400),
            row("a", name: "App", kind: .application, cpu: 3),
        ]
        let shown = NowPresentation.contributorRows(rows, limit: 5)
        #expect(shown.count(where: { $0.kind == .systemProcesses }) == 1)
    }

    /// FR-002 and FR-003: every qualifier a row carries is said in words.
    @Test("Qualifiers become chips: cannot be broken down, not measurable, uncertain grouping")
    func chips() {
        #expect(NowPresentation.chips(for: row(
            "system-processes", name: "System processes", kind: .systemProcesses, cpu: 5))
                == ["Can't be broken down"])
        #expect(NowPresentation.chips(for: row(
            "x", name: "x", kind: .member, cpu: 0, measurable: false))
                == ["Not measurable"])
        #expect(NowPresentation.chips(for: row(
            "y", name: "y", kind: .application, cpu: 1,
            qualification: "started by Terminal"))
                == ["started by Terminal"])
        #expect(NowPresentation.chips(for: row("z", name: "z", kind: .application, cpu: 1))
                .isEmpty)
    }

    /// FR-027: search filters, it never re-ranks or re-reads.
    @Test("Search matches a family by name or by one of its processes")
    func search() {
        let rows = [
            row("safari", name: "Safari", kind: .application, cpu: 40,
                children: [row("wc", name: "com.apple.WebKit.WebContent", kind: .member, cpu: 20),
                           row("net", name: "com.apple.WebKit.Networking", kind: .member, cpu: 20)]),
            row("mail", name: "Mail", kind: .application, cpu: 5),
        ]
        #expect(NowPresentation.matching(rows, query: "safa").map(\.name) == ["Safari"])
        #expect(NowPresentation.matching(rows, query: "WebKit").map(\.name) == ["Safari"])
        #expect(NowPresentation.matching(rows, query: "   ").count == 2)
        #expect(NowPresentation.matching(rows, query: "nothing here").isEmpty)
    }
}

@Suite("Now incident banner")
struct NowIncidentBannerTests {
    private func incident(severity: IncidentSeverity, seconds: Double) -> Incident {
        let began = Date(timeIntervalSince1970: 0)
        return Incident(
            id: UUID(), beganAt: began, triggeredAt: began,
            recoveryStartedAt: nil, closedAt: began.addingTimeInterval(seconds),
            conditions: [.cpuSaturation], severity: severity,
            peakCPUBusyFraction: 0.95, peakMemoryPressure: .normal)
    }

    @Test("The chip states severity and how long it has run")
    func chip() {
        let chip = NowPresentation.incidentChip(incident(severity: .high, seconds: 360))
        #expect(chip.hasPrefix("High · "))
        #expect(chip.contains("6"))
    }

    /// FR-013: the banner's body is the summariser's output, and every statement
    /// in it carries an evidence class — a hypothesis never appears bare.
    @Test("Every line the banner renders is well formed")
    func wellFormed() {
        let summary = IncidentSummarizer.summarize(
            incident: incident(severity: .high, seconds: 360),
            attribution: attribution(total: 700, attributed: 400))
        #expect(summary.isWellFormed)
        #expect(!summary.conclusions.isEmpty)
    }
}

@Suite("Now safe actions")
struct NowActionTests {
    /// PIDs are reused. Matching on the pid alone would act on whichever process
    /// inherited the number, which is the wrong application.
    @Test("A contributor is matched on pid and start time together")
    func identityMatch() {
        let wanted = ProcessIdentity(pid: 42, startTime: 1_000)
        let recycled = ProcessIdentity(pid: 42, startTime: 9_999)
        let member = FamilyMember(
            record: ProcessRecord(
                identity: recycled, command: "other", uid: getuid(), ppid: 1,
                metrics: .measured(ProcessMetrics(cpuTicks: 0, residentBytes: 0))),
            resolved: ResolvedIdentity(
                executablePath: nil, appBundlePath: nil, bundleID: nil, teamID: nil),
            membership: .certain)
        let families = [ProcessFamily(
            id: "f", displayName: "Family", bundlePath: nil, members: [member])]

        #expect(NowPresentation.familyMember(for: wanted, in: families) == nil)
        #expect(NowPresentation.familyMember(for: recycled, in: families) != nil)
    }
}

@Suite("Now footnotes")
struct NowFootnoteTests {
    /// FR-004: the convention travels with the figures. FR-009: the per-app disk
    /// limitation is stated rather than left as a silent omission.
    @Test("Footnotes state the CPU convention and the per-app disk limitation")
    func footnotes() {
        let notes = NowPresentation.footnotes(
            topology: CoreTopology(logical: 8, performance: 4, efficiency: 4))
        #expect(notes.contains { $0.contains("100% is one core fully busy") })
        // Matched against the framework's constant rather than a phrase copied
        // here. This assertion used to name a hand-written paraphrase, which is
        // how two differently worded statements of one limitation came to sit on
        // the same screen (TASK-80).
        #expect(notes.contains(DiskSignals.perApplicationUnavailable))
        #expect(notes.contains { $0.contains("performance and 4 efficiency") })
        #expect(notes.contains { $0.contains("footprint") })
    }
}

// MARK: - Per-metric freshness (TASK-65.14, design 1n)

@Suite("Now, when our own sampling falls behind")
struct NowFreshnessTests {
    private let cadence = Duration.seconds(2)

    @Test("A reading within the promised interval is current; a late one carries its age")
    func agesAreDerivedFromTheReadingTimestamp() {
        let now = Date()
        #expect(NowPresentation.metricFreshness(
            observedAt: now.addingTimeInterval(-1), now: now, cadence: cadence)
            == .current(age: .seconds(1)))
        #expect(NowPresentation.metricFreshness(
            observedAt: now.addingTimeInterval(-45), now: now, cadence: cadence)
            == .stale(age: .seconds(45)))
    }

    /// The failure this screen exists to prevent. `MonitorStore.freshness` can only
    /// be recomputed when a sample arrives, so a loop that has stopped arriving
    /// leaves it saying `.current` indefinitely. Deriving the age from the reading's
    /// timestamp and a clock of our own is what catches that (FR-032).
    @Test("A loop that has stopped arriving reads as stale, not as current")
    func aStalledLoopIsNotCurrent() {
        let now = Date()
        let freshness = NowPresentation.metricFreshness(
            observedAt: now.addingTimeInterval(-120), now: now, cadence: cadence)
        #expect(freshness.isStale)
        #expect(freshness.caption == "as of 2 minutes ago")
    }

    @Test("No reading yet is neither current nor stale")
    func noReadingYet() {
        let freshness = NowPresentation.metricFreshness(
            observedAt: nil, now: Date(), cadence: cadence)
        #expect(freshness == .noReadingYet)
        #expect(!freshness.isStale)
        #expect(freshness.caption == "no reading yet")
    }

    /// FR-031's investigation cadence is 1 s. Twice that is 2 s, which a render a
    /// moment before the next sample would cross — so the threshold has a floor.
    @Test("A 1 s investigation cadence does not read as stale between samples")
    func investigationCadenceHasAFloor() {
        #expect(NowPresentation.staleThreshold(cadence: .seconds(1)) == .seconds(3))
        #expect(NowPresentation.staleThreshold(cadence: .seconds(2)) == .seconds(4))
        #expect(NowPresentation.staleThreshold(cadence: .seconds(5)) == .seconds(10))
    }

    /// FR-034: dimming a value is a colour. The age has to be a word and a glyph as
    /// well, and it has to reach VoiceOver.
    @Test("Staleness is carried by a word and a glyph, and is spoken")
    func stalenessIsNeverColourAlone() {
        let stale = NowPresentation.MetricFreshness.stale(age: .seconds(45))
        #expect(stale.caption == "as of 45 seconds ago")
        #expect(stale.symbolName == "exclamationmark.triangle")
        #expect(stale.spoken == "not current, as of 45 seconds ago")
        #expect(stale.rowCaption == "45 s ago")

        let current = NowPresentation.MetricFreshness.current(age: .seconds(1))
        #expect(current.caption == "current")
        #expect(current.symbolName == nil)
        // A current row carries no age: it would be noise on every row of an
        // ordinary screen.
        #expect(current.rowCaption == nil)
    }

    /// Memory pressure is the one metric on this screen with an age of its own,
    /// because the kernel pushes it through a dispatch source. Everything else is
    /// written in a single pass of the sampling loop and shares one age exactly.
    @Test("An event-driven reading is current regardless of the sampling loop")
    func eventDrivenReadingsAreCurrent() {
        let pushed = NowPresentation.MetricFreshness.reportedOnChange
        #expect(!pushed.isStale)
        #expect(pushed.caption == "current · reported when it changes")
        #expect(pushed.spoken.contains("reported by the system when it changes"))
    }

    @Test("The banner says sampling is behind and that recording has not stopped")
    func bannerSaysRecordingContinues() {
        let banner = NowPresentation.catchingUpBanner(cadence: .seconds(1))
        #expect(banner.headline == "These readings are catching up")
        #expect(banner.body.contains("last reading we trust"))
        #expect(banner.body.contains("Recording is still running"))
        #expect(banner.body.contains("nothing is being lost"))
        #expect(banner.retry == "Retrying every 1 s")
    }

    @Test("The contributor list is headed with the age of the reading it came from")
    func contributorHeaderCarriesTheAge() {
        #expect(NowPresentation.contributorHeaderNote(.stale(age: .seconds(45)))
            == "from the reading 45 seconds ago — not updating right now")
        #expect(NowPresentation.contributorHeaderNote(.current(age: .seconds(1))) == nil)
        #expect(NowPresentation.contributorHeaderNote(.reportedOnChange) == nil)
    }

    /// FR-002: the screen must say that a greyed figure is a record, not a forecast.
    @Test("The footer refuses to estimate anything forward")
    func footerRefusesToExtrapolate() {
        #expect(NowPresentation.staleFootnotes.contains {
            $0.contains("last complete reading")
                && $0.contains("Nothing here is estimated forward")
        })
    }

    /// TASK-65.14 criterion #5. Design 1n promises "the menu bar icon runs on a
    /// higher-priority path, so it keeps updating even while this window is
    /// behind". It does not: `MonitorStore` is `@MainActor`, its sampling loop runs
    /// on the main actor, and both surfaces read the same `@Observable` state. The
    /// claim is removed, and this pins the removal so nobody restores the
    /// reassurance without first making it true.
    @Test("The menu bar is not claimed to be more up to date than the window")
    func theMenuBarIsNotClaimedToBeFresher() {
        let text = NowPresentation.staleFootnotes.joined(separator: " ")
        #expect(!text.lowercased().contains("higher-priority"))
        #expect(!text.lowercased().contains("keeps updating"))
        #expect(text.contains("never more up to date than this window"))
    }

    /// The other half of the same verdict: the icon is not merely no fresher, it is
    /// allowed to be up to `MenuBarIcon.minimumInterval` *behind* the window,
    /// because TASK-65.17's rate limiter holds a state change back (design 2d).
    @Test("The menu bar icon may lag the window by up to the rate limit")
    func theIconMayLagTheWindow() {
        let start = ContinuousClock.now
        let severe = MenuBarIconPresentation(
            state: .incident, showsBadge: true, cappedByExpectedWorkload: false,
            tint: .none, accessibilityLabel: "incident")
        let decision = MenuBarIconRateLimiter.decide(
            displayed: .normal, desired: severe,
            lastChangeAt: start, now: start.advanced(by: .milliseconds(500)),
            minimumInterval: MenuBarIcon.minimumInterval)
        #expect(decision == .hold(remaining: .milliseconds(1500)))
    }
}
