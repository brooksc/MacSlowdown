import Foundation
import Testing

@testable import Metrics

private func mounted(
    path: String, name: String, kind: VolumeKind, state: VolumeState,
    format: String? = "APFS"
) -> MountedVolume {
    MountedVolume(url: URL(fileURLWithPath: path), name: name, kind: kind,
                  formatDescription: format, state: state)
}

@Suite("Volume inventory")
struct VolumeInventoryTests {
    /// FR-041: the startup volume is always present and always measured, so the
    /// screen has something to be about.
    @Test("The live inventory contains the startup volume, measured")
    func startupVolumeIsMeasured() throws {
        let volumes = VolumeInventory.mounted()
        let found = volumes.first(where: \.isStartupVolume)
        let startup = try #require(found)
        let capacity = try #require(startup.capacity)

        #expect(startup.kind == .startup)
        #expect(capacity.totalBytes > 0)
        #expect(capacity.availableBytes <= capacity.totalBytes)
    }

    /// FR-002, FR-010: every mounted volume is in exactly one state, and every
    /// state that is not a measurement carries a reason. Nothing is dropped.
    @Test("Every mounted volume is either measured or carries a reason")
    func nothingIsSilentlyOmitted() {
        for volume in VolumeInventory.mounted() {
            switch volume.state {
            case .measured(let capacity):
                #expect(capacity.totalBytes > 0)
            case .unreadable(let reason), .excluded(let reason):
                #expect(!reason.isEmpty, "\(volume.name) was set aside with no reason")
            }
        }
    }

    /// The inventory answers "what is mounted"; the snapshot answers "what can be
    /// measured". The second is a subset of the first, never the whole picture.
    @Test("The measurable snapshot is a subset that keeps unreadable volumes")
    func snapshotKeepsUnreadableVolumes() {
        let volumes = [
            mounted(path: "/", name: "Macintosh HD", kind: .startup,
                    state: .measured(VolumeCapacity(
                        url: URL(fileURLWithPath: "/"), name: "Macintosh HD",
                        isStartupVolume: true, isRemovable: false, isNetwork: false,
                        totalBytes: 1_000_000_000_000, availableBytes: 96_000_000_000,
                        purgeableEstimateBytes: 48_000_000_000))),
            mounted(path: "/Volumes/design-share", name: "design-share", kind: .network,
                    state: .unreadable(reason: "Network volumes are not reported to "
                                       + "App Store apps."), format: "SMB"),
            mounted(path: "/Volumes/T7", name: "SAMSUNG T7", kind: .removable,
                    state: .excluded(reason: VolumeInventory.removableExclusionReason)),
        ]

        let snapshot = VolumeInventory.snapshot(volumes)
        #expect(snapshot.volumes.count == 1)
        #expect(snapshot.startupVolume != nil)
        // The network volume is carried through as unreadable rather than dropped.
        #expect(snapshot.unreadable.count == 1)
        #expect(snapshot.unreadable.first?.isNetwork == true)
        // An excluded volume is not a measurement and not a failure, so it appears
        // in neither list — it is only ever shown from the inventory itself.
        #expect(!snapshot.unreadable.contains { $0.name == "SAMSUNG T7" })
    }

    /// A network volume that cannot be read says why, in terms that name the cause
    /// rather than implying the app is broken.
    @Test("A network volume's reason names the network as the cause")
    func networkReasonIsSpecific() {
        let network = UnreadableVolume(url: URL(fileURLWithPath: "/Volumes/share"),
                                       name: "share", isNetwork: true)
        let local = UnreadableVolume(url: URL(fileURLWithPath: "/Volumes/odd"),
                                     name: "odd", isNetwork: false)
        #expect(network.explanation.lowercased().contains("network"))
        #expect(network.explanation != local.explanation)
        #expect(!local.explanation.isEmpty)
    }

    @Test("Excluded volumes name the exclusion rather than disappearing")
    func exclusionIsNamed() {
        let excluded = mounted(path: "/Volumes/T7", name: "SAMSUNG T7", kind: .removable,
                               state: .excluded(reason: VolumeInventory.removableExclusionReason))
        guard case .excluded(let reason) = excluded.state else {
            Issue.record("expected an exclusion")
            return
        }
        #expect(reason.lowercased().contains("excluded"))
        #expect(excluded.capacity == nil)
    }

    @Test("The subtitle omits what the volume did not report")
    func subtitleOmitsUnknowns() {
        let known = mounted(path: "/", name: "Macintosh HD", kind: .startup,
                            state: .unreadable(reason: "x"), format: "APFS")
        #expect(known.subtitle(isInternal: true) == "Startup volume · APFS · internal")

        let unknownFormat = mounted(path: "/", name: "Macintosh HD", kind: .startup,
                                    state: .unreadable(reason: "x"), format: nil)
        #expect(unknownFormat.subtitle(isInternal: nil) == "Startup volume")
        #expect(!unknownFormat.subtitle(isInternal: nil).contains("nil"))
    }

    @Test("Each volume kind carries a word, not only a position in a list")
    func kindsAreLabelled() {
        for kind in [VolumeKind.startup, .internalDisk, .external, .removable, .network] {
            #expect(!kind.label.isEmpty)
        }
        #expect(VolumeKind.network.label == "Network")
    }
}
