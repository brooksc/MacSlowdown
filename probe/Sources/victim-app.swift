// A do-nothing LSUIElement app, used only as something for the FR-046
// exit-status probe to watch terminate.
//
// It has to be a real NSApplication, because the question is whether
// NSWorkspace.didTerminateApplicationNotification distinguishes a crashed .app
// from a quit one, and NSWorkspace only knows about registered applications.
// LSUIElement keeps it off the Dock and off the screen entirely.
//
// The harness spawns it and the harness crashes it. Nothing else is signalled.

import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// VICTIM_LIFETIME gives this instance a clean, voluntary exit(0) after N
// seconds. That is the comparison case: one instance is SIGKILLed and one quits
// of its own accord, and the question is whether NSWorkspace reports them
// differently. The 180 s default is a hard stop so a failed harness run cannot
// leave the process behind.
let lifetime = Double(ProcessInfo.processInfo.environment["VICTIM_LIFETIME"] ?? "") ?? 180
DispatchQueue.global().asyncAfter(deadline: .now() + lifetime) { exit(0) }
app.run()
