import AppKit
import Foundation
import Testing

@testable import MacSlowdown
@testable import Metrics

/// Design 6a — the popover mid-condition, and the caption that has to fit in it.
@MainActor
@Suite("The popover's two decisions, and the caption width (design 6a)")
struct PopoverDecisionsTests {
    /// **The measurement design's premise got wrong, kept so it cannot drift.**
    ///
    /// 6a proposed reordering the attribution caption because the long form
    /// "wraps to two lines at 11 px in 342 px of caption width". Measured at the
    /// popover's real geometry — 340 pt wide, 14 pt padding either side, and
    /// `.caption2` which resolves to 10 pt, uppercased by `textCase` — the long
    /// form is about 294 pt against 312 available. It fits.
    ///
    /// The reorder is still right, for the reason 6a gave second: it says what is
    /// uncertain before how uncertain, and it clears the width by 77 pt instead of
    /// 17. This test exists so that if the type size, the padding or the longest
    /// confidence label ever changes, the 5% margin the long form was living on
    /// fails here rather than on someone's screen.
    @Test("Both caption forms fit the popover, and the glance form has real headroom")
    func captionFitsThePopover() {
        let font = NSFont.systemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .caption2).pointSize,
            weight: .semibold)
        let available: CGFloat = 340 - 28

        func width(_ text: String) -> CGFloat {
            (text.uppercased() as NSString).size(withAttributes: [.font: font]).width
        }

        // Worst case is the longest confidence label.
        let longest = Confidence.allCases.max { width($0.label) < width($1.label) } ?? .moderate
        let long = width(NowPresentation.attributionQualifier(longest))
        let glance = width(NowPresentation.attributionQualifierAtAGlance(longest))

        #expect(long <= available, "the long form no longer fits: \(long) of \(available)")
        #expect(glance <= available)
        #expect(glance < long, "the glance form must be the shorter of the two")
        #expect(available - glance > 60,
                "the glance form's headroom has been eroded to \(available - glance) pt")
    }

    /// The subject leads. A confidence word that does not say what it qualifies is
    /// the collapse FR-065 forbids, so shortening must not have dropped it.
    @Test("The glance form still names what the confidence is about")
    func glanceFormKeepsItsSubject() {
        for confidence in Confidence.allCases {
            let text = NowPresentation.attributionQualifierAtAGlance(confidence)
            #expect(text.hasPrefix("Which app"), "the subject must lead: \(text)")
            #expect(text.contains(confidence.label))
            #expect(!text.contains("%"), "no numerical confidence (FR-065)")
        }
    }

    /// FR-063: the popover must not have regained an impact claim in the space the
    /// deleted sentence left. This is the specific sentence that was removed —
    /// "While that continues, other apps are likely to feel slower" — and the
    /// general class it belonged to.
    @Test("The vacated space carries no claim about the user's experience")
    func noImpactClaimReturned() {
        let forbidden = ["feel slower", "feels slower", "slowing", "is slow",
                         "struggling", "unusable", "you'll notice"]
        for confidence in Confidence.allCases {
            let texts = [
                NowPresentation.attributionQualifier(confidence),
                NowPresentation.attributionQualifierAtAGlance(confidence),
            ]
            for text in texts {
                for phrase in forbidden {
                    #expect(!text.lowercased().contains(phrase),
                            "\"\(phrase)\" returned in: \(text)")
                }
            }
        }
    }
}

/// Design 6b — first run promises what it can do, and admits what it cannot.
@MainActor
@Suite("First run states its limits before its features (design 6b)")
struct FirstRunPromiseTests {
    /// The promise that had to go. "Tell you about slowdowns" set up every later
    /// screen to look like a failure to deliver.
    @Test("Nothing promises to tell the user their Mac was slow")
    func noSlowdownPromise() {
        let copy = [
            FirstRunCopy.title, FirstRunCopy.promise,
            FirstRunCopy.watchesTitle, FirstRunCopy.watchesDetail,
            FirstRunCopy.notificationsTitle, FirstRunCopy.notificationsDetail,
            FirstRunCopy.loginItemTitle, FirstRunCopy.loginItemDetail,
        ]
        for text in copy {
            #expect(!text.lowercased().contains("slowdown"),
                    "first run still promises slowdowns: \(text)")
        }
    }

    /// Both admissions are present and stated as facts rather than buried.
    @Test("The two limits are stated outright")
    func limitsAreStated() {
        #expect(FirstRunCopy.cannotJudgeTitle.contains("can't tell you"))
        #expect(FirstRunCopy.cannotJudgeDetail.contains("leave the verdict to you"))
        #expect(FirstRunCopy.unattributableTitle.contains("invisible to us"))
        // The reason, not just the fact — otherwise it reads as an excuse.
        #expect(FirstRunCopy.unattributable.contains("another user"))
    }

    /// A first run that does not mention the gesture means nobody discovers the
    /// one thing only they can tell us (FR-064).
    @Test("The report gesture is introduced, and asks nothing of the user")
    func reportGestureIsIntroduced() {
        #expect(FirstRunCopy.reportTitle.contains("tell us"))
        #expect(FirstRunCopy.reportDetail.contains("menu bar"))
        #expect(FirstRunCopy.reportDetail.lowercased().contains("no questions"))
    }

    /// The sentence that prevents "why didn't you tell me about the CPU" later.
    @Test("The notification toggle says which conditions interrupt, and why CPU does not")
    func notificationToggleExplainsCPU() {
        #expect(FirstRunCopy.notificationsTitle.lowercased().contains("memory"))
        #expect(FirstRunCopy.notificationsDetail.contains("Not CPU"))
        #expect(FirstRunCopy.notificationsDetail.lowercased().contains("recorded"))
    }
}
