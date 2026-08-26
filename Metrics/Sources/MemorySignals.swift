import Darwin
import Dispatch
import Foundation
import Synchronization

/// The system's own memory-pressure assessment (FR-007).
///
/// This is deliberately *not* derived from "percent RAM used". A Mac with 2% free
/// memory can be perfectly healthy, because macOS fills unused RAM with cache it
/// will surrender on demand. Only the kernel knows whether that memory is
/// reclaimable, so the kernel's own signal is the one that means anything.
public enum MemoryPressureLevel: Int, Sendable, Comparable, CaseIterable, Codable {
    case normal
    case warning
    case critical

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }

    /// Plain-language meaning. Never implies that cached or in-use memory is
    /// waste — FR-007 requires the interface avoid describing cached memory as
    /// inherently wasted, and FR-036 forbids implying memory can be "freed".
    public var explanation: String {
        switch self {
        case .normal:
            "macOS has enough memory for what you are doing. Memory shown as in use "
                + "includes cache that macOS will reuse when something needs it, which "
                + "is normal and not a problem."
        case .warning:
            "macOS is having to work to find memory, and may be compressing or "
                + "swapping to keep up."
        case .critical:
            "macOS is short of memory and is actively compressing or swapping, which "
                + "can make everything feel slower."
        }
    }
}

/// Raw virtual-memory counters, in bytes.
///
/// Reported as measured, with no editorialising about which portions are "wasted".
public struct MemoryStatistics: Sendable, Equatable {
    public let free: UInt64
    /// Recently used and likely to be used again.
    public let active: UInt64
    /// Not recently used. **Reclaimable, not wasted** — this is the number that
    /// naive monitors misreport as a problem.
    public let inactive: UInt64
    /// Cannot be paged out.
    public let wired: UInt64
    /// Compressed to save space rather than swapped to disk.
    public let compressed: UInt64
    public let pageSize: UInt64
}

public enum MemorySignals {
    /// Current VM statistics. Available under App Sandbox — `host_statistics64`
    /// is a host-level call.
    public static func statistics() -> MemoryStatistics? {
        var size = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
        let page = UInt64(pageSize)

        return MemoryStatistics(
            free: UInt64(stats.free_count) * page,
            active: UInt64(stats.active_count) * page,
            inactive: UInt64(stats.inactive_count) * page,
            wired: UInt64(stats.wire_count) * page,
            compressed: UInt64(stats.compressor_page_count) * page,
            pageSize: page
        )
    }

    /// Polls the kernel's current pressure level.
    ///
    /// `kern.memorystatus_vm_pressure_level` reports 1 = normal, 2 = warning,
    /// 4 = critical. Used to establish the level at launch, since a dispatch
    /// source only reports *changes*.
    public static func currentPressureLevel() -> MemoryPressureLevel {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0
        else { return .normal }
        switch level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }
}

/// Watches for memory-pressure transitions and timestamps them.
///
/// Uses a dispatch source rather than polling so a transition is observed when it
/// happens rather than at the next sample — FR-007 requires transitions be
/// captured within 2 seconds, and the sampling cadence alone would not guarantee
/// that.
public final class MemoryPressureMonitor: Sendable {
    public struct Transition: Sendable, Equatable {
        public let level: MemoryPressureLevel
        public let at: Date
    }

    private struct State {
        var level: MemoryPressureLevel = .normal
        var transitions: [Transition] = []
        var source: DispatchSourceMemoryPressure?
    }

    private let state = Mutex(State())
    private let maximumTransitions: Int

    /// - Parameter initialLevel: the level to start from. Defaults to the live
    ///   machine, which is right for the product — a monitor that began at
    ///   `.normal` on a Mac already under pressure would report a transition that
    ///   never happened. It is a parameter so a test can start from a known level
    ///   rather than from whatever the developer's Mac is doing: three tests here
    ///   passed on an idle machine and failed on a busy one, which reads as
    ///   flakiness and is actually the test asserting on the real world (TASK-92).
    public init(
        maximumTransitions: Int = 200,
        initialLevel: MemoryPressureLevel = MemorySignals.currentPressureLevel()
    ) {
        self.maximumTransitions = maximumTransitions
        state.withLock { $0.level = initialLevel }
    }

    public var level: MemoryPressureLevel { state.withLock { $0.level } }
    public var transitions: [Transition] { state.withLock { $0.transitions } }

    /// Begins watching. `onChange` fires on every transition, on the given queue.
    public func start(
        queue: DispatchQueue = .global(qos: .utility),
        onChange: (@Sendable (Transition) -> Void)? = nil
    ) {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical], queue: queue)

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = source.data
            let level: MemoryPressureLevel =
                event.contains(.critical) ? .critical
                : event.contains(.warning) ? .warning
                : .normal
            if let transition = record(level) {
                onChange?(transition)
            }
        }

        state.withLock { $0.source = source }
        source.resume()
    }

    public func stop() {
        state.withLock { state in
            state.source?.cancel()
            state.source = nil
        }
    }

    /// Records a level, returning the transition if the level actually changed.
    /// Repeated notifications at the same level are not transitions.
    @discardableResult
    func record(_ level: MemoryPressureLevel, at date: Date = Date()) -> Transition? {
        state.withLock { state in
            guard state.level != level else { return nil }
            state.level = level
            let transition = Transition(level: level, at: date)
            state.transitions.append(transition)
            if state.transitions.count > maximumTransitions {
                state.transitions.removeFirst(state.transitions.count - maximumTransitions)
            }
            return transition
        }
    }
}
