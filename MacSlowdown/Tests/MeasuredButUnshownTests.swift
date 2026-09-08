import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

/// TASK-80 and TASK-81: four things the app measured and never said, plus the one
/// naming predicate that turned out to be a real gap rather than a convenience.
///
/// These are wiring tests, not capability tests. Each capability is already
/// covered in `MetricsTests`; what was missing in every case was a caller, and a
/// passing unit test proves a unit works, not that anything reaches it. So every
/// test here drives the composition the app actually renders from — the card's
/// detail builder, the footnote list, the timeline builder, the row builder —
/// rather than the framework member underneath it.
///
/// What these tests cannot establish: that any of it is legible on screen. Nobody
/// has looked. See the task notes for the exact on-screen checks still owed.

// MARK: - Fixtures

private func usage(used: UInt64, total: UInt64, encrypted: Bool) -> SwapUsage {
    SwapUsage(total: total, used: used, available: total - used, encrypted: encrypted)
}

private func machineMemory() -> UInt64 { 36 * 1_073_741_824 }

// MARK: - 1. Swap usage reaches the Now screen (FR-008)

@Suite("Swap usage is shown, not just swap activity (FR-008)")
struct SwapUsageSurfaceTests {
    @Test("The memory card carries the swap figure alongside the swap activity")
    func memoryCardCarriesSwapUsage() {
        let details = NowPresentation.memoryCardDetails(
            statistics: nil,
            physicalMemoryBytes: machineMemory(),
            swapActivity: "No swapping",
            swapUsage: usage(used: 3_221_225_472, total: 6_442_450_944, encrypted: true))

        // Both halves of FR-008 present: whether pages are moving, and how much
        // swap exists. Before TASK-80 only the first was ever shown.
        #expect(details.contains("No swapping"))
        #expect(details.contains { $0.contains("swap in use") })
        #expect(details.contains { $0.contains("encrypted") })
    }

    @Test("Unreadable swap says unavailable, never zero")
    func unreadableSwapIsNotZero() {
        let details = NowPresentation.memoryCardDetails(
            statistics: nil, physicalMemoryBytes: machineMemory(),
            swapActivity: "No swapping", swapUsage: nil)

        #expect(details.contains("Swap usage unavailable"))
        // A swap file we could not read is not an empty one (FR-002, FR-010).
        #expect(!details.contains { $0.contains("0 bytes swap") })
        #expect(!details.contains { $0.contains("No swap in use") })
    }

    @Test("An empty swap file is stated as empty, and is a different claim")
    func emptySwapIsMeasured() {
        let text = Presentation.swapInUse(
            usage(used: 0, total: 2_147_483_648, encrypted: false))
        #expect(text.contains("No swap in use"))
        #expect(text.contains("not encrypted"))
    }

    /// FR-036 and DR-08. Swap is not waste and must never be described as
    /// something the user could reclaim.
    @Test("Swap is never described as reclaimable")
    func swapIsNotDescribedAsWaste() {
        let phrasings = [
            Presentation.swapInUse(usage(used: 3_221_225_472, total: 6_442_450_944,
                                         encrypted: true)),
            Presentation.swapInUse(usage(used: 0, total: 0, encrypted: false)),
            Presentation.swapInUse(nil),
        ]
        for text in phrasings {
            let lowered = text.lowercased()
            for forbidden in ["free up", "freed", "wasted", "reclaim", "clean", "optimi"] {
                #expect(!lowered.contains(forbidden), "“\(forbidden)” in “\(text)”")
            }
        }
    }
}

// MARK: - 2. The per-application disk limitation is stated once (FR-009)

@Suite("Per-application disk I/O unavailability is stated (FR-009)")
struct DiskUnavailabilitySurfaceTests {
    @Test("The Now screen's footnotes carry the framework's own sentence")
    func footnotesCarryTheStatement() {
        #expect(NowPresentation.footnotes().contains(DiskSignals.perApplicationUnavailable))
    }

    /// The point of routing both surfaces through one constant. Two hand-written
    /// paraphrases sat on this screen and either could have drifted from what the
    /// app actually does.
    @Test("No second, separately worded paraphrase remains in the footnotes")
    func onlyOneWordingSurvives() {
        let paraphrases = NowPresentation.footnotes().filter {
            $0.lowercased().contains("per-app") || $0.lowercased().contains("per-application")
        }
        #expect(paraphrases == [DiskSignals.perApplicationUnavailable])
    }

    @Test("The statement says why, not merely that it is missing")
    func statementExplainsWhy() {
        let text = DiskSignals.perApplicationUnavailable.lowercased()
        #expect(text.contains("macos does not report"))
        #expect(text.contains("app store"))
    }
}

// MARK: - 3. Incident start provenance reaches the timeline (FR-038)

@Suite("A reconstructed incident start says so (FR-038)")
struct StartProvenanceSurfaceTests {
    private func incident(reconstructed: Bool) -> Incident {
        let began = Date(timeIntervalSince1970: 1_770_000_000)
        var incident = Incident(
            id: UUID(), beganAt: began, triggeredAt: began.addingTimeInterval(90),
            recoveryStartedAt: nil, closedAt: began.addingTimeInterval(600),
            conditions: [.cpuSaturation], severity: .moderate,
            peakCPUBusyFraction: 0.9, peakMemoryPressure: .normal)
        incident.beganAtEstablishedFromRetainedHistory = reconstructed
        return incident
    }

    @Test("The timeline the view renders carries the provenance conclusion")
    func timelineCarriesProvenance() {
        let line = IncidentTimeline.build(incident: incident(reconstructed: true))
        #expect(line.startProvenance != nil)
        // FR-038: the claim travels with its evidence class, and this one is
        // measured — the readings were real, they were simply kept rather than
        // watched.
        #expect(line.startProvenance?.evidence == .measured)
        #expect(line.startProvenance?.text.contains("already kept") == true)
    }

    @Test("An ordinary incident has nothing to explain and says nothing")
    func ordinaryIncidentHasNoProvenanceRow() {
        let line = IncidentTimeline.build(incident: incident(reconstructed: false))
        #expect(line.startProvenance == nil)
    }
}

// MARK: - 4. Storage trend carries its provenance label (FR-038)

@Suite("Storage trend is labelled as a calculation (FR-038)")
struct StorageTrendProvenanceTests {
    @Test("A direction over a window is Calculated")
    func directionsAreCalculated() {
        let trends: [StorageTrend] = [
            .steady(over: .seconds(3600)),
            .declining(bytes: 1 << 30, over: .seconds(3600), stillFalling: true),
            .rising(bytes: 1 << 30, over: .seconds(3600)),
        ]
        for trend in trends {
            #expect(StoragePresentation.trendProvenance(trend) == "Calculated",
                    "\(trend) should be labelled as derived")
        }
    }

    /// Not a calculation: it reports how many readings exist and how long they
    /// span, which is a count of measurements and nothing more.
    @Test("Too little history is Measured, because that is all it claims")
    func insufficientHistoryIsMeasured() {
        let trend = StorageTrend.insufficientHistory(covered: .seconds(300), readings: 3)
        #expect(StoragePresentation.trendProvenance(trend) == "Measured")
    }

    /// The storage screen's footer defines exactly three provenance words. A label
    /// outside that set would be unexplained wherever it appeared.
    @Test("The label is one of the three the screen's footer defines")
    func labelIsInTheDefinedVocabulary() {
        let allowed: Set<String> = ["Measured", "Calculated", "Estimate"]
        let trends: [StorageTrend] = [
            .insufficientHistory(covered: .seconds(0), readings: 0),
            .steady(over: .seconds(60)),
            .declining(bytes: 1, over: .seconds(60), stillFalling: false),
            .rising(bytes: 1, over: .seconds(60)),
        ]
        for trend in trends {
            #expect(allowed.contains(StoragePresentation.trendProvenance(trend)))
        }
    }
}

// MARK: - 5. A truncated command is said aloud, not only drawn (FR-002, FR-034)

@Suite("Truncated process names reach VoiceOver (FR-002, FR-034)")
struct TruncatedNameSurfaceTests {
    /// `p_comm` is 16 bytes. `displayName` marks the cut with an ellipsis, which
    /// is silent to VoiceOver — the gap this closes.
    private func member(command: String, friendlyName: String?) -> FamilyMember {
        FamilyMember(
            record: ProcessRecord(
                identity: ProcessIdentity(pid: 4_242, startTime: 1_000),
                command: command, uid: getuid(), ppid: 1,
                metrics: .measured(ProcessMetrics(cpuTicks: 0, residentBytes: 1 << 20))),
            resolved: ResolvedIdentity(
                executablePath: "/usr/libexec/\(command)", appBundlePath: nil,
                bundleID: nil, teamID: nil, friendlyName: friendlyName),
            membership: .certain)
    }

    /// Built the way `FamilyGrouper` builds one: a standalone process's family
    /// takes its display name from the resolved identity, so the ellipsis is on
    /// the family row too. Naming it from the raw command instead would test a
    /// family the app never constructs.
    private func rows(_ member: FamilyMember) -> [InventoryRow] {
        let family = ProcessFamily(
            id: "f",
            displayName: member.resolved.displayName(command: member.record.command),
            bundlePath: nil,
            members: [member])
        return Presentation.inventory(
            [family],
            contributions: [member.record.identity: 5],
            unattributedPercentOfOneCore: 0)
    }

    @Test("A 16-byte command is flagged as shortened on the row")
    func truncatedCommandIsFlagged() {
        let row = rows(member(command: "MTLCompilerServi", friendlyName: nil)).first
        #expect(row?.nameIsShortened == true)
        // The visual marker is still there; the flag is what carries it into speech.
        #expect(row?.name.contains("…") == true)
    }

    @Test("A short command is not flagged")
    func shortCommandIsNotFlagged() {
        #expect(rows(member(command: "zsh", friendlyName: nil)).first?.nameIsShortened == false)
    }

    /// The case that makes the predicate more than a length check: the command was
    /// cut, but we resolved a real name, so there is nothing shortened on display.
    @Test("A resolved friendly name is not a truncated command, however long")
    func resolvedNameIsNotShortened() {
        let row = rows(member(command: "MediaApp Helper (", friendlyName: "MediaApp")).first
        #expect(row?.name == "MediaApp")
        #expect(row?.nameIsShortened == false)
    }

    @Test("The all-processes table flags it too")
    func allProcessesRowIsFlagged() {
        let cut = member(command: "MTLCompilerServi", friendlyName: nil)
        let family = ProcessFamily(
            id: "f",
            displayName: cut.resolved.displayName(command: cut.record.command),
            bundlePath: nil, members: [cut])
        let row = AllProcesses.rows([family], contributions: [:]).first
        #expect(row?.nameIsShortened == true)
    }

    @Test("The spoken wording exists once, so the two tables cannot disagree")
    func oneWordingForBothTables() {
        #expect(ProcessNaming.truncationNote == "name shortened by the system")
        #expect(ProcessNaming.accessibilityLabel(command: "MTLCompilerServi")
            .contains(ProcessNaming.truncationNote))
    }
}
