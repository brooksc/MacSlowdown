import Foundation

/// How confident we are that a process belongs to the family it was placed in.
///
/// FR-003 requires uncertain associations to be labeled; FR-038 requires every
/// conclusion to carry its evidence class. Grouping is a heuristic over public
/// metadata, so the distinction is part of the data, not a UI afterthought.
public enum FamilyMembership: Sendable, Equatable {
    /// The code signature corroborates the path: the process's signed identifier
    /// shares the application's identifier prefix.
    case certain
    /// The executable lives inside the bundle, but the signature does not
    /// corroborate it. Real example from the Tier 0 spike: `node_repl` and
    /// `assistant-helper` executing from inside AssistantApp.app. Attributing them to
    /// AssistantApp is defensible but not certain.
    case uncertain(reason: String)
    /// The process was spawned by the application it is grouped under.
    ///
    /// Distinct from `.certain` because it is a different kind of evidence: the
    /// executable lives outside the bundle entirely, and the association rests on
    /// process lineage. A shell you started in a terminal is genuinely the
    /// terminal's child, and its CPU is genuinely part of what that terminal is
    /// costing you — but it is not part of the application.
    case byParent(reason: String)
    /// The user placed this process here (FR-039).
    case userAssigned

    /// Whether this association needs qualifying to the user. Parent lineage is
    /// evidence, not a guess, so it is not lumped in with uncertainty.
    public var isUncertain: Bool {
        if case .uncertain = self { true } else { false }
    }
}

public struct FamilyMember: Sendable {
    public let record: ProcessRecord
    public let resolved: ResolvedIdentity
    public let membership: FamilyMembership
}

/// A user-meaningful application, or a standalone process.
///
/// Only about 15% of the process table belongs to an application bundle. Daemons
/// and command-line tools are standalone processes in their own right — modelling
/// them as families-of-one would misrepresent the system and clutter the app view.
public struct ProcessFamily: Sendable, Identifiable {
    public let id: String
    public let displayName: String
    /// `nil` for a standalone process.
    public let bundlePath: String?
    /// Individual PID records, always preserved beneath the aggregate (FR-003).
    public let members: [FamilyMember]

    public var isStandalone: Bool { bundlePath == nil }
    public var hasUncertainMembers: Bool { members.contains { $0.membership.isUncertain } }

    /// Members whose CPU and memory the sandbox denies us. They stay visible by
    /// name; their usage belongs in the unattributed bucket.
    public var notMeasurableCount: Int { members.count(where: { !$0.record.isMeasurable }) }
}

/// User corrections to grouping (FR-039). Grouping is reversible by construction:
/// nothing is destroyed, the override simply changes where a process is placed.
public struct GroupingOverrides: Sendable {
    /// Processes the user pulled out of their inferred family.
    public var detached: Set<ProcessIdentity>
    /// Processes the user placed into a specific family, by bundle path.
    public var attached: [ProcessIdentity: String]

    public init(detached: Set<ProcessIdentity> = [], attached: [ProcessIdentity: String] = [:]) {
        self.detached = detached
        self.attached = attached
    }

    public static let none = GroupingOverrides()
}

public enum FamilyGrouper {
    /// Groups processes into application families.
    ///
    /// Grouping keys on the **outermost `.app` in the executable path**, not the
    /// signed bundle identifier: helpers report their own identifier
    /// (`net.imput.helium.helper.renderer`), not the parent's, so the signature
    /// identifies a process without grouping it. The signature is used instead to
    /// decide how confident the association is.
    public static func group(
        _ inputs: [(record: ProcessRecord, resolved: ResolvedIdentity)],
        overrides: GroupingOverrides = .none
    ) -> [ProcessFamily] {
        var bundled: [String: [FamilyMember]] = [:]
        var standalone: [ProcessFamily] = []
        let parents = ParentIndex(inputs)

        for input in inputs {
            let identity = input.record.identity

            if let forced = overrides.attached[identity] {
                bundled[forced, default: []].append(
                    FamilyMember(record: input.record, resolved: input.resolved,
                                 membership: .userAssigned))
                continue
            }

            let bundlePath = overrides.detached.contains(identity) ? nil : input.resolved.appBundlePath
            guard let bundlePath else {
                // No bundle of its own. If an application started it, that is the
                // application responsible for its CPU — 14 shells under a terminal
                // belong with the terminal, not as 14 unrelated rows.
                if !overrides.detached.contains(identity),
                   let parent = parents.bundleOfParent(of: input.record) {
                    bundled[parent.bundlePath, default: []].append(
                        FamilyMember(
                            record: input.record, resolved: input.resolved,
                            membership: .byParent(
                                reason: "started by \(parent.parentCommand)")))
                } else {
                    standalone.append(standaloneFamily(input.record, input.resolved))
                }
                continue
            }

            bundled[bundlePath, default: []].append(
                FamilyMember(record: input.record, resolved: input.resolved,
                             membership: .certain)  // refined below, once the family's own id is known
            )
        }

        let applications = bundled.map { path, members in
            ProcessFamily(
                id: path,
                // Prefer the bundle's own declared name over its folder name:
                // "BrowserApp" rather than a path component that happens to match.
                //
                // Only members that live inside the bundle may name it. A process
                // grouped here because the application started it carries its own
                // name — a shell under a terminal is `zsh` — and members arrive in
                // whatever order the snapshot's dictionary yields, so taking the
                // first name of any kind would let the family be called `zsh` on one
                // sweep and by its real name on the next.
                displayName: members.lazy
                    .filter { if case .byParent = $0.membership { false } else { true } }
                    .compactMap { $0.resolved.friendlyName }.first
                    ?? displayName(forBundle: path),
                bundlePath: path,
                members: classify(members, bundlePath: path, parents: parents)
            )
        }

        return (applications + standalone).sorted { $0.displayName < $1.displayName }
    }

    /// Convenience over a live snapshot.
    public static func group(
        snapshot: ProcessSnapshot,
        resolver: ProcessIdentityResolver,
        overrides: GroupingOverrides = .none
    ) -> [ProcessFamily] {
        group(
            snapshot.records.values.map { ($0, resolver.identity(for: $0.identity)) },
            overrides: overrides
        )
    }

    // MARK: - Confidence

    /// Decides per-member confidence once the family's own identifier is known.
    ///
    /// The family's identifier comes from its main executable — the one directly in
    /// `Contents/MacOS`. A member whose signed identifier shares that prefix is a
    /// genuine helper. A member executing from inside the bundle whose signature
    /// says otherwise is flagged: it may be a legitimate subprocess or an unrelated
    /// binary that merely lives there.
    static func classify(
        _ members: [FamilyMember], bundlePath: String, parents: ParentIndex
    ) -> [FamilyMember] {
        let mainExecutablePrefix = bundlePath + "/Contents/MacOS/"
        let familyID = members.first {
            ($0.resolved.executablePath?.hasPrefix(mainExecutablePrefix) ?? false)
        }?.resolved.bundleID

        return members.map { member in
            if case .userAssigned = member.membership { return member }
            if case .byParent = member.membership { return member }

            // The parent link is independent evidence for what the path claims.
            // Where they agree there is nothing left to qualify, so the member is
            // certain even when the signature could not corroborate it.
            let parentAgrees = parents.bundleOfParent(of: member.record)?.bundlePath == bundlePath

            guard let familyID, let memberID = member.resolved.bundleID else {
                // No signature to corroborate with. The path is still evidence, but
                // weaker on its own.
                if parentAgrees { return FamilyMember(
                    record: member.record, resolved: member.resolved, membership: .certain) }
                return FamilyMember(
                    record: member.record, resolved: member.resolved,
                    membership: member.resolved.bundleID == nil
                        ? .uncertain(reason: "matched by path only; no code signature")
                        : .certain)
            }
            if memberID == familyID || memberID.hasPrefix(familyID + ".") {
                return member  // certain
            }
            if parentAgrees { return FamilyMember(
                record: member.record, resolved: member.resolved, membership: .certain) }
            return FamilyMember(
                record: member.record, resolved: member.resolved,
                membership: .uncertain(
                    reason: "runs from inside the bundle but is signed as \(memberID)"))
        }
    }

    // MARK: - Naming

    static func displayName(forBundle path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    private static func standaloneFamily(
        _ record: ProcessRecord, _ resolved: ResolvedIdentity
    ) -> ProcessFamily {
        ProcessFamily(
            id: "pid:\(record.identity.pid):\(record.identity.startTime)",
            // Never the bare command: at 16 bytes it is a fragment, and showing a
            // fragment as though it were a name breaks FR-002.
            displayName: resolved.displayName(command: record.command),
            bundlePath: nil,
            members: [FamilyMember(record: record, resolved: resolved, membership: .certain)]
        )
    }
}
