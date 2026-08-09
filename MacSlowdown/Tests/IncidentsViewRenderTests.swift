import AppKit
import SwiftUI
import Testing

@testable import MacSlowdown
@testable import Metrics

/// TASK-51.1: the Incidents pane showed its navigation title and nothing else.
///
/// A unit test cannot assert that a person saw the empty state, but it can assert
/// something stronger than "the branch compiles": lay the real view out offscreen
/// and check that the detail column is not one flat expanse of a single colour.
/// That is exactly the failure that was captured, and it is the part of it a test
/// can hold onto.
///
/// Two things about this harness are easy to get wrong and were both got wrong
/// while writing it, so they are worth stating rather than rediscovering:
///
/// - The hosting view has no opaque background of its own. Read the bitmap
///   without compositing over white and every pixel collapses to the same value,
///   so a perfectly good render reports as blank.
/// - `NSHostingView` is flipped. Take the "top" of the pane as
///   `height - visibleHeight` and you sample the bottom instead, which is blank
///   for an entirely uninteresting reason.
///
/// The window is created so SwiftUI has a real layout context. It is never made
/// key, ordered front or made visible.
@MainActor
private func detailColumnInk<V: View>(_ view: V, size: CGSize) -> Double {
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(
        contentRect: host.frame, styleMask: [.titled, .resizable],
        backing: .buffered, defer: true)
    window.contentView = host
    defer { window.contentView = nil }

    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.6))
    host.layoutSubtreeIfNeeded()

    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return -1 }
    host.cacheDisplay(in: host.bounds, to: rep)

    // The right-hand 60%, skipping the strip the navigation title occupies: this
    // must measure the pane's body, not its chrome.
    let x0 = Int(Double(rep.pixelsWide) * 0.4)
    let y0 = Int(Double(rep.pixelsHigh) * 0.1)
    var counts: [UInt32: Int] = [:]
    for y in stride(from: y0, to: rep.pixelsHigh, by: 3) {
        for x in stride(from: x0, to: rep.pixelsWide, by: 3) {
            guard let colour = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                continue
            }
            let a = colour.alphaComponent
            let r = colour.redComponent * a + (1 - a)
            let g = colour.greenComponent * a + (1 - a)
            let b = colour.blueComponent * a + (1 - a)
            let key = UInt32(r * 255) << 16 | UInt32(g * 255) << 8 | UInt32(b * 255)
            counts[key, default: 0] += 1
        }
    }
    let total = counts.values.reduce(0, +)
    let background = counts.values.max() ?? 0
    return total == 0 ? -1 : Double(total - background) / Double(total)
}

/// The app's own composition, so the test exercises the arrangement that shipped
/// rather than a simplified stand-in.
private struct MainWindowShape<Detail: View>: View {
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        NavigationSplitView {
            List(MainWindowView.Section.allCases, selection: .constant(
                MainWindowView.Section.incidents)) { section in
                Label(section.rawValue, systemImage: section.symbol).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            detail()
        }
    }
}

@MainActor
@Suite("Incidents pane rendering")
struct IncidentsViewRenderTests {
    /// Guards the measurement itself. If this ever fails the other results in
    /// this suite mean nothing, whatever they say.
    @Test("The harness can tell ink from paper")
    func harnessMeasuresSomething() {
        let ink = detailColumnInk(VStack(spacing: 0) { Color.red; Color.blue },
                                  size: CGSize(width: 900, height: 600))
        #expect(ink > 0.3, "ink was \(ink)")
    }

    /// The regression: with nothing recorded, the pane must draw its empty state.
    @Test("With no incidents the detail column is not blank")
    func emptyStateDrawsSomething() {
        let store = MonitorStore()
        #expect(store.openIncident == nil && store.recentIncidents.isEmpty)
        let ink = detailColumnInk(
            MainWindowShape { IncidentsView(store: store) },
            size: CGSize(width: 900, height: 600))
        #expect(ink >= 0.001, "ink was \(ink)")
    }

    /// The real window is wider and much taller than the default. A pane that is
    /// only correct at one size is not correct.
    @Test("The empty state survives the window size the app is actually used at")
    func emptyStateAtRealWindowSize() {
        let ink = detailColumnInk(
            MainWindowShape { IncidentsView(store: MonitorStore()) },
            size: CGSize(width: 1316, height: 876))
        #expect(ink >= 0.001, "ink was \(ink)")
    }

    /// A short pane. `ContentUnavailableView` centres itself in whatever height
    /// it is handed, so a container that measures the height badly hides it
    /// rather than failing loudly.
    @Test("The empty state survives a short pane")
    func emptyStateInAShortPane() {
        let ink = detailColumnInk(
            MainWindowShape { IncidentsView(store: MonitorStore()) },
            size: CGSize(width: 1200, height: 300))
        #expect(ink >= 0.001, "ink was \(ink)")
    }

    /// The populated branch, so the fix to the empty branch cannot quietly break
    /// the list. `MonitorStore` does not expose a setter for its incidents, so
    /// this builds the same rows the view builds.
    @Test("A populated list draws its rows")
    func populatedListDrawsRows() {
        let incidents = (0..<3).map { index in
            Incident(
                id: UUID(), beganAt: Date(timeIntervalSince1970: Double(1000 - index)),
                triggeredAt: Date(), recoveryStartedAt: nil, closedAt: Date(),
                conditions: [.cpuSaturation], severity: .high,
                peakCPUBusyFraction: 0.9, peakMemoryPressure: .normal)
        }
        let ink = detailColumnInk(
            MainWindowShape {
                List(incidents) { IncidentRow(incident: $0) }
                    .navigationTitle("Incidents")
            },
            size: CGSize(width: 900, height: 600))
        #expect(ink >= 0.001, "ink was \(ink)")
    }
}
