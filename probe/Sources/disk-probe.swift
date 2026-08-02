import Foundation
import IOKit
import IOKit.storage
var log = "sandboxed: \(NSHomeDirectory().contains("/Containers/"))\n"
guard let matching = IOServiceMatching("IOBlockStorageDriver") else {
    log += "IOServiceMatching returned nil\n"
    try? log.write(toFile: NSHomeDirectory()+"/disk.txt", atomically: true, encoding: .utf8); exit(0)
}
var iterator: io_iterator_t = 0
let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
log += "IOServiceGetMatchingServices kr=\(kr)\n"
var devices = 0, read: UInt64 = 0, written: UInt64 = 0
while case let drive = IOIteratorNext(iterator), drive != 0 {
    defer { IOObjectRelease(drive) }
    var props: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(drive, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let p = props?.takeRetainedValue() as? [String: Any],
          let s = p[kIOBlockStorageDriverStatisticsKey] as? [String: Any] else { continue }
    if let v = s[kIOBlockStorageDriverStatisticsBytesReadKey] as? NSNumber { read += v.uint64Value }
    if let v = s[kIOBlockStorageDriverStatisticsBytesWrittenKey] as? NSNumber { written += v.uint64Value }
    devices += 1
}
IOObjectRelease(iterator)
log += "devices=\(devices) bytesRead=\(read) bytesWritten=\(written)\n"
log += devices > 0 ? "RESULT: IOKit disk counters AVAILABLE sandboxed\n" : "RESULT: UNAVAILABLE\n"
try? log.write(toFile: NSHomeDirectory()+"/disk.txt", atomically: true, encoding: .utf8)
exit(0)
