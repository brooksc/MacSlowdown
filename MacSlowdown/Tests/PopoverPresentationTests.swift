import Darwin
import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

private func identity(_ pid: pid_t) -> ProcessIdentity {
    ProcessIdentity(pid: pid, startTime: UInt64(pid) * 1000)
}

private func record(_ pid: pid_t, command: String, measurable: Bool = true) -> ProcessRecord {
    ProcessRecord(
        identity: identity(pid), command: command,
        uid: measurable ? getuid() : 0, ppid: 1,
        metrics: measurable
            ? .measured(ProcessMetrics(cpuTicks: 0, residentBytes: 1 << 20))
            : .notPermitted)
}

private func familyRow(
    _ name: String, percent: Double, members: [ProcessRecord], bundlePath: String? = nil
) -> MonitorStore.FamilyRow {
    let family = ProcessFamily(
        id: bundlePath ?? name, displayName: name, bundlePath: bundlePath,
        members: members.map {
            FamilyMember(
                record: $0,
                resolved: ResolvedIdentity(
                    executablePath: bundlePath.map { $0 + "/Contents/MacOS/" + name },
                    appBundlePath: bundlePath, bundleID: nil, teamID: nil),
                membership: .certain)
        })
    return MonitorStore.FamilyRow(
        family: family, percentOfOneCore: percent, residentBytes: 1 << 20)
}

@Suite("Popover verdict and proof of monitoring")
struct PopoverVerdictTests {
    /// The design's whole premise: a sentence a person can act on, not a label.
    @Test("A healthy machine gets a plain-language sentence, not a severity word")
    func healthyVerdictIsASentence() {
        let verdict = PopoverPresentation.verdict(severity: .normal, incidentOpen: false)
        #expect(verdict.headline == "Your Mac is running normally")
        #expect(verdict.headline != Severity.normal.label)
        #expect(!verdict.symbolName.isEmpty)
    }

    @Test("Every severity carries both a sentence and a symbol", arguments: Severity.allCases)
    func everySeverityHasBoth(severity: Severity) {
        let verdict = PopoverPresentation.verdict(severity: severity, incidentOpen: false)
        #expect(verdict.headline.count > "Normal".count)
        #expect(!verdict.symbolName.isEmpty)
    }

    /// The healthy copy must never sit over an open incident. The triage
    /// presentation itself is TASK-65.2.
    @Test("An open incident is never described as running normally")
    func openIncidentOverridesHealthyCopy() {
        let verdict = PopoverPresentation.verdict(severity: .normal, incidentOpen: true)
        #expect(!verdict.headline.contains("normally"))
    }

    /// "No slowdowns" alone is equally consistent with the app being broken.
    @Test("The reassurance line states when watching began")
    func lineProvesMonitoringIsRunning() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let line = PopoverPresentation.monitoringLine(
            isRunning: true, watchingSince: start, now: start.addingTimeInterval(3600),
            incidentCount: 0, timeText: { _ in "8:02 AM" })
        #expect(line.contains("No slowdowns"))
        #expect(line.contains("8:02 AM"))
    }

    /// FR-038: we may only claim the window we actually observed. Incidents live
    /// in memory for this session, so a five-minute-old process cannot speak for
    /// the last 24 hours.
    @Test("A 24-hour claim is only made after 24 hours of watching")
    func windowIsObservedNotClaimed() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let short = PopoverPresentation.monitoringLine(
            isRunning: true, watchingSince: start, now: start.addingTimeInterval(600),
            incidentCount: 0, timeText: { _ in "8:02 AM" })
        #expect(!short.contains("24 hours"))
        #expect(short.contains("when monitoring started"))

        let long = PopoverPresentation.monitoringLine(
            isRunning: true, watchingSince: start, now: start.addingTimeInterval(25 * 3600),
            incidentCount: 0, timeText: { _ in "8:02 AM" })
        #expect(long.contains("in the last 24 hours"))
    }

    @Test("Stopped monitoring is stated, not implied by an absence of incidents")
    func notRunningIsStated() {
        let line = PopoverPresentation.monitoringLine(
            isRunning: false, watchingSince: Date(), now: Date(), incidentCount: 0)
        #expect(line.contains("not running"))
        #expect(!line.contains("No slowdowns"))
    }

    @Test("Observed incidents are counted, singular and plural")
    func incidentCounts() {
        #expect(PopoverPresentation.incidentPhrase(0) == "No slowdowns")
        #expect(PopoverPresentation.incidentPhrase(1) == "1 slowdown")
        #expect(PopoverPresentation.incidentPhrase(4) == "4 slowdowns")
    }
}

@Suite("Popover headline figures")
struct PopoverTileTests {
    private func tiles(
        attribution: CPUAttribution? = nil,
        pressure: MemoryPressureLevel = .normal,
        disk: DiskRates? = nil,
        storage: VolumeCapacity? = nil
    ) -> [PopoverPresentation.MetricTile] {
        PopoverPresentation.tiles(
            attribution: attribution, memoryPressure: pressure,
            diskRates: disk, storage: storage)
    }

    private func volume(available: UInt64, total: UInt64) -> VolumeCapacity {
        VolumeCapacity(
            url: URL(fileURLWithPath: "/"), name: "Macintosh HD", isStartupVolume: true,
            isRemovable: false, isNetwork: false, totalBytes: total,
            availableBytes: available, purgeableEstimateBytes: 20 << 30)
    }

    /// Criterion #2: the four-up strip the design specifies.
    @Test("The strip covers CPU, memory pressure, disk and storage free")
    func stripCoversFourFigures() {
        let labels = tiles().map(\.label)
        #expect(labels == ["CPU", "Memory pressure", "Disk", "Storage free"])
    }

    /// FR-002: an unavailable measurement is labelled, never rendered as zero —
    /// "0 B/s" claims an idle disk, which is a different statement.
    @Test("An unread disk counter is unavailable, not zero")
    func unavailableDiskIsNotZero() {
        let disk = tiles().first { $0.id == "disk" }!
        #expect(!disk.isAvailable)
        #expect(disk.value == "Unavailable")
        #expect(!disk.value.contains("0"))
    }

    @Test("A volume that did not report is unavailable, not zero bytes free")
    func unavailableStorageIsNotZero() {
        let storage = tiles().first { $0.id == "storage" }!
        #expect(!storage.isAvailable)
        #expect(storage.value == "Unavailable")
        #expect(storage.barFraction == nil)
    }

    @Test("A measured disk rate is stated per second, both directions in detail")
    func diskRateIsARate() {
        let disk = tiles(disk: DiskRates(
            readBytesPerSecond: 4_000_000, writeBytesPerSecond: 2_000_000))
            .first { $0.id == "disk" }!
        #expect(disk.isAvailable)
        #expect(disk.value.hasSuffix("/s"))
        #expect(disk.value.contains("6"))  // read + write
        #expect(disk.detail.contains("read"))
        #expect(disk.detail.contains("write"))
    }

    /// FR-041: purgeable space is an estimate of what macOS might reclaim, so it
    /// must not be added into the free figure.
    @Test("Storage free reports available space, not available plus purgeable")
    func purgeableIsNotCountedAsFree() {
        let storage = tiles(storage: volume(available: 214 << 30, total: 1000 << 30))
            .first { $0.id == "storage" }!
        #expect(storage.isAvailable)
        #expect(storage.value.contains("214") || storage.value.contains("229"))
        #expect(!storage.value.contains("234"))
        #expect(storage.barFraction != nil)
        #expect(abs(storage.barFraction! - 0.786) < 0.01)
    }

    /// FR-007: memory pressure is not percent of RAM used, and a number here
    /// would invite exactly that reading.
    @Test("Memory pressure is reported as a level with its meaning")
    func memoryPressureIsALevel() {
        let tile = tiles(pressure: .warning).first { $0.id == "memory" }!
        #expect(tile.value == "Warning")
        #expect(tile.detail == MemoryPressureLevel.warning.explanation)
    }

    @Test("Before the first reading CPU is pending, not zero")
    func cpuBeforeFirstReading() {
        let tile = tiles().first { $0.id == "cpu" }!
        #expect(!tile.isAvailable)
        #expect(tile.detail.contains("two samples"))
    }
}

@Suite("Popover contributor rows")
struct PopoverContributorTests {
    private let attribution = 60.0

    private func rows(
        _ families: [MonitorStore.FamilyRow], unattributed: Double = 20
    ) -> [PopoverPresentation.ContributorRow] {
        PopoverPresentation.contributorRows(
            families: families, attributedPercentOfOneCore: attribution,
            unattributedPercentOfOneCore: unattributed)
    }

    /// Criterion #3.
    @Test("A row carries the name, the process count and the percentage")
    func rowCarriesNameCountAndPercent() {
        let safari = familyRow(
            "Safari", percent: 47,
            members: (1...9).map { record($0, command: "Safari") },
            bundlePath: "/Applications/Safari.app")
        let row = rows([safari]).first { $0.kind == .application }!
        #expect(row.name == "Safari")
        #expect(row.processCount == 9)
        #expect(row.percentOfOneCore == 47)
        #expect(row.executablePath?.contains("Safari.app") == true)
    }

    /// Criterion #4: a peer row, not a footnote. It is routinely one of the
    /// largest entries and must rank with the rest.
    @Test("Unattributed system activity ranks among the applications")
    func unattributedIsAPeer() {
        let list = rows(
            [familyRow("Photos", percent: 12, members: [record(1, command: "Photos")])],
            unattributed: 42)
        #expect(list.first?.kind == .unattributed)
        #expect(list.contains { $0.kind == .application })
    }

    @Test("Unattributed activity is present even when it is zero")
    func unattributedAlwaysPresent() {
        let list = rows(
            [familyRow("Photos", percent: 12, members: [record(1, command: "Photos")])],
            unattributed: 0)
        #expect(list.contains { $0.kind == .unattributed })
    }

    /// Criterion #4: a family we can only partly measure is a floor, not a total.
    @Test("A family with unmeasurable members is marked partial")
    func partialAttributionIsMarked() {
        let spotlight = familyRow(
            "Spotlight indexing", percent: 19,
            members: [record(1, command: "mds"), record(2, command: "mds_stores", measurable: false)])
        let row = rows([spotlight]).first { $0.kind == .application }!
        #expect(row.isPartial)
        #expect(PopoverPresentation.accessibilityLabel(for: row).contains("partly measured"))
    }

    @Test("A fully measured family is not marked partial")
    func fullyMeasuredIsNotPartial() {
        let photos = familyRow("Photos", percent: 12, members: [record(1, command: "Photos")])
        let row = rows([photos]).first { $0.kind == .application }!
        #expect(!row.isPartial)
        #expect(!PopoverPresentation.accessibilityLabel(for: row).contains("partly"))
    }

    /// The rows have to visibly account for the machine. Truncating the list is
    /// the same failure the unattributed row exists to prevent.
    @Test("Measured activity beyond the listed rows is still shown")
    func remainderIsAccountedFor() {
        let families = (1...6).map {
            familyRow("App \($0)", percent: 10, members: [record(pid_t($0), command: "app")])
        }
        let list = rows(families)
        let other = list.first { $0.kind == .other }
        #expect(other != nil)
        #expect(abs(other!.percentOfOneCore - 30) < 0.001)  // 60 attributed, 30 listed
        #expect(list.last?.kind == .other)
    }

    @Test("A family using no CPU does not appear under 'using the most CPU now'")
    func zeroCPUFamiliesAreOmitted() {
        let idle = familyRow("Idle", percent: 0, members: [record(1, command: "idle")])
        #expect(!rows([idle]).contains { $0.kind == .application })
    }

    /// FR-034: VoiceOver has to hear the same qualifiers the eye reads.
    @Test("The spoken row includes the process count and the unit")
    func accessibilityLabelIsComplete() {
        let safari = familyRow(
            "Safari", percent: 47,
            members: (1...9).map { record($0, command: "Safari") })
        let label = PopoverPresentation.accessibilityLabel(
            for: rows([safari]).first { $0.kind == .application }!)
        #expect(label.contains("Safari"))
        #expect(label.contains("9 processes"))
        #expect(label.contains("of one core"))
    }
}
