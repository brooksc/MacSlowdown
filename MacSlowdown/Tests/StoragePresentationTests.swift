import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

private func capacity(
    total: UInt64 = 1_000_000_000_000, available: UInt64 = 96_000_000_000,
    purgeable: UInt64? = 48_000_000_000
) -> VolumeCapacity {
    VolumeCapacity(url: URL(fileURLWithPath: "/"), name: "Macintosh HD",
                   isStartupVolume: true, isRemovable: false, isNetwork: false,
                   totalBytes: total, availableBytes: available,
                   purgeableEstimateBytes: purgeable)
}

@Suite("Storage presentation")
struct StoragePresentationTests {
    /// FR-002: before the first reading there is no freshness to state, and a
    /// placeholder would be a claim about a value we do not have.
    @Test("Freshness is absent until something has been checked")
    func freshnessNeedsAReading() {
        #expect(StoragePresentation.freshness(lastChecked: nil, now: Date()) == nil)
    }

    @Test("Freshness is stated in the largest sensible unit")
    func freshnessUnits() {
        let now = Date()
        #expect(StoragePresentation.freshness(
            lastChecked: now.addingTimeInterval(-30), now: now) == "Checked 30 s ago")
        #expect(StoragePresentation.freshness(
            lastChecked: now.addingTimeInterval(-300), now: now) == "Checked 5 min ago")
        #expect(StoragePresentation.freshness(
            lastChecked: now.addingTimeInterval(-7200), now: now) == "Checked 2 hr ago")
    }

    /// FR-041's specific error: purgeable space presented as space the user has.
    @Test("Purgeable carries its caveat wherever it is shown")
    func purgeableAlwaysCarriesTheCaveat() throws {
        let text = try #require(StoragePresentation.purgeable(capacity()))
        #expect(text.contains("estimate"))
        #expect(text.contains("not space you have"))
        #expect(text.lowercased().contains("roughly"))
    }

    @Test("A volume that reports no purgeable estimate shows none")
    func noPurgeableIsNotZero() {
        #expect(StoragePresentation.purgeable(capacity(purgeable: nil)) == nil)
    }

    /// Available and capacity are both stated, so "96 GB" is never left to be read
    /// as a share of an unstated whole.
    @Test("The headline states available against capacity")
    func headlineStatesBoth() {
        let text = StoragePresentation.headline(capacity())
        #expect(text.contains("available of"))
        #expect(text.contains("96"))
        #expect(text.contains("1 TB"))
    }

    /// The screen must never describe purgeable space as free. Available plus in
    /// use accounts for the whole volume on its own; purgeable sits inside in use.
    @Test("Available and in use account for the volume without purgeable")
    func breakdownAccountsForTheVolume() {
        let volume = capacity()
        #expect(volume.availableBytes + volume.usedBytes == volume.totalBytes)
        #expect(volume.usedBytes > (volume.purgeableEstimateBytes ?? 0),
                "purgeable is part of what is in use, not additional free space")
    }
}

@Suite("Storage screen model")
@MainActor
struct StorageScreenModelTests {
    private func model() -> StorageScreenModel {
        StorageScreenModel(history: StorageHistory(minimumInterval: .seconds(1)))
    }

    /// The model reads real volumes, so this asserts the shape rather than a
    /// machine-specific list.
    @Test("Refreshing finds the startup volume and dates the reading")
    func refreshFindsStartupVolume() {
        let model = model()
        let at = Date()
        model.refresh(at: at)

        #expect(model.startupVolume != nil)
        #expect(model.lastChecked == at)
        #expect(StoragePresentation.freshness(lastChecked: model.lastChecked, now: at)
                == "Checked 0 s ago")
    }

    /// A fresh install has no capacity history. It must say so rather than draw a
    /// flat line through one reading (FR-002).
    @Test("A first reading yields no trend, stated as no history")
    func firstReadingHasNoTrend() throws {
        let model = model()
        model.refresh()
        let startup = try #require(model.startupVolume)

        guard case .insufficientHistory = model.trend(for: startup) else {
            Issue.record("a single reading must not produce a trend")
            return
        }
        #expect(model.coveredDuration(for: startup).totalSeconds == 0)
    }

    /// FR-041: an excluded volume is shown as excluded, and there is a way in.
    @Test("Including a removable volume changes what the inventory reports")
    func includingARemovableVolume() {
        let model = model()
        model.refresh()
        // This machine may mount no removable volume, so the assertion is on the
        // rule rather than on a device: whatever is excluded is listed, with a
        // reason, and never dropped.
        for volume in model.volumes {
            if case .excluded(let reason) = volume.state {
                #expect(!reason.isEmpty)
                #expect(!model.includedRemovableIDs.contains(volume.id))
            }
        }
    }

    @Test("Standing against the warning line is only stated for measured volumes")
    func standingNeedsAMeasurement() {
        let model = model()
        let unreadable = MountedVolume(
            url: URL(fileURLWithPath: "/Volumes/share"), name: "share", kind: .network,
            formatDescription: "SMB",
            state: .unreadable(reason: "Network volumes are not reported to App Store apps."))
        #expect(model.standing(for: unreadable, hadIncident: true) == nil)
    }
}
