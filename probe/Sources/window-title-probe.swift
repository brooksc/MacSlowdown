import AppKit
import CoreGraphics
import Foundation
var log = ""
func emit(_ s: String) { log += s + "\n" }
emit("sandboxed: \(NSHomeDirectory().contains("/Containers/"))")

// 1. Window list without titles (no permission needed historically)
let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let list = (CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]]) ?? []
emit("windows returned: \(list.count)")

var withOwner = 0, withName = 0, nonEmptyName = 0
var samples: [String] = []
for w in list {
    if w[kCGWindowOwnerName as String] as? String != nil { withOwner += 1 }
    if let n = w[kCGWindowName as String] as? String {
        withName += 1
        if !n.isEmpty {
            nonEmptyName += 1
            if samples.count < 5 {
                let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
                samples.append("\(owner): \"\(n)\"")
            }
        }
    }
}
emit("with owner name : \(withOwner)/\(list.count)")
emit("with kCGWindowName key : \(withName)/\(list.count)")
emit("with NON-EMPTY title   : \(nonEmptyName)/\(list.count)")
samples.forEach { emit("   \($0)") }

// 2. Screen recording permission status (titles require it since 10.15)
let hasScreenRecording = CGPreflightScreenCaptureAccess()
emit("CGPreflightScreenCaptureAccess: \(hasScreenRecording)")

// 3. Accessibility API route
emit("AXIsProcessTrusted: \(AXIsProcessTrusted())")

try? log.write(toFile: NSHomeDirectory() + "/wintitle-result.txt", atomically: true, encoding: .utf8)
exit(0)
