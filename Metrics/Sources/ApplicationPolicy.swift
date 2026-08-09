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

/// A user's rule for one application.
public struct ApplicationPolicy: Sendable, Codable, Equatable, Identifiable {
    /// Keyed on the stable identity where available. TASK-3 established that
    /// teamID+bundleID survives app updates and path changes, while the bundle
    /// path survives when a signature is unavailable — so both are kept.
    public let bundleID: String?
    public let bundlePath: String?
    public let displayName: String
    public var classification: PolicyClassification
    public let createdAt: Date

    public var id: String { bundleID ?? bundlePath ?? displayName }

    public init(
        bundleID: String? = nil, bundlePath: String? = nil,
        displayName: String, classification: PolicyClassification,
        createdAt: Date = Date()
    ) {
        self.bundleID = bundleID
        self.bundlePath = bundlePath
        self.displayName = displayName
        self.classification = classification
        self.createdAt = createdAt
    }

    /// Whether this policy applies to a resolved process identity.
    public func matches(_ identity: ResolvedIdentity, displayName name: String) -> Bool {
        if let bundleID, let candidate = identity.bundleID, bundleID == candidate { return true }
        if let bundlePath, let candidate = identity.appBundlePath, bundlePath == candidate {
            return true
        }
        return bundleID == nil && bundlePath == nil && displayName == name
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

    public init(id: UUID = UUID(), application: String,
                classification: PolicyClassification, at: Date = Date(),
                severity: IncidentSeverity, incidentID: UUID? = nil) {
        self.id = id
        self.application = application
        self.classification = classification
        self.at = at
        self.severity = severity
        self.incidentID = incidentID
    }

    public var summary: String {
        "\(application) — \(classification.label), not alerted"
    }

    /// A copy keyed to the incident it suppressed.
    public func linked(to incidentID: UUID) -> SuppressedDetection {
        SuppressedDetection(
            id: id, application: application, classification: classification,
            at: at, severity: severity, incidentID: incidentID)
    }
}

/// User corrections to grouping (FR-039), stored alongside policies because both
/// are the user telling us something we could not measure.
public struct GroupingCorrection: Sendable, Codable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Codable {
        /// Pull a process out of the family we inferred.
        case split
        /// Put a process into a named family.
        case merge
    }

    public let processCommand: String
    public let kind: Kind
    /// Target family for a merge.
    public let intoBundlePath: String?
    public let createdAt: Date

    public var id: String { "\(kind.rawValue):\(processCommand)" }

    public init(processCommand: String, kind: Kind,
                intoBundlePath: String? = nil, createdAt: Date = Date()) {
        self.processCommand = processCommand
        self.kind = kind
        self.intoBundlePath = intoBundlePath
        self.createdAt = createdAt
    }
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
    /// Note this maps by command name rather than process identity: a correction
    /// must outlive the process it was made about, and PIDs do not.
    public func overrides(for snapshot: ProcessSnapshot) -> GroupingOverrides {
        let corrections = self.corrections
        var detached: Set<ProcessIdentity> = []
        var attached: [ProcessIdentity: String] = [:]

        for record in snapshot.records.values {
            guard let correction = corrections.first(where: {
                $0.processCommand == record.command
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
