import Darwin
import Foundation

// Does every path that can produce a report honour redaction identically, on real
// data? (TASK-70, FR-028, FR-029)
//
// TASK-65.11 verified the export sheet this way: real processes, a real incident,
// real files on disk, searched for every value the document claims to hide. This
// does the same for both report-producing paths — the sheet's call shape and the
// App Intent's — because the App Intent is the one a person cannot inspect before
// it hands a report to another app.
//
// The probe cannot import the app module, so it makes the same two calls the app
// makes: the sheet supplies contributor paths gathered from the families it is
// showing, the intent asks `IncidentReport.contributorPaths(in:)` for them. That
// the app's own types agree byte for byte is asserted in ExportPathParityTests;
// what is checked here is that they agree on *real* data, where the values are the
// operator's actual user name, actual running applications and actual paths.
//
// Counting, not substring absence: a live process may legitimately share a name
// with something in the report's scaffolding — TASK-65.11 hit exactly this with a
// process called `MacSlowdown`. Each value is counted in a contributor-free
// scaffold document first, and a redacted report must not exceed that baseline.
//
// Build: probe/build-with-metrics.sh Sources/export-paths-probe.swift
// Run:   open probe/build/export-paths-probe.app  (never exec from a shell — TCC)
//        Results are printed and written to /tmp/export-paths-probe.log.

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return raised }
        set { lock.lock(); raised = newValue; lock.unlock() }
    }
}

@main
struct ExportPathsProbe {
    static let logURL = URL(fileURLWithPath: "/tmp/export-paths-probe.log")
    nonisolated(unsafe) static var logText = ""

    static func log(_ line: String) {
        print(line)
        logText += line + "\n"
        try? logText.write(to: logURL, atomically: true, encoding: .utf8)
    }

    static func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var index = haystack.startIndex
        while let range = haystack.range(of: needle, range: index..<haystack.endIndex) {
            count += 1
            index = range.upperBound
        }
        return count
    }

    static func main() {
        log("export-paths-probe — TASK-70 (log: \(logURL.path))")

        let sampler = ProcessSampler()
        let resolver = ProcessIdentityResolver()

        guard var hostPrevious = HostCPU.sample() else {
            log("FAIL: no host CPU sample"); exit(1)
        }
        let hostBefore = hostPrevious
        let snapshotBefore = sampler.snapshot()

        // Real load, so the incident the detector opens responds to something that
        // actually happened rather than a fabricated observation (FR-006).
        let stop = Flag()
        for _ in 0..<max(2, ProcessInfo.processInfo.activeProcessorCount) {
            Thread.detachNewThread {
                var accumulator = 0.0
                while !stop.value {
                    for value in 0..<200_000 { accumulator += Double(value).squareRoot() }
                }
                if accumulator.isNaN { print("") }
            }
        }

        // The real detector, with a shortened sustained window so a probe run is a
        // minute rather than ten. The thresholds and the hysteresis are the
        // product's; only the durations are compressed, and that is stated.
        let detector = IncidentDetector(policy: IncidentPolicy(
            cpuSustainedDuration: .seconds(3), recoveryDuration: .seconds(3),
            mergeWindow: .seconds(1)))
        var state = IncidentDetector.State()
        var closed: Incident?
        let start = Date()

        func observe(_ step: Int) {
            Thread.sleep(forTimeInterval: 1)
            guard let host = HostCPU.sample() else { return }
            let busy = HostCPU.busyFraction(from: hostPrevious, to: host) ?? 0
            hostPrevious = host
            let event = detector.observe(SystemObservation(
                at: start.addingTimeInterval(Double(step)),
                cpuBusyFraction: busy,
                memoryPressure: MemorySignals.currentPressureLevel(),
                thermalState: .current,
                lowStorage: false), state: &state)
            if case .opened(let incident) = event {
                log("  detector opened an incident at \(incident.beganAt)")
            }
            if case .closed(let incident) = event { closed = incident }
        }

        for step in 0..<8 { observe(step) }
        let snapshotAfter = sampler.snapshot()
        guard let hostAfter = HostCPU.sample() else { log("FAIL: no host"); exit(1) }
        stop.value = true
        for step in 8..<14 { observe(step) }

        guard let subject = closed ?? state.current else {
            log("FAIL: no incident detected — the machine never sustained a breach.")
            log("Honest negative, not a pass. Re-run on a quieter machine.")
            exit(1)
        }
        log("incident: \(subject.conditions.map(\.label).sorted().joined(separator: ", ")), "
            + "severity \(subject.severity.label), peak CPU "
            + "\(Int(subject.peakCPUBusyFraction * 100))%, open=\(subject.isOpen)")

        let families = FamilyGrouper.group(snapshot: snapshotAfter, resolver: resolver)
        let attribution = CPUAttributionCalculator.attribution(
            from: snapshotBefore, to: snapshotAfter,
            hostEarlier: hostBefore, hostLater: hostAfter,
            naming: { resolver.identity(for: $0).friendlyName })
        let summary = IncidentSummarizer.summarize(
            incident: subject, attribution: attribution)
        let machine = MachineContext.current()
        let generatedAt = Date()

        log("processes: \(snapshotAfter.records.count), families: \(families.count), "
            + "contributors: \(attribution.contributors.count)")

        /// What `ExportReportModel` does: it is handed paths the incident screen
        /// gathered from the families it is showing.
        func sheetPath(_ options: RedactionOptions) -> ExportDocument {
            var paths: [ProcessIdentity: String] = [:]
            for family in families {
                for member in family.members {
                    if let path = member.resolved.executablePath {
                        paths[member.record.identity] = path
                    }
                }
            }
            return IncidentReport.document(
                incident: subject, machine: machine, summary: summary,
                attribution: attribution, contributorPaths: paths, sections: .all,
                options: options, generatedAt: generatedAt)
        }

        /// What `UnattendedIncidentReport.make` does for the App Intent.
        func intentPath(_ options: RedactionOptions) -> ExportDocument {
            IncidentReport.document(
                incident: subject, machine: machine, summary: summary,
                attribution: attribution,
                contributorPaths: IncidentReport.contributorPaths(in: families),
                sections: .all, options: options, generatedAt: generatedAt)
        }

        // A report of the same incident with no contributors and nothing
        // identifying: the baseline for how often a value appears for reasons that
        // have nothing to do with the contributor list.
        let scaffold = IncidentReport.document(
            incident: subject, machine: machine,
            summary: IncidentSummarizer.summarize(incident: subject, attribution: nil),
            attribution: nil, contributorPaths: [:], sections: .all,
            options: RedactionOptions(hideUserName: true, hideFilePaths: true,
                                      hideProcessNames: true),
            generatedAt: generatedAt)

        let paths = IncidentReport.contributorPaths(in: families)
        var sensitive: [(kind: String, value: String)] = [("user name", NSUserName())]
        for contributor in attribution.contributors.prefix(5) {
            sensitive.append(("process name", contributor.label))
            if let path = paths[contributor.identity] {
                sensitive.append(("executable path", path))
            }
        }
        sensitive = sensitive.filter { !$0.value.isEmpty }
        log("sensitive values under test: \(sensitive.count)")
        for item in sensitive { log("  \(item.kind): \(item.value)") }

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("export-paths-probe-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        log("files written under: \(directory.path)")

        let hideEverything = RedactionOptions(hideUserName: true, hideFilePaths: true,
                                              hideProcessNames: true)
        let hideNothing = RedactionOptions(hideUserName: false, hideFilePaths: false,
                                           hideProcessNames: false)

        var absent = 0, expectedAbsent = 0
        var present = 0, expectedPresent = 0
        var identical = 0, compared = 0

        for (name, build) in [("sheet", sheetPath), ("intent", intentPath)] {
            for format in ReportFormat.allCases {
                let hidden = build(hideEverything)
                let control = build(hideNothing)
                let hiddenURL = directory
                    .appendingPathComponent("\(name)-hidden.\(format.fileExtension)")
                let controlURL = directory
                    .appendingPathComponent("\(name)-control.\(format.fileExtension)")
                try? hidden.data(as: format).write(to: hiddenURL)
                try? control.data(as: format).write(to: controlURL)

                // Read back from disk: the file is what leaves the machine.
                let hiddenText = (try? String(contentsOf: hiddenURL, encoding: .utf8)) ?? ""
                let controlText = (try? String(contentsOf: controlURL, encoding: .utf8)) ?? ""
                let scaffoldText = String(decoding: scaffold.data(as: format), as: UTF8.self)

                compared += 2
                if sheetPath(hideEverything).data(as: format) == hidden.data(as: format) {
                    identical += 1
                } else {
                    log("DIVERGED: \(name)/\(format) hidden bytes differ from the sheet")
                }
                if sheetPath(hideNothing).data(as: format) == control.data(as: format) {
                    identical += 1
                } else {
                    log("DIVERGED: \(name)/\(format) control bytes differ from the sheet")
                }

                for item in sensitive {
                    let baseline = occurrences(of: item.value, in: scaffoldText)
                    expectedAbsent += 1
                    let inHidden = occurrences(of: item.value, in: hiddenText)
                    if inHidden <= baseline {
                        absent += 1
                    } else {
                        log("LEAK: \(name)/\(format) still contains \(item.kind) "
                            + "'\(item.value)' — \(inHidden) occurrences against a "
                            + "baseline of \(baseline)")
                    }

                    expectedPresent += 1
                    let inControl = occurrences(of: item.value, in: controlText)
                    if inControl > baseline {
                        present += 1
                    } else {
                        log("CONTROL WEAK: \(name)/\(format) does not carry \(item.kind) "
                            + "'\(item.value)' even when nothing is hidden "
                            + "(\(inControl) against baseline \(baseline))")
                    }
                }
            }
        }

        log("")
        log("hidden:  \(absent) of \(expectedAbsent) sensitive values absent when hidden")
        log("control: \(present) of \(expectedPresent) present when nothing is hidden")
        log("bytes:   \(identical) of \(compared) renderings identical across both paths")
        let passed = absent == expectedAbsent && present == expectedPresent
            && identical == compared
        log(passed ? "PASS" : "FAIL")
        exit(passed ? 0 : 1)
    }
}
