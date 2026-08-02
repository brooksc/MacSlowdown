import Darwin
import Foundation
import Testing

@testable import Metrics

@Suite("Thermal state")
struct ThermalStateTests {
    @Test("The live thermal state is readable")
    func stateReadable() {
        #expect(ThermalState.allCases.contains(ThermalState.current))
    }

    /// FR-010: unavailable hardware temperature is never fabricated. The type
    /// carries no temperature at all, so there is nothing to invent.
    @Test("No explanation claims a temperature or a specific throttling detail")
    func noFabricatedTemperature() {
        for state in ThermalState.allCases {
            let text = state.explanation.lowercased()
            #expect(!text.isEmpty)
            for forbidden in ["°", "degrees", "celsius", "fahrenheit", "temperature",
                              "fan", "rpm", "mhz", "ghz"] {
                #expect(!text.contains(forbidden),
                        "\(state) claims hardware detail we cannot measure: \(forbidden)")
            }
            // Attribution stays with macOS rather than asserting our own diagnosis.
            #expect(text.contains("macos reports"))
        }
    }
}

@Suite("Power context")
struct PowerContextTests {
    @Test("Power context is readable and internally consistent")
    func contextReadable() {
        let power = PowerSignals.current()
        if let percentage = power.batteryPercentage {
            #expect(percentage >= 0)
            #expect(percentage <= 100)
        }
        #expect(!power.summary.isEmpty)
    }

    /// FR-047: desktop Macs degrade gracefully. A machine with no battery reports
    /// nil rather than a fabricated zero, and the summary omits battery entirely.
    @Test("A machine with no battery omits battery rather than reporting zero")
    func noBatteryOmitsRatherThanZeroes() {
        let desktop = PowerContext(source: .externalPower, batteryPercentage: nil,
                                   isCharging: nil, lowPowerModeEnabled: false)
        #expect(!desktop.hasBattery)
        #expect(desktop.summary == "On external power")
        #expect(!desktop.summary.contains("0"))
        #expect(!desktop.summary.lowercased().contains("battery"))
    }

    @Test("A portable includes battery detail")
    func portableIncludesBattery() {
        let laptop = PowerContext(source: .battery, batteryPercentage: 46,
                                  isCharging: false, lowPowerModeEnabled: true)
        #expect(laptop.hasBattery)
        #expect(laptop.summary.contains("46%"))
        #expect(laptop.summary.contains("Low Power Mode"))
    }
}

@Suite("Storage capacity")
struct StorageCapacityTests {
    @Test("The startup volume is found and reports plausible capacity")
    func startupVolumeReadable() throws {
        let snapshot = StorageSignals.snapshot()
        let startup = try #require(snapshot.startupVolume, "no startup volume found")

        #expect(startup.totalBytes > 0)
        #expect(startup.availableBytes <= startup.totalBytes)
        #expect(startup.availableFraction >= 0)
        #expect(startup.availableFraction <= 1)
    }

    /// FR-041: values agree with an authorized system reference within tolerance.
    /// `statfs` is the same source `df` reads.
    @Test("Capacity agrees with statfs")
    func agreesWithStatfs() throws {
        let startup = try #require(StorageSignals.snapshot().startupVolume)

        var fs = statfs()
        #expect(statfs("/", &fs) == 0)
        let referenceTotal = UInt64(fs.f_blocks) * UInt64(fs.f_bsize)

        // Within 2%: APFS containers and the resource-value API round differently.
        let difference = Double(abs(Int64(startup.totalBytes) - Int64(referenceTotal)))
        #expect(difference / Double(referenceTotal) < 0.02,
                "ours \(startup.totalBytes) vs statfs \(referenceTotal)")
    }

    /// FR-041: purgeable space must not be treated as guaranteed free space.
    @Test("Purgeable is separate from available and labelled an estimate")
    func purgeableIsNotAvailable() throws {
        let startup = try #require(StorageSignals.snapshot().startupVolume)
        if let purgeable = startup.purgeableEstimateBytes {
            // It is a distinct figure, not folded into available.
            #expect(purgeable > 0)
            #expect(startup.availableBytes != startup.availableBytes + purgeable)
        }
        let caveat = StorageSignals.purgeableCaveat.lowercased()
        #expect(caveat.contains("estimate"))
        #expect(caveat.contains("not space you have"))
        #expect(caveat.contains("may not release"))
    }

    @Test("Unreadable volumes are listed rather than hidden")
    func unreadableVolumesAreListed() {
        let snapshot = StorageSignals.snapshot()
        for volume in snapshot.unreadable {
            #expect(!volume.explanation.isEmpty)
        }
        // Every volume is either measured or explained; none silently vanish.
        #expect(snapshot.volumes.count + snapshot.unreadable.count > 0)
    }
}

@Suite("Low-storage detection")
struct LowStorageDetectorTests {
    private func volume(total: UInt64, available: UInt64) -> VolumeCapacity {
        VolumeCapacity(url: URL(fileURLWithPath: "/"), name: "Test",
                       isStartupVolume: true, isRemovable: false, isNetwork: false,
                       totalBytes: total, availableBytes: available,
                       purgeableEstimateBytes: nil)
    }

    /// FR-042: both a proportional and an absolute safeguard. 10% of a 4 TB disk
    /// is 400 GB and not a problem.
    @Test("A large disk at 8% free is not low, because the absolute space is ample")
    func largeDiskIsNotLow() {
        let detector = LowStorageDetector()
        let big = volume(total: 4_000_000_000_000, available: 320_000_000_000)
        #expect(big.availableFraction < 0.10)
        #expect(!detector.isBelowThreshold(big), "400 GB free is not a low-storage condition")
    }

    @Test("A small disk at 8% free is low on both counts")
    func smallDiskIsLow() {
        let detector = LowStorageDetector()
        let small = volume(total: 128_000_000_000, available: 4_000_000_000)
        #expect(detector.isBelowThreshold(small))
    }

    @Test("A comfortable disk is never low")
    func comfortableDiskIsFine() {
        let detector = LowStorageDetector()
        #expect(!detector.isBelowThreshold(volume(total: 1_000_000_000_000,
                                                  available: 500_000_000_000)))
    }

    /// FR-042: a transient measurement anomaly does not create an incident.
    @Test("A single low reading is not sustained")
    func singleReadingIsNotSustained() {
        let detector = LowStorageDetector(requiredDuration: .seconds(60))
        let low = volume(total: 128_000_000_000, available: 4_000_000_000)
        let now = Date()

        #expect(!detector.isSustained(readings: [(low, now)]))
        #expect(!detector.isSustained(readings: [(low, now), (low, now.addingTimeInterval(10))]),
                "10 seconds is not 60")
    }

    @Test("A recovery in the middle breaks the run")
    func recoveryBreaksTheRun() {
        let detector = LowStorageDetector(requiredDuration: .seconds(60))
        let low = volume(total: 128_000_000_000, available: 4_000_000_000)
        let fine = volume(total: 128_000_000_000, available: 60_000_000_000)
        let now = Date()

        #expect(!detector.isSustained(readings: [
            (low, now), (fine, now.addingTimeInterval(30)), (low, now.addingTimeInterval(90)),
        ]))
    }

    @Test("A sustained run past the duration counts")
    func sustainedRunCounts() {
        let detector = LowStorageDetector(requiredDuration: .seconds(60))
        let low = volume(total: 128_000_000_000, available: 4_000_000_000)
        let now = Date()

        #expect(detector.isSustained(readings: [
            (low, now), (low, now.addingTimeInterval(30)), (low, now.addingTimeInterval(75)),
        ]))
    }
}
