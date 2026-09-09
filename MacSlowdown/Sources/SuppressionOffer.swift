import Foundation
import Metrics

/// The suppression sheet's content (design 5f, FR-016 amendment 1).
///
/// Kept out of the view for the reason every presentation type here is: the claims
/// the sheet makes — that one choice is narrower than another, that none of them
/// stops recording, that the app-scoped option leaves other conditions alone — are
/// claims about behaviour, and a claim about behaviour should be checkable without
/// putting anything on screen.
///
/// **Three complete sentences, ordered by how much they give up**, and no pickers
/// or steppers. The subject is whatever the person was just annoyed by, so it is
/// passed in rather than chosen: someone reaching for this is trying to make an
/// interruption stop, and every control between them and that is a control they
/// did not ask for.
struct SuppressionOffer: Equatable {
    /// The application the condition was attributed to, or nil when it was not
    /// attributed to one. FR-055's unattributable share is often the largest part
    /// of a reading, so "no application" is an ordinary case here, not an error —
    /// and when it happens the application-scoped sentence is simply not offered
    /// rather than offered against a guess.
    let application: String?
    let condition: IncidentCondition

    init(application: String?, condition: IncidentCondition) {
        self.application = application
        self.condition = condition
    }

    enum Choice: String, Identifiable, CaseIterable {
        /// Quiet until logout or restart, for everything.
        case session
        /// Permanent, this application, this condition.
        case applicationAndCondition
        /// Permanent, this condition, any application.
        case conditionAnywhere

        var id: String { rawValue }
    }

    struct Option: Identifiable, Equatable {
        let choice: Choice
        let title: String
        let detail: String
        var id: String { choice.rawValue }
    }

    static let title = "Stop telling you about this?"

    /// The line under the title. Deliberately **not** "held the largest measurable
    /// share": that ranking is incomplete by construction, and a sheet that leads
    /// with a rank invites a rule keyed on one — the exact instability amendment 1
    /// removes.
    var subtitle: String {
        guard let application else {
            return "MacSlowdown could not attribute this "
                + "\(condition.label.lowercased()) to an application."
        }
        return "\(application) was one of the measurable contributors to this "
            + "\(condition.label.lowercased())."
    }

    /// The footer. It is the point of the sheet rather than a caption: a user who
    /// silences an alert and later finds their history has gaps in it would be
    /// right to feel misled.
    static let footer =
        "Whatever you pick is listed in Settings and reversible. "
        + "Nothing here stops MacSlowdown recording."

    var options: [Option] {
        var options = [
            Option(choice: .session,
                   title: SessionQuiet.title,
                   detail: SessionQuiet.offerDetail),
        ]
        if let application {
            options.append(Option(
                choice: .applicationAndCondition,
                title: "\(condition.label) from \(application) is expected",
                detail: "Permanent, and only \(condition.label.lowercased()), and only "
                    + "\(application). \(stillHeardSentence(application: application))"))
        }
        options.append(Option(
            choice: .conditionAnywhere,
            title: "Never tell me about \(condition.label.lowercased())",
            detail: "Any app. Still recorded, still in the overview."))
        return options
    }

    /// The sentence that makes the narrow option's narrowness concrete, naming a
    /// condition the user would *still* hear about from the same application.
    ///
    /// Derived from `announcesByDefault` rather than written out, so it cannot
    /// promise an alert that the default policy does not send — the failure mode
    /// this repository keeps hitting, where copy outlives the behaviour it
    /// describes.
    private func stillHeardSentence(application: String) -> String {
        guard let other = IncidentCondition.allCases
            .filter({ $0 != condition && $0.announcesByDefault })
            .sorted(by: { $0.label < $1.label })
            .first
        else {
            return "Other conditions from \(application) are unaffected."
        }
        return "You'd still hear about \(application) and "
            + "\(other.label.lowercased())."
    }
}

/// Carrying out a choice from the sheet (FR-016 amendment 1).
///
/// Separate from `SuppressionOffer` so the sentences can be checked without a
/// store, and separate from the view so the *effect* can be checked without a
/// screen. Each case writes to exactly one place, and all three of those places
/// are listed on the Rules screen — which is what makes criterion 3 ("every rule
/// visible and reversible from one place") a property of the code rather than of
/// a screenshot.
@MainActor
enum SuppressionOfferAction {
    static func apply(
        _ choice: SuppressionOffer.Choice,
        offer: SuppressionOffer,
        store: MonitorStore = .shared,
        settings: AlertSettings = .shared,
        session: SessionQuiet = .shared
    ) {
        switch choice {
        case .session:
            session.begin()
        case .applicationAndCondition:
            guard let application = offer.application else { return }
            // Merged into any existing rule for the same application rather than
            // replacing it: someone who has already said compiles are expected and
            // now says thermal pressure is too has made two statements, and
            // overwriting the first would silently revoke a decision they never
            // revisited.
            let existing = store.policies.policies.first { $0.displayName == application }
            // A rule the user had set to "watch closely" suppresses nothing, so
            // adding a condition to it would produce a rule that appears in the
            // list and does nothing. Asking to stop being told is a request to
            // suppress, so it becomes `.expected`; a rule already suppressing keeps
            // whatever the user chose.
            let classification: PolicyClassification = existing.map {
                $0.classification.suppressesNotification ? $0.classification : .expected
            } ?? .expected
            store.policies.setPolicy(ApplicationPolicy(
                bundleID: existing?.bundleID,
                bundlePath: existing?.bundlePath,
                displayName: application,
                classification: classification,
                conditions: (existing?.conditions ?? []).union([offer.condition])))
        case .conditionAnywhere:
            settings.setInterrupts(offer.condition, false)
        }
    }
}
