import Darwin
import Foundation
import Metrics

// What did parent-PID grouping actually change on this machine?

@main
struct GroupingProbe {
    static func main() {
        let sampler = ProcessSampler()
        let resolver = ProcessIdentityResolver()
        let snapshot = sampler.snapshot()
        let families = FamilyGrouper.group(snapshot: snapshot, resolver: resolver)

        let spawned = families.filter { $0.spawnedMemberCount > 0 }
        let uncertain = families.filter { $0.hasUncertainMembers }

        print("processes: \(snapshot.records.count)")
        print("families:  \(families.count)")
        print("")
        print("families that absorbed a spawned process: \(spawned.count)")
        for family in spawned.sorted(by: { $0.spawnedMemberCount > $1.spawnedMemberCount }) {
            print("  \(family.displayName): \(family.members.count) members, "
                  + "\(family.spawnedMemberCount) spawned")
            for member in family.members where {
                if case .byParent = member.membership { return true }
                return false
            }() {
                if case .byParent(let reason) = member.membership {
                    print("     - \(member.record.command)  [\(reason)]")
                }
            }
        }

        print("")
        print("families still showing an uncertainty marker: \(uncertain.count)")
        for family in uncertain {
            for member in family.members where member.membership.isUncertain {
                if case .uncertain(let reason) = member.membership {
                    print("  \(family.displayName) / \(member.record.command): \(reason)")
                }
            }
        }

        let standalone = families.count { $0.isStandalone }
        print("")
        print("standalone processes (own row, no application): \(standalone)")
    }
}
