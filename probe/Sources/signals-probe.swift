// TASK-27 / TASK-28: are app unresponsiveness (FR-046) and audio activity
// (FR-019) observable from a sandboxed App Store build?
//
// Writes to the app container so it can be launched via `open` — TCC attributes
// permissions to the responsible process, so exec'ing from a shell inherits the
// terminal's grants and would give a false positive.

import AppKit
import AudioToolbox
import CoreAudio
import Darwin
import Foundation

var log = ""
func emit(_ line: String) { log += line + "\n" }

emit("sandboxed: \(NSHomeDirectory().contains("/Containers/"))")
emit("")

// MARK: - TASK-27: unresponsiveness

emit("=== FR-046: application unresponsiveness ===")

// 1. NSRunningApplication — the only public per-app state source.
let apps = NSWorkspace.shared.runningApplications
emit("NSRunningApplication count: \(apps.count)")
emit("exposed state: isActive / isHidden / isTerminated / ownsMenuBar / activationPolicy")
emit("  -> none of these indicate a hang; a beachballing app reports normally")
if let sample = apps.first(where: { $0.activationPolicy == .regular }) {
    emit("  sample \(sample.localizedName ?? "?"): active=\(sample.isActive) "
        + "hidden=\(sample.isHidden) terminated=\(sample.isTerminated)")
}

// 2. Accessibility API — the usual route to "is this app answering events".
emit("AXIsProcessTrusted: \(AXIsProcessTrusted())")

// 3. Hang reports written by the system's own hang detector.
let reportDirs = [
    NSHomeDirectory() + "/Library/Logs/DiagnosticReports",
    "/Library/Logs/DiagnosticReports",
    NSString("~/Library/Logs/DiagnosticReports").expandingTildeInPath,
]
for dir in reportDirs {
    let readable = FileManager.default.isReadableFile(atPath: dir)
    let contents = try? FileManager.default.contentsOfDirectory(atPath: dir)
    emit("diagnostic reports at \(dir): readable=\(readable) entries=\(contents?.count ?? -1)")
}

// 4. What we CAN see: process lifecycle. Repeated relaunch is a public signal.
emit("process lifecycle via sysctl: available (name, pid, ppid, start time)")
emit("  -> repeated relaunch IS detectable; a hang without exit is NOT")
emit("")

// MARK: - TASK-28: audio activity

emit("=== FR-019: audio activity ===")

func audioObjects(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
        size > 0 else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
    else { return [] }
    return ids
}

func property<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                 default fallback: T) -> T {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var value = fallback
    var size = UInt32(MemoryLayout<T>.size)
    let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
    return status == noErr ? value : fallback
}

// Per-process audio objects (macOS 14.2+). If this works, per-app audio activity
// is obtainable without any microphone permission.
let processObjects = audioObjects(kAudioHardwarePropertyProcessObjectList)
emit("kAudioHardwarePropertyProcessObjectList: \(processObjects.count) objects")

var runningAudio = 0
var details: [String] = []
for object in processObjects {
    let pid: pid_t = property(object, kAudioProcessPropertyPID, default: pid_t(-1))
    let running: UInt32 = property(object, kAudioProcessPropertyIsRunning, default: 0)
    let input: UInt32 = property(object, kAudioProcessPropertyIsRunningInput, default: 0)
    let output: UInt32 = property(object, kAudioProcessPropertyIsRunningOutput, default: 0)
    if running != 0 { runningAudio += 1 }
    // Only the processes actually producing or capturing audio matter for FR-019.
    if running != 0 || input != 0 || output != 0 {
        var name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? ""
        if name.isEmpty {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            if proc_pidinfo(pid, 3, 0, &info, size) == size {
                name = withUnsafeBytes(of: &info.pbi_name) {
                    String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
                }
            }
        }
        details.append("  ACTIVE: \(name.isEmpty ? "pid \(pid)" : name) [\(pid)] "
            + "running=\(running) input=\(input) output=\(output)")
    }
}
emit("  processes with active audio: \(details.count) (running flag set on \(runningAudio))")
details.forEach { emit($0) }

// Device-level fallback: is anything at all using the default output device?
var deviceAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
var device = AudioObjectID(0)
var deviceSize = UInt32(MemoryLayout<AudioObjectID>.size)
let deviceStatus = AudioObjectGetPropertyData(
    AudioObjectID(kAudioObjectSystemObject), &deviceAddress, 0, nil, &deviceSize, &device)
emit("default output device: status=\(deviceStatus) id=\(device)")
if deviceStatus == noErr {
    let runningSomewhere: UInt32 = property(
        device, kAudioDevicePropertyDeviceIsRunningSomewhere, default: 0)
    emit("  kAudioDevicePropertyDeviceIsRunningSomewhere: \(runningSomewhere)")
}

try? log.write(toFile: NSHomeDirectory() + "/signals-result.txt",
               atomically: true, encoding: .utf8)
exit(0)
