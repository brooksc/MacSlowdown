import AppKit
import Metrics
import SwiftUI

/// How the glyph is drawn once accessibility settings are taken into account.
///
/// A value rather than a pile of `if`s in the view, so the rule "under Increase
/// Contrast the fills go to pure black/white outlines" is a fact a test can read
/// back. What a test cannot do is judge the result — that needs eyes on a menu bar.
struct MenuBarIconTreatment: Equatable, Sendable {
    /// Whether colour is applied at all. Under Increase Contrast it is not: the
    /// glyph is drawn in the foreground colour, which is pure black or white
    /// against the strip. Nothing is lost, because the state was never carried by
    /// hue (FR-034).
    var usesTint: Bool
    /// How a bar that is *not* filled is drawn.
    var unfilled: Unfilled

    enum Unfilled: Equatable, Sendable {
        /// A dimmed fill. The default, and the closest to the design's rendering.
        case dimmed
        /// A stroked outline with nothing behind it. Used whenever the user has
        /// asked for increased contrast or reduced transparency, both of which are
        /// requests not to convey anything by a washed-out fill.
        case outline
    }

    static func resolve(increaseContrast: Bool, reduceTransparency: Bool) -> MenuBarIconTreatment {
        MenuBarIconTreatment(
            usesTint: !increaseContrast,
            unfilled: increaseContrast || reduceTransparency ? .outline : .dimmed)
    }

    /// What the system currently asks for, read from AppKit rather than from the
    /// SwiftUI environment so it is reachable outside a view — including from a
    /// test, which is the only part of this that can be checked without looking.
    @MainActor
    static var current: MenuBarIconTreatment {
        let workspace = NSWorkspace.shared
        return resolve(
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency)
    }
}

extension MenuBarIconTint {
    /// Nil means "no colour" — the glyph is drawn in the menu bar's own foreground
    /// colour as a template image, like every other icon in the strip.
    var color: Color? {
        switch self {
        case .none: nil
        // Deliberately the system red rather than design 2d's muted tone. It is now
        // reserved for a severe incident, and a colour that rare has to be worth
        // looking at when it does appear (TASK-89).
        case .red: .red
        }
    }
}

/// The three-bar silhouette of design 2d.
///
/// The bars are at fixed heights and only their *fill* changes with state, which
/// is what lets a 250 ms cross-fade be a cross-fade: nothing grows, slides, spins
/// or pulses. The design is explicit that a moving menu bar icon during a slowdown
/// is the worst thing this app could do.
struct MenuBarIconGlyph: View {
    let state: MenuBarIconState
    let showsBadge: Bool
    let treatment: MenuBarIconTreatment
    /// Which colour, if any, this presentation is allowed. Most of the time none —
    /// see `MenuBarIcon.tint`.
    var iconTint: MenuBarIconTint = .none

    /// Menu bar content is nominally 16 pt tall; 14 leaves the breathing room the
    /// strip expects on either side.
    private static let side: CGFloat = 14
    private static let barWidth: CGFloat = 3
    private static let barHeights: [CGFloat] = [6, 10, 14]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(Self.barHeights.enumerated()), id: \.offset) { index, height in
                bar(filled: index < state.filledBars, height: height)
            }
        }
        .frame(width: Self.side, height: Self.side, alignment: .bottom)
        .overlay(alignment: .center) { slash }
        .overlay(alignment: .topTrailing) { badge }
        // Colour and opacity only. `state` never changes any frame, so there is
        // nothing here for an animation to move.
        .animation(.easeInOut(duration: MenuBarIcon.crossFadeSeconds), value: state)
        .animation(.easeInOut(duration: MenuBarIcon.crossFadeSeconds), value: showsBadge)
    }

    /// The colour actually used. Two independent reasons to have none: this state
    /// is not severe enough to earn one, or the user asked for increased contrast.
    private var colour: Color? { treatment.usesTint ? iconTint.color : nil }

    private var tint: Color { colour ?? .primary }

    @ViewBuilder
    private func bar(filled: Bool, height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 1, style: .continuous)
        if filled {
            shape.fill(tint).frame(width: Self.barWidth, height: height)
        } else {
            switch treatment.unfilled {
            case .dimmed:
                shape.fill(Color.primary.opacity(0.28))
                    .frame(width: Self.barWidth, height: height)
            case .outline:
                shape.strokeBorder(Color.primary, lineWidth: 1)
                    .frame(width: Self.barWidth, height: height)
            }
        }
    }

    /// The muted state's diagonal. It is the whole reason muted cannot be confused
    /// with normal: the bars go empty *and* a stroke crosses them, so the
    /// difference survives a monochrome menu bar, a colour-blind reader and a
    /// 16 pt render.
    @ViewBuilder
    private var slash: some View {
        if state.isSlashed {
            MenuBarSlash()
                .stroke(Color.primary,
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .frame(width: Self.side, height: Self.side)
        }
    }

    /// The open-incident badge. A ring rather than a plain dot, so it is a distinct
    /// shape at 6 pt rather than a blob that could be a rendering artefact.
    @ViewBuilder
    private var badge: some View {
        if showsBadge {
            // The badge is the thing that says "an episode is being recorded", and
            // it appears for every open incident — including the ones that are not
            // severe enough for colour. It therefore has to be legible in a template
            // image, so it takes the foreground colour unless the glyph is tinted.
            Circle()
                .strokeBorder(colour ?? Color.primary, lineWidth: 1.4)
                .frame(width: 5.5, height: 5.5)
                .offset(x: 2, y: -1)
        }
    }
}

/// Bottom-left to top-right, the direction the design draws it.
struct MenuBarSlash: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset: CGFloat = 1
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
        return path
    }
}

/// The optional 60-second trend (design 2d).
///
/// Every point is a retained sample. Nothing is interpolated to fill the width and
/// nothing is drawn when there are too few readings, because a flat line in the
/// menu bar would read as a quiet machine when the truth is that we have not been
/// watching long enough.
struct MenuBarSparkline: View {
    let points: [SparklinePoint]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let values = points.map(\.value)
                guard let lowest = values.min(), let highest = values.max(),
                      points.count > 1 else { return }
                let range = max(highest - lowest, 1)
                let step = proxy.size.width / CGFloat(points.count - 1)
                for (index, value) in values.enumerated() {
                    let y = proxy.size.height
                        * (1 - CGFloat((value - lowest) / range))
                    let point = CGPoint(x: CGFloat(index) * step, y: y)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
        }
        .frame(width: 28, height: 10)
    }
}

/// Turns the glyph into a bitmap, because a `MenuBarExtra` label will not draw it
/// otherwise.
///
/// **Measured on screen 2026-08-09, not inferred.** With the glyph as live SwiftUI
/// shapes, the status item existed at 1429,5 sized 18x24, its accessibility label
/// read back correctly as "MacSlowdown, high, quits, 1 minute" — and a capture of
/// exactly those 18x24 points was pure black at every pixel. The item occupied the
/// strip and painted nothing. `MenuBarExtra` renders its label into an
/// `NSStatusItem`'s button, which draws `Text` and `Image`; arbitrary shapes are
/// silently dropped.
///
/// Nothing about the design changes here. This renders the same
/// `MenuBarIconGlyph`, so the four states, the slash, the badge and the Increase
/// Contrast treatment are still exactly what the tests assert on — they simply
/// reach the screen now.
@MainActor
enum MenuBarGlyphRenderer {
    static func image(state: MenuBarIconState, showsBadge: Bool,
                      treatment: MenuBarIconTreatment,
                      tint: MenuBarIconTint = .none) -> NSImage? {
        let renderer = ImageRenderer(
            content: MenuBarIconGlyph(
                state: state, showsBadge: showsBadge,
                treatment: treatment, iconTint: tint))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        // Template whenever no colour is actually in use — which since TASK-89 is
        // every state but a severe incident, and every state at all under Increase
        // Contrast. A template image is drawn by macOS in the strip's own
        // foreground colour, so it can never come out dark on dark and it sits with
        // the rest of the menu bar. Only a genuinely tinted glyph opts out, because
        // a template would throw the tint away.
        image.isTemplate = !(treatment.usesTint && tint != .none)
        return image
    }
}

/// The whole menu bar label: glyph, optional readout, one accessibility label.
///
/// Reads `MonitorStore` for its inputs and `MenuBarIconModel` for what is allowed
/// on screen right now. The two are separate because the store describes the
/// machine and the model describes the menu bar, and the rate limiter is the only
/// thing standing between them.
struct MenuBarIconLabel: View {
    let store: MonitorStore

    @State private var model = MenuBarIconModel()
    @AppStorage(MenuBarReadout.storageKey) private var readoutRaw = MenuBarReadout.default.rawValue
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var readout: MenuBarReadout {
        MenuBarReadout(rawValue: readoutRaw) ?? .default
    }

    private var treatment: MenuBarIconTreatment {
        MenuBarIconTreatment.resolve(
            increaseContrast: contrast == .increased,
            reduceTransparency: reduceTransparency)
    }

    var body: some View {
        // Read on every body evaluation, which is what makes the icon follow the
        // store's observation rather than a timer of its own.
        let desired = MenuBarIcon.presentation(for: store.menuBarIconInputs)
        let shown = model.displayed

        HStack(spacing: 3) {
            glyph(shown)
            readoutView
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(shown))
        // The rate limiter is fed from here rather than from inside `body`'s
        // evaluation, because changing observable state while a view is being
        // built is exactly how a "modifying state during view update" warning is
        // earned.
        .task { model.update(to: desired) }
        .onChange(of: desired) { _, new in model.update(to: new) }
    }

    @ViewBuilder
    private func glyph(_ shown: MenuBarIconPresentation) -> some View {
        if let image = MenuBarGlyphRenderer.image(
            state: shown.state, showsBadge: shown.showsBadge,
            treatment: treatment, tint: shown.tint) {
            Image(nsImage: image)
        } else {
            // An SF Symbol rather than nothing. An invisible status item is worse
            // than a plain one, because the user cannot tell it apart from the app
            // not running at all — which is the failure this whole type exists to
            // stop.
            Image(systemName: fallbackSymbolName(shown.state))
        }
    }

    /// Shape still carries the state in the fallback: a different symbol per state,
    /// never the same glyph in a different colour (FR-034).
    private func fallbackSymbolName(_ state: MenuBarIconState) -> String {
        switch state {
        case .normal: "gauge.with.dots.needle.33percent"
        case .elevated: "gauge.with.dots.needle.67percent"
        case .incident: "gauge.with.dots.needle.100percent"
        case .muted: "bell.slash"
        }
    }

    @ViewBuilder
    private var readoutView: some View {
        switch readout {
        case .iconOnly:
            EmptyView()
        case .cpuPercentage:
            // An em dash, never "0%": no reading is not a reading of zero.
            Text(MenuBarIcon.cpuReadout(busyShareOfMachine: busyShare) ?? "—")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
        case .sparkline:
            let points = MenuBarIcon.sparklinePoints(retained: store.retainedSamples)
            if MenuBarIcon.canDrawSparkline(points) {
                MenuBarSparkline(
                    points: points,
                    tint: (treatment.usesTint ? model.displayed.tint.color : nil) ?? .primary)
            }
        }
    }

    private var busyShare: Double? {
        guard let attribution = store.attribution else { return nil }
        return Presentation.busyShareOfMachine(
            percentOfOneCore: attribution.totalBusyPercentOfOneCore,
            logicalCores: store.machine.logicalCores)
    }

    private func accessibilityLabel(_ shown: MenuBarIconPresentation) -> String {
        switch readout {
        case .iconOnly, .sparkline:
            return shown.accessibilityLabel
        case .cpuPercentage:
            return shown.accessibilityLabel + ", "
                + MenuBarIcon.cpuReadoutAccessibilityLabel(busyShareOfMachine: busyShare)
        }
    }
}

// MARK: - Gathering the inputs from the store

extension MonitorStore {
    /// Everything the menu bar icon is derived from, read from the one place that
    /// holds it.
    ///
    /// A computed property rather than stored state: the store already publishes
    /// every field this reads, so recomputing costs a handful of comparisons and
    /// cannot go stale, where a cached copy could.
    var menuBarIconInputs: MenuBarIconInputs {
        let now = Date()
        let incident = openIncident
        // An open incident is judged on what it recorded; a live elevation on what
        // is breaching now. The two are never mixed, because the incident's own
        // attribution is the evidence and live state is a different machine.
        let leading = MenuBarIcon.leadingApplication(incident: incident)
            ?? MenuBarIcon.leadingApplication(attribution: attribution, families: families)

        return MenuBarIconInputs(
            severity: severity,
            incidentIsOpen: incident != nil,
            incidentSeverity: incident?.severity,
            incidentConditions: MenuBarIcon.ordered(incident?.conditions ?? []),
            incidentDuration: incident?.duration,
            elevatedConditions: liveBreachingConditions,
            isMuted: mute.isMuted(at: now),
            muteRemaining: mute.remaining(at: now),
            muteIsIndefinite: MuteAlerts.isIndefinite(mute, now: now),
            leadingApplicationName: leading?.displayName,
            leadingApplicationPolicy: MenuBarIcon.policy(
                for: leading, in: policies.policies)?.classification)
    }

    /// The conditions currently above their line, in the same order the incident
    /// detector would report them.
    ///
    /// Note this is "above the line now", not "sustained": that distinction is the
    /// whole difference between the elevated glyph and the incident glyph, and it
    /// is why elevated is derived from live signals while incident is derived from
    /// the detector.
    var liveBreachingConditions: [IncidentCondition] {
        var conditions: Set<IncidentCondition> = []
        if severity > .normal { conditions.insert(.cpuSaturation) }
        if memoryPressure > .normal { conditions.insert(.memoryPressure) }
        if thermalState != .nominal { conditions.insert(.thermalPressure) }
        if isLowStorage { conditions.insert(.lowStorage) }
        return MenuBarIcon.ordered(conditions)
    }
}
