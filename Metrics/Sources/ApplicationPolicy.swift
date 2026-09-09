import Foundation
import Synchronization

/// How the user has classified an application (FR-016).
public enum PolicyClassification: String, Sendable, Codable, CaseIterable {
    /// Heavy load is normal for this application; record but do not interrupt.
    case expected
    /// Never alert for this application at all.
    case ignored
    /// Alert as usual, but the user has explicitly said so.
    case watched

    public var label: String {
        switch self {
        case .expected: "Heavy load is expected"
        case .ignored: "Never alert me"
        case .watched: "Watch closely"
        }
    }

    /// FR-016: suppressing an alert must never suppress the record.
    public var suppressesNotification: Bool { self != .watched }
}

/// A user's rule for one application (FR-016, amendment 1).
///
/// **A rule is one application *and* one condition.** "Xcode's heavy load is
/// expected" is not "Xcode can never cause a problem", and until amendment 1 this
/// type could only express the second: a rule set because compiles are normal
/// silenced a memory-pressure finding about the same application, which is a claim
/// the person never made. `conditions` is what makes the narrower claim sayable.
public struct ApplicationPolicy: Sendable, Codable, Equatable, Identifiable {
    /// Keyed on the stable identity where available. TASK-3 established that
    /// teamID+bundleID survives app updates and path changes, while the bundle
    /// path survives when a signature is unavailable — so both are kept.
    public let bundleID: String?
    public let bundlePath: String?
    public let displayName: String
    public var classification: PolicyClassification
    /// The conditions this rule is about. Never empty — a rule that named nothing
    /// would either suppress everything or nothing, and which of those it did would
    /// depend on the reader.
    public var conditions: Set<IncidentCondition>
    public let createdAt: Date

    public var id: String { bundleID ?? bundlePath ?? displayName }

    public init(
        bundleID: String? = nil, bundlePath: String? = nil,
        displayName: String, classification: PolicyClassification,
        conditions: Set<IncidentCondition> = [.cpuSaturation],
        createdAt: Date = Date()
    ) {
        self.bundleID = bundleID
        self.bundlePath = bundlePath
        self.displayName = displayName
        self.classification = classification
        self.conditions = conditions.isEmpty ? [.cpuSaturation] : conditions
        self.createdAt = createdAt
    }

    /// Decoding, with the amendment-1 migration written out rather than defaulted.
    ///
    /// A rule stored before `conditions` existed was application-wide, and carrying
    /// it forward as application-wide would preserve exactly the defect the
    /// amendment removes. So the scope is reconstructed from what the rule *said*:
    ///
    /// - `.expected` — "heavy load is expected" — was always the CPU claim, and the
    ///   only writer of it (`MonitorStore.markExpected`) had already commented that
    ///   it meant CPU. It migrates to CPU alone.
    /// - `.ignored` — "never alert me" — was deliberately unconditional, so it keeps
    ///   every condition. Narrowing it would silently start alerting someone who
    ///   asked not to be.
    /// - `.watched` suppresses nothing either way; every condition is the harmless
    ///   answer.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
        bundlePath = try container.decodeIfPresent(String.self, forKey: .bundlePath)
        displayName = try container.decode(String.self, forKey: .displayName)
        classification = try container.decode(PolicyClassification.self, forKey: .classification)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        let stored = try container.decodeIfPresent(
            Set<IncidentCondition>.self, forKey: .conditions)
        conditions = switch (stored, classification) {
        case (let decoded?, _) where !decoded.isEmpty: decoded
        case (_, .expected): [.cpuSaturation]
        case (_, .ignored), (_, .watched): Set(IncidentCondition.allCases)
        }
    }

    /// Whether this policy applies to a resolved process identity.
    public func matches(_ identity: ResolvedIdentity, displayName name: String) -> Bool {
        if let bundleID, let candidate = identity.bundleID, bundleID == candidate { return true }
        if let bundlePath, let candidate = identity.appBundlePath, bundlePath == candidate {
            return true
        }
        return bundleID == nil && bundlePath == nil && displayName == name
    }

    /// Whether this rule has anything to say about one condition.
    public func applies(to condition: IncidentCondition) -> Bool {
        conditions.contains(condition)
    }

    /// The rule read back as a sentence, for a list and for VoiceOver.
    public var summary: String {
        let named = conditions.map(\.label).sorted().joined(separator: ", ")
        return "\(displayName) — \(classification.label), for \(named)"
    }
}

/// A detection that a policy suppressed (FR-016).
///
/// The audit trail is the point: an alert the user never saw must still be
/// findable, or a policy becomes a way to hide evidence from yourself.
public struct SuppressedDetection: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let application: String
    public let classification: PolicyClassification
    public let at: Date
    public let severity: IncidentSeverity
    /// The incident this suppression belongs to (FR-016).
    ///
    /// Optional because a suppression can be recorded before an incident opens —
    /// the policy is consulted at detection, and detection precedes the episode.
    /// Where it is set, the audit trail in `PolicyStore` and the incident in the
    /// history are the same event seen from two directions, and a screen can say
    /// *why* a particular slowdown never interrupted the user.
    public let incidentID: UUID?
    /// Which condition the rule was about (FR-016 amendment 1).
    ///
    /// Optional, and nil for a trail entry written before rules named a condition.
    /// The trail's whole job is to say what a rule hid, and after the amendment
    /// "Xcode, not alerted" is no longer a complete answer — the reader has to be
    /// able to see that the memory finding would still have reached them.
    public let condition: IncidentCondition?

    public init(id: UUID = UUID(), application: String,
                classification: PolicyClassification, at: Date = Date(),
                severity: IncidentSeverity, incidentID: UUID? = nil,
                condition: IncidentCondition? = nil) {
        self.id = id
        self.application = application
        self.classification = classification
        self.at = at
        self.severity = severity
        self.incidentID = incidentID
        self.condition = condition
    }

    public var summary: String {
        guard let condition else {
            return "\(application) — \(classification.label), not alerted"
        }
        return "\(application) — \(classification.label) for \(condition.label), not alerted"
    }

    /// A copy keyed to the incident it suppressed.
    public func linked(to incidentID: UUID) -> SuppressedDetection {
        SuppressedDetection(
            id: id, application: application, classification: classification,
            at: at, severity: severity, incidentID: incidentID, condition: condition)
    }
}

/// User corrections to grouping (FR-039), stored alongside policies because both
/// are the user telling us something we could not measure.
///
/// **The key is deliberately not a PID.** PIDs are reused — macOS wraps allocation
/// at 99999 and the counter had already wrapped on a machine with twelve days of
/// uptime — so a correction keyed on one would attach itself to an unrelated
/// process within days, and would not survive a restart at all. A correction is
/// keyed on what the process *is*:
///
/// - `executablePath` when it was known when the correction was made. This is the
///   precise key, and it is nearly always available: `proc_pidpath` answers for
///   1042 of 1063 processes and is unaffected by the sandbox.
/// - `processCommand` — the kernel's `p_comm` — otherwise. Durable for the same
///   reason, but coarse: `p_comm` is 16 bytes, so a correction made this way applies
///   to every process whose truncated command matches. The interface says so rather
///   than letting the user discover it.
public struct GroupingCorrection: Sendable, Codable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Codable {
        /// Pull a process out of the family we inferred.
        case split
        /// Put a process into a named family.
        case merge
    }

    public let processCommand: String
    /// The executable's full path when the correction was made, when it was known.
    ///
    /// Optional, and decoded as nil when absent, so corrections written before this
    /// field existed keep working on their command key rather than being dropped.
    public let executablePath: String?
    public let kind: Kind
    /// Target family for a merge.
    public let intoBundlePath: String?
    /// The name the user saw when they made the correction.
    ///
    /// Kept because a correction outlives the process it was made about: a list of
    /// corrections has to be readable when nothing matching them is running, and a
    /// truncated `p_comm` is not a name (FR-002).
    public let displayName: String?
    public let createdAt: Date

    /// One correction per subject, not one per subject *and kind*.
    ///
    /// Keyed this way so that correcting the same process twice replaces the earlier
    /// decision instead of leaving a split and a merge both stored, where whichever
    /// `overrides(for:)` happened to find first would silently win.
    public var id: String { executablePath ?? processCommand }

    public init(processCommand: String, executablePath: String? = nil, kind: Kind,
                intoBundlePath: String? = nil, displayName: String? = nil,
                createdAt: Date = Date()) {
        self.processCommand = processCommand
        self.executablePath = executablePath
        self.kind = kind
        self.intoBundlePath = intoBundlePath
        self.displayName = displayName
        self.createdAt = createdAt
    }

    /// What to call this correction's subject in the interface.
    public var subject: String { displayName ?? processCommand }

    /// Whether this correction is about the given process.
    ///
    /// A correction that carries a path matches only on the path — never falling
    /// back to the command, which would silently widen a precise correction into a
    /// coarse one the moment the path became unreadable.
    public func matches(command: String, executablePath: String?) -> Bool {
        if let mine = self.executablePath { return mine == executablePath }
        return processCommand == command
    }

    /// Whether this correction can apply to more than one process, because it had
    /// no path to key on. Stated in the interface (FR-038) rather than left implied.
    public var isKeyedOnCommandOnly: Bool { executablePath == nil }
}

/// Stores what the user has told us (FR-016, FR-039).
///
/// Every rule here is reversible and none of them changes what is recorded — only
/// what interrupts. That separation is the whole design: a user tuning their
/// alerts must not be quietly tuning their evidence.
public final class PolicyStore: Sendable {
    private struct State: Codable {
        var policies: [ApplicationPolicy] = []
        var corrections: [GroupingCorrection] = []
        var suppressed: [SuppressedDetection] = []
    }

    private let state = Mutex(State())
    private let url: URL?
    /// Bounded so the audit trail cannot grow without limit.
    private let maximumSuppressed: Int

    public init(url: URL? = nil, maximumSuppressed: Int = 200) {
        self.url = url
        self.maximumSuppressed = maximumSuppressed
        restore()
    }

    // MARK: - Policies

    public var policies: [ApplicationPolicy] { state.withLock { $0.policies } }

    public func setPolicy(_ policy: ApplicationPolicy) {
        state.withLock { state in
            state.policies.removeAll { $0.id == policy.id }
            state.policies.append(policy)
        }
        persist()
    }

    /// FR-016: the user can revoke a policy. Removing it restores default
    /// behaviour completely; nothing lingers.
    public func removePolicy(id: String) {
        state.withLock { $0.policies.removeAll { $0.id == id } }
        persist()
    }

    public func policy(
        for identity: ResolvedIdentity, displayName: String
    ) -> ApplicationPolicy? {
        state.withLock { state in
            state.policies.first { $0.matches(identity, displayName: displayName) }
        }
    }

    // MARK: - Suppression audit trail

    public var suppressedDetections: [SuppressedDetection] {
        state.withLock { $0.suppressed }
    }

    /// The suppressions belonging to one incident (FR-016), so "why was I not told
    /// about this?" is answerable from the incident rather than only from a
    /// separate list the user has to correlate by hand.
    public func suppressedDetections(forIncident id: UUID) -> [SuppressedDetection] {
        state.withLock { $0.suppressed.filter { $0.incidentID == id } }
    }

    public func recordSuppression(_ detection: SuppressedDetection) {
        state.withLock { state in
            state.suppressed.insert(detection, at: 0)
            if state.suppressed.count > maximumSuppressed {
                state.suppressed.removeLast(state.suppressed.count - maximumSuppressed)
            }
        }
        persist()
    }

    // MARK: - Grouping corrections

    public var corrections: [GroupingCorrection] { state.withLock { $0.corrections } }

    public func addCorrection(_ correction: GroupingCorrection) {
        state.withLock { state in
            state.corrections.removeAll { $0.id == correction.id }
            state.corrections.append(correction)
        }
        persist()
    }

    public func removeCorrection(id: String) {
        state.withLock { $0.corrections.removeAll { $0.id == id } }
        persist()
    }

    /// Corrections as grouping overrides, for FamilyGrouper.
    ///
    /// Resolves each correction's durable key — executable path, or command where
    /// there was no path — back onto the identities present in *this* snapshot. The
    /// `ProcessIdentity` keys in the result are therefore recomputed every sweep and
    /// never stored, which is what lets a correction survive the process it was made
    /// about being replaced by one with a different PID.
    ///
    /// Returns `.none` immediately when the user has made no corrections, which is
    /// the overwhelmingly common case: without that early exit this would take a
    /// resolver lock once per process on every sweep to answer "no" ~1000 times.
    public func overrides(
        for snapshot: ProcessSnapshot, resolver: ProcessIdentityResolver? = nil
    ) -> GroupingOverrides {
        let corrections = self.corrections
        guard !corrections.isEmpty else { return .none }
        var detached: Set<ProcessIdentity> = []
        var attached: [ProcessIdentity: String] = [:]

        for record in snapshot.records.values {
            // Served from the resolver's (pid, start time) cache, so this is a
            // dictionary lookup and not the ~760 ms of filesystem work a full
            // resolution pass costs.
            let path = resolver?.identity(for: record.identity).executablePath
            guard let correction = corrections.first(where: {
                $0.matches(command: record.command, executablePath: path)
            }) else { continue }
            switch correction.kind {
            case .split: detached.insert(record.identity)
            case .merge:
                if let target = correction.intoBundlePath {
                    attached[record.identity] = target
                }
            }
        }
        return GroupingOverrides(detached: detached, attached: attached)
    }

    // MARK: - Persistence

    public func removeAll() {
        state.withLock { $0 = State() }
        persist()
    }

    private func persist() {
        guard let url else { return }
        let snapshot = state.withLock { $0 }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func restore() {
        guard let url, let data = try? Data(contentsOf: url),
              let restored = try? JSONDecoder().decode(State.self, from: data)
        else { return }
        state.withLock { $0 = restored }
    }
}
