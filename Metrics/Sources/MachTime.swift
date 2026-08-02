import Darwin
import Foundation

/// Conversion between mach absolute time units and wall-clock time.
///
/// `proc_taskinfo.pti_total_{user,system}` and `rusage_info.ri_{user,system}_time`
/// are reported in mach absolute time units, **not** nanoseconds. On Apple Silicon
/// the timebase is 125/3 (41.667 ns per tick), so treating those values as
/// nanoseconds under-reports CPU by roughly 42x. On Intel the timebase is 1:1,
/// which is why much published sample code omits the conversion and still appears
/// to work.
///
/// Verified against `ps %cpu` with a synthetic single-core spinner: 99.2% vs 100.0%.
/// See probe/FINDINGS.md.
public enum MachTime {
    /// Nanoseconds per mach tick on this machine.
    public static let nanosPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()

    /// Converts mach absolute time units to nanoseconds.
    public static func nanos(fromTicks ticks: UInt64) -> Double {
        Double(ticks) * nanosPerTick
    }

    /// Converts mach absolute time units to seconds.
    public static func seconds(fromTicks ticks: UInt64) -> Double {
        nanos(fromTicks: ticks) / 1e9
    }
}

extension Duration {
    /// Total duration in seconds.
    ///
    /// `components.attoseconds` carries only the sub-second remainder; whole
    /// seconds live in `components.seconds`. Reading attoseconds alone silently
    /// truncates any duration of one second or more.
    public var totalSeconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
